<?php

namespace App\Controllers;

use App\Core\{Auth, Database, Controller, Auditoria};

class DominioController extends Controller
{
    public function index(): void
    {
        Auth::exigir();

        $dominios = Database::fetchAll(
            'SELECT * FROM dominios ORDER BY tipo, dominio'
        );

        $this->view('dominios/index', compact('dominios'));
    }

    public function criar(): void
    {
        Auth::exigir();
        if (!csrf_verificar()) { json_resposta(['erro' => 'Token inválido.'], 403); }

        $dominio = strtolower(trim($_POST['dominio'] ?? ''));
        $tipo    = trim($_POST['tipo'] ?? '');

        if ($dominio === '' || !in_array($tipo, ['whitelist', 'blacklist'])) {
            json_resposta(['erro' => 'Domínio e tipo são obrigatórios.'], 422);
        }

        if (!preg_match('/^(\*\.)?([a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$/', $dominio)) {
            json_resposta(['erro' => 'Domínio inválido.'], 422);
        }

        $existe = Database::fetch('SELECT id FROM dominios WHERE dominio = ?', [$dominio]);
        if ($existe) { json_resposta(['erro' => 'Domínio já cadastrado.'], 409); }

        $id = Database::insert(
            'INSERT INTO dominios (dominio, tipo, origem) VALUES (?, ?, ?)',
            [$dominio, $tipo, 'manual']
        );

        Auditoria::registrar('criar_dominio', 'dominios', (int)$id, null, compact('dominio', 'tipo'));

        $this->aplicarRegras();

        json_resposta(['sucesso' => 'Domínio adicionado.', 'id' => $id]);
    }

    public function remover(string $id): void
    {
        Auth::exigir();
        if (!csrf_verificar()) { json_resposta(['erro' => 'Token inválido.'], 403); }

        $dominio = Database::fetch('SELECT * FROM dominios WHERE id = ?', [$id]);
        if (!$dominio) { json_resposta(['erro' => 'Domínio não encontrado.'], 404); }

        Database::execute('DELETE FROM dominios WHERE id = ?', [$id]);
        Auditoria::registrar('remover_dominio', 'dominios', (int)$id, $dominio, null);

        $this->aplicarRegras();

        json_resposta(['sucesso' => 'Domínio removido.']);
    }

    public function aplicar(): void
    {
        Auth::exigir();
        if (!csrf_verificar()) { json_resposta(['erro' => 'Token inválido.'], 403); }

        $this->aplicarRegras();
        Auditoria::registrar('aplicar_dominios', 'dominios', null, null, null);

        json_resposta(['sucesso' => 'Listas de domínios reaplicadas.']);
    }

    private function aplicarRegras(): void
    {
        $scripts = config('sistema.scripts_dir', '/opt/gwos/scripts');
        shell_exec("sudo {$scripts}/gerar_squid_dominios.sh > /dev/null 2>&1 &");
        shell_exec("sudo {$scripts}/aplicar_bind9_rpz.sh > /dev/null 2>&1 &");
    }
}
