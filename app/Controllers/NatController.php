<?php

namespace App\Controllers;

use App\Core\{Database, Auditoria};

class NatController
{
    public function index(): void
    {
        $entradas = Database::fetchAll(
            'SELECT * FROM nat_um_para_um ORDER BY criado_em DESC'
        );

        $this->render('nat/index', 'NAT 1:1', compact('entradas'));
    }

    public function criar(): void
    {
        if (!csrf_verificar()) { json_resposta(['erro' => 'Token inválido.'], 403); }

        $ip_externo = trim($_POST['ip_externo'] ?? '');
        $ip_interno = trim($_POST['ip_interno'] ?? '');
        $descricao  = trim($_POST['descricao']  ?? '');

        if (!filter_var($ip_externo, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) ||
            !filter_var($ip_interno, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
            json_resposta(['erro' => 'IPs inválidos.'], 422);
        }

        $existe = Database::fetch(
            'SELECT id FROM nat_um_para_um WHERE ip_externo = ? OR ip_interno = ?',
            [$ip_externo, $ip_interno]
        );
        if ($existe) {
            json_resposta(['erro' => 'Um dos IPs já está em uso em outra regra NAT.'], 409);
        }

        $id = Database::insert(
            'INSERT INTO nat_um_para_um (ip_externo, ip_interno, descricao) VALUES (?, ?, ?)',
            [$ip_externo, $ip_interno, $descricao ?: '']
        );

        Auditoria::registrar('criar_nat', 'nat_um_para_um', (int)$id, null, [
            'ip_externo' => $ip_externo, 'ip_interno' => $ip_interno,
        ]);

        json_resposta(['sucesso' => 'Regra NAT criada.', 'id' => $id]);
    }

    public function toggle(string $id): void
    {
        if (!csrf_verificar()) { json_resposta(['erro' => 'Token inválido.'], 403); }

        $nat = Database::fetch('SELECT * FROM nat_um_para_um WHERE id = ?', [$id]);
        if (!$nat) { json_resposta(['erro' => 'Regra não encontrada.'], 404); }

        $novo = $nat['ativo'] ? 0 : 1;
        Database::execute('UPDATE nat_um_para_um SET ativo = ? WHERE id = ?', [$novo, $id]);

        $acao = $novo ? 'ativar' : 'desativar';
        $script = config('sistema.scripts_dir') . '/aplicar_nat.sh';
        shell_exec("sudo {$script} {$acao} " . escapeshellarg($nat['ip_externo']) . ' ' . escapeshellarg($nat['ip_interno']) . ' > /dev/null 2>&1 &');

        Auditoria::registrar('toggle_nat', 'nat_um_para_um', (int)$id, $nat, ['ativo' => $novo]);

        json_resposta(['sucesso' => $novo ? 'NAT ativado.' : 'NAT desativado.', 'ativo' => $novo]);
    }

    public function remover(string $id): void
    {
        if (!csrf_verificar()) { json_resposta(['erro' => 'Token inválido.'], 403); }

        $nat = Database::fetch('SELECT * FROM nat_um_para_um WHERE id = ?', [$id]);
        if (!$nat) { json_resposta(['erro' => 'Regra não encontrada.'], 404); }

        // Desativa antes de remover para limpar as regras do kernel
        if ($nat['ativo']) {
            $script = config('sistema.scripts_dir') . '/aplicar_nat.sh';
            shell_exec("sudo {$script} desativar " . escapeshellarg($nat['ip_externo']) . ' ' . escapeshellarg($nat['ip_interno']) . ' > /dev/null 2>&1');
        }

        Database::execute('DELETE FROM nat_um_para_um WHERE id = ?', [$id]);
        Auditoria::registrar('remover_nat', 'nat_um_para_um', (int)$id, $nat, null);

        json_resposta(['sucesso' => 'Regra NAT removida.']);
    }

    public function aplicarTodas(): void
    {
        if (!csrf_verificar()) { json_resposta(['erro' => 'Token inválido.'], 403); }

        $script = config('sistema.scripts_dir') . '/aplicar_nftables.sh';
        shell_exec("sudo {$script} > /dev/null 2>&1 &");

        Auditoria::registrar('aplicar_nat_todas', 'nat_um_para_um', null, null, null);

        json_resposta(['sucesso' => 'Regras NAT reaplicadas via nftables.']);
    }

    private function render(string $view, string $titulo, array $dados = []): void
    {
        ob_start();
        view($view, $dados);
        $conteudo = ob_get_clean();
        view('layouts/base', array_merge($dados, [
            'titulo'   => $titulo,
            'modulo'   => 'nat',
            'conteudo' => $conteudo,
        ]));
    }
}
