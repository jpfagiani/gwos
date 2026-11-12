<?php

namespace App\Core;

final class CredenciamentoMonitor
{
    public static function portal(): ?string
    {
        $ip = Estado::obter('IP_GATEWAY');
        $porta = filter_var(Estado::obter('ACESSO_PORTA', '8444'), FILTER_VALIDATE_INT, [
            'options' => ['min_range' => 1, 'max_range' => 65535],
        ]);
        return filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) && $porta
            ? "https://{$ip}:{$porta}/acesso" : null;
    }

    public static function emitir(string $ip): string
    {
        $codigo = bin2hex(random_bytes(32));
        Database::execute('DELETE FROM convites_monitor WHERE expira_em<=NOW()');
        Database::execute(
            'INSERT INTO convites_monitor (ip,codigo_hash,expira_em) VALUES (?,?,DATE_ADD(NOW(), INTERVAL 10 MINUTE))
             ON DUPLICATE KEY UPDATE codigo_hash=VALUES(codigo_hash), expira_em=VALUES(expira_em)',
            [$ip, hash('sha256', $codigo)]
        );
        return $codigo;
    }

    public static function resgatar(string $codigo): ?array
    {
        if (!preg_match('/^[a-f0-9]{64}$/D', $codigo)) return null;

        $pdo = Database::conectar();
        $hash = hash('sha256', $codigo);
        $chave = bin2hex(random_bytes(32));
        $pdo->beginTransaction();
        try {
            $convite = Database::fetch(
                'SELECT ip FROM convites_monitor WHERE codigo_hash=? AND expira_em>NOW() FOR UPDATE',
                [$hash]
            );
            if (!$convite) {
                $pdo->rollBack();
                return null;
            }
            $ip = $convite['ip'];
            Database::execute(
                'INSERT INTO monitores_internet (ip,chave_hash) VALUES (?,?)
                 ON DUPLICATE KEY UPDATE chave_hash=VALUES(chave_hash), ciclo_hash=NULL, presente_ate=NULL',
                [$ip, hash('sha256', $chave)]
            );
            Database::execute('DELETE FROM convites_monitor WHERE codigo_hash=?', [$hash]);
            $pdo->commit();
        } catch (\Throwable $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            throw $e;
        }

        try {
            AcessoInternet::sair($ip);
        } catch (\Throwable $e) {
            // O convite já foi consumido. Entrega a chave e registra a falha.
            error_log('[GWOS credenciamento] revogação: ' . $e->getMessage());
        }
        return ['ip' => $ip, 'chave' => $chave];
    }
}
