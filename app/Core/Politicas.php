<?php

namespace App\Core;

/**
 * Ações rápidas de política por equipamento (Relatório Mestre v2.0, seção 6):
 * alterar grupo, bloquear, liberar temporariamente (com expiração e retorno
 * automático) e revogar a liberação. Só atua em regras de IP EXATO; redes CIDR
 * continuam sendo geridas em Grupos e IPs. Toda ação é auditada e enfileira a
 * reaplicação do firewall/Squid pela fila allowlisted.
 */
class Politicas
{
    public const GRUPO_LIBERACAO_AUTOMATICO = 'Liberações temporárias';
    public const MIN_MINUTOS = 5;
    public const MAX_MINUTOS = 10080; // 7 dias

    public static function ipValido(string $ip): bool
    {
        return filter_var($ip, FILTER_VALIDATE_IP) !== false;
    }

    /** Grupos ativos, ordenados por tipo de política. */
    public static function grupos(): array
    {
        return Database::fetchAll("SELECT id,nome,tipo FROM ip_grupos WHERE ativo=1 ORDER BY FIELD(tipo,'liberado','parcial','bloqueado','isento'),nome");
    }

    public static function grupoPorTipo(string $tipo): ?array
    {
        $g = Database::fetch('SELECT id,nome,tipo FROM ip_grupos WHERE ativo=1 AND tipo=? ORDER BY id LIMIT 1', [$tipo]);
        return $g ?: null;
    }

    /** Regras exatas vigentes do IP (inclui a liberação temporária, se houver). */
    public static function regrasExatas(string $ip): array
    {
        return Database::fetchAll(
            'SELECT i.id,i.grupo_id,i.expira_em,i.restaurar_ips,i.origem_acao,g.nome grupo_nome,g.tipo grupo_tipo
             FROM ips i JOIN ip_grupos g ON g.id=i.grupo_id
             WHERE i.endereco=? AND i.ativo=1 AND g.ativo=1 AND (i.expira_em IS NULL OR i.expira_em>NOW())
             ORDER BY i.id',
            [$ip]
        );
    }

    /** Move o IP para o grupo (permanente), retirando-o dos demais. */
    public static function alterarGrupo(string $ip, int $grupoId, ?int $adminId, string $origem = 'alterar_grupo'): array
    {
        if (!self::ipValido($ip)) return ['ok' => false, 'erro' => 'Endereço IP inválido.'];
        $grupo = Database::fetch('SELECT id,nome,tipo FROM ip_grupos WHERE id=? AND ativo=1', [$grupoId]);
        if (!$grupo) return ['ok' => false, 'erro' => 'Grupo não encontrado ou inativo.'];

        $antes = self::regrasExatas($ip);
        $pdo = Database::conectar();
        $pdo->beginTransaction();
        try {
            // Remove só as regras exatas do IP; CIDRs de rede não são tocados.
            $pdo->prepare('DELETE FROM ips WHERE endereco=?')->execute([$ip]);
            $pdo->prepare('INSERT INTO ips (grupo_id,endereco,descricao,origem_acao) VALUES (?,?,?,?)')
                ->execute([$grupoId, $ip, 'Ação rápida do painel', $origem]);
            $pdo->commit();
        } catch (\Throwable $e) {
            $pdo->rollBack();
            return ['ok' => false, 'erro' => 'Não foi possível gravar a alteração.'];
        }
        $tarefa = Tarefas::enfileirar('firewall_apply', [], $adminId, 'firewall_apply');
        Auditoria::registrar($origem, 'ips', null,
            ['ip' => $ip, 'grupos' => array_column($antes, 'grupo_nome')],
            ['ip' => $ip, 'grupo' => $grupo['nome'], 'tipo' => $grupo['tipo'], 'tarefa_id' => $tarefa]);
        return ['ok' => true, 'mensagem' => "{$ip} agora está em “{$grupo['nome']}”. Aplicação enfileirada.", 'tarefa_id' => $tarefa];
    }

    public static function bloquear(string $ip, ?int $adminId): array
    {
        $g = self::grupoPorTipo('bloqueado');
        if (!$g) return ['ok' => false, 'erro' => 'Não há grupo do tipo Bloqueado. Crie um em Grupos e IPs.'];
        return self::alterarGrupo($ip, (int) $g['id'], $adminId, 'bloquear_equipamento');
    }

    /** Libera por N minutos; as regras anteriores voltam sozinhas ao vencer. */
    public static function liberarTemporario(string $ip, int $minutos, ?int $adminId): array
    {
        if (!self::ipValido($ip)) return ['ok' => false, 'erro' => 'Endereço IP inválido.'];
        if ($minutos < self::MIN_MINUTOS || $minutos > self::MAX_MINUTOS) {
            return ['ok' => false, 'erro' => 'A duração deve ficar entre ' . self::MIN_MINUTOS . ' minutos e 7 dias.'];
        }
        $pdo = Database::conectar();
        $pdo->beginTransaction();
        try {
            // A mesma linha sincroniza confirmações simultâneas e a rotina de expiração.
            $fila = $pdo->query('SELECT id FROM fila_expiracao_politicas WHERE id=1 FOR UPDATE');
            if (!$fila->fetchColumn()) throw new \RuntimeException('Fila de políticas indisponível.');

            $regras = self::regrasExatas($ip);
            $temp = Database::fetch(
                "SELECT i.id,i.restaurar_ips,g.id grupo_id,g.nome
                 FROM ips i JOIN ip_grupos g ON g.id=i.grupo_id
                 WHERE i.endereco=? AND i.origem_acao='liberacao_temporaria' AND i.ativo=1
                   AND g.ativo=1 AND g.tipo='liberado' ORDER BY i.id DESC LIMIT 1",
                [$ip]
            );
            $alvo = $temp ? ['id' => $temp['grupo_id'], 'nome' => $temp['nome']] : self::grupoPorTipo('liberado');
            if (!$alvo) {
                $pdo->prepare("INSERT INTO ip_grupos (nome, descricao, tipo) VALUES (?, ?, 'liberado')")
                    ->execute([self::GRUPO_LIBERACAO_AUTOMATICO, 'Grupo criado pela ação de liberação temporária.']);
                $alvo = ['id' => (int) $pdo->lastInsertId(), 'nome' => self::GRUPO_LIBERACAO_AUTOMATICO];
            }
            $suspensas = array_column(array_filter($regras, static fn(array $r): bool =>
                $r['origem_acao'] !== 'liberacao_temporaria'), 'id');
            if ($temp) { // renovar: só estende o prazo
                $pdo->prepare('UPDATE ips SET expira_em = NOW() + INTERVAL ' . (int) $minutos . ' MINUTE WHERE id=?')->execute([(int) $temp['id']]);
                $restaurar = $temp['restaurar_ips'];
            } else {
                if ($suspensas) {
                    $in = implode(',', array_fill(0, count($suspensas), '?'));
                    $pdo->prepare("UPDATE ips SET ativo=0 WHERE id IN ($in)")->execute($suspensas);
                }
                $restaurar = $suspensas ? implode(',', $suspensas) : null;
                $pdo->prepare('INSERT INTO ips (grupo_id,endereco,descricao,expira_em,restaurar_ips,origem_acao) VALUES (?,?,?,NOW() + INTERVAL ' . (int) $minutos . ' MINUTE,?,?)')
                    ->execute([(int) $alvo['id'], $ip, 'Liberação temporária', $restaurar, 'liberacao_temporaria']);
            }
            $pdo->exec('UPDATE fila_expiracao_politicas
                        SET pendente=1, tarefa_firewall=NULL WHERE id=1');
            $pdo->commit();
        } catch (\Throwable $e) {
            $pdo->rollBack();
            return ['ok' => false, 'erro' => 'Não foi possível gravar a liberação.'];
        }

        // O cron também lê o pedido persistente e repete a aplicação se necessário.
        $tarefa = null;
        try {
            $pdo->beginTransaction();
            $fila = $pdo->query('SELECT tarefa_firewall FROM fila_expiracao_politicas WHERE id=1 FOR UPDATE')->fetch();
            $tarefa = $fila['tarefa_firewall'] ?: Tarefas::enfileirar('firewall_apply', [], $adminId, 'firewall_apply');
            $pdo->prepare('UPDATE fila_expiracao_politicas SET tarefa_firewall=? WHERE id=1')->execute([$tarefa]);
            $pdo->commit();
        } catch (\Throwable $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            error_log('[GWOS políticas] ' . $e->getMessage());
        }
        Auditoria::registrar('liberar_temporario', 'ips', null,
            ['ip' => $ip, 'grupos' => array_column($regras, 'grupo_nome')],
            ['ip' => $ip, 'minutos' => $minutos, 'grupo' => $alvo['nome'], 'retorno' => $restaurar, 'tarefa_id' => $tarefa]);
        return ['ok' => true, 'mensagem' => "{$ip} liberado por {$minutos} min; depois disso volta à política anterior. Atualização do firewall pendente.", 'tarefa_id' => $tarefa];
    }

    /** Encerra a liberação temporária antes do prazo e restaura as regras. */
    public static function revogarTemporario(string $ip, ?int $adminId): array
    {
        if (!self::ipValido($ip)) return ['ok' => false, 'erro' => 'Endereço IP inválido.'];
        $t = Database::fetch("SELECT id,restaurar_ips FROM ips WHERE endereco=? AND origem_acao='liberacao_temporaria' AND ativo=1 LIMIT 1", [$ip]);
        if (!$t) return ['ok' => false, 'erro' => 'Este equipamento não tem liberação temporária ativa.'];
        $pdo = Database::conectar();
        $pdo->beginTransaction();
        try {
            $pdo->prepare('DELETE FROM ips WHERE id=?')->execute([(int) $t['id']]);
            self::restaurar($pdo, (string) $t['restaurar_ips']);
            $pdo->commit();
        } catch (\Throwable $e) {
            $pdo->rollBack();
            return ['ok' => false, 'erro' => 'Não foi possível revogar a liberação.'];
        }
        $tarefa = Tarefas::enfileirar('firewall_apply', [], $adminId, 'firewall_apply');
        Auditoria::registrar('revogar_liberacao', 'ips', (int) $t['id'], ['ip' => $ip], ['tarefa_id' => $tarefa]);
        return ['ok' => true, 'mensagem' => "Liberação temporária de {$ip} revogada. Aplicação enfileirada.", 'tarefa_id' => $tarefa];
    }

    /** Reativa as regras suspensas (ids numéricos, validados). */
    public static function restaurar(\PDO $pdo, string $lista): void
    {
        $ids = array_values(array_filter(array_map('intval', explode(',', $lista)), static fn(int $i): bool => $i > 0));
        if (!$ids) return;
        $in = implode(',', array_fill(0, count($ids), '?'));
        $pdo->prepare("UPDATE ips SET ativo=1 WHERE id IN ($in)")->execute($ids);
    }
}
