<?php

namespace App\Controllers;

use App\Core\{Auth, Database, Controller, Auditoria};

class NatController extends Controller
{
    private const SCRIPTS_PERMITIDOS = [
        'nat'      => 'aplicar_nat.sh',
        'nftables' => 'aplicar_nftables.sh',
    ];

    public function index(): void
    {
        Auth::exigir();

        $entradas = Database::fetchAll(
            'SELECT * FROM nat_um_para_um ORDER BY criado_em DESC'
        );

        $this->view('nat/index', compact('entradas'));
    }

    public function criar(): void
    {
        Auth::exigir();
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
        Auth::exigir();
        if (!csrf_verificar()) { json_resposta(['erro' => 'Token inválido.'], 403); }

        $nat = Database::fetch('SELECT * FROM nat_um_para_um WHERE id = ?', [$id]);
        if (!$nat) { json_resposta(['erro' => 'Regra não encontrada.'], 404); }

        $novo = $nat['ativo'] ? 0 : 1;
        Database::execute('UPDATE nat_um_para_um SET ativo = ? WHERE id = ?', [$novo, $id]);

        $acao = $novo ? 'ativar' : 'desativar';
        $this->executarScript('nat', $acao, [$nat['ip_externo'], $nat['ip_interno']]);

        Auditoria::registrar('toggle_nat', 'nat_um_para_um', (int)$id, $nat, ['ativo' => $novo]);

        json_resposta(['sucesso' => $novo ? 'NAT ativado.' : 'NAT desativado.', 'ativo' => $novo]);
    }

    public function remover(string $id): void
    {
        Auth::exigir();
        if (!csrf_verificar()) { json_resposta(['erro' => 'Token inválido.'], 403); }

        $nat = Database::fetch('SELECT * FROM nat_um_para_um WHERE id = ?', [$id]);
        if (!$nat) { json_resposta(['erro' => 'Regra não encontrada.'], 404); }

        if ($nat['ativo']) {
            $this->executarScript('nat', 'desativar', [$nat['ip_externo'], $nat['ip_interno']], wait: true);
        }

        Database::execute('DELETE FROM nat_um_para_um WHERE id = ?', [$id]);
        Auditoria::registrar('remover_nat', 'nat_um_para_um', (int)$id, $nat, null);

        json_resposta(['sucesso' => 'Regra NAT removida.']);
    }

    public function aplicarTodas(): void
    {
        Auth::exigir();
        if (!csrf_verificar()) { json_resposta(['erro' => 'Token inválido.'], 403); }

        $this->executarScript('nftables');
        Auditoria::registrar('aplicar_nat_todas', 'nat_um_para_um', null, null, null);

        json_resposta(['sucesso' => 'Regras NAT reaplicadas via nftables.']);
    }

    // Executa script da whitelist — nunca interpola variáveis externas no comando
    private function executarScript(string $chave, string $acao = '', array $args = [], bool $wait = false): void
    {
        $nome = self::SCRIPTS_PERMITIDOS[$chave] ?? null;
        if (!$nome) return;

        $dir    = config('sistema.scripts_dir', '/opt/gwos/scripts');
        $script = $dir . '/' . $nome;

        $cmd = 'sudo ' . escapeshellarg($script);
        if ($acao !== '') $cmd .= ' ' . escapeshellarg($acao);
        foreach ($args as $arg) $cmd .= ' ' . escapeshellarg($arg);
        $cmd .= $wait ? ' 2>/dev/null' : ' > /dev/null 2>&1 &';

        shell_exec($cmd);
    }
}
