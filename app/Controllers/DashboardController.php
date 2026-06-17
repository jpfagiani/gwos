<?php

namespace App\Controllers;

use App\Core\{Auth, Database, Controller};

class DashboardController extends Controller
{
    public function index(): void
    {
        Auth::exigir();

        $servicos = $this->statusServicos();

        $totalIps     = (int) Database::valor('SELECT COUNT(*) FROM ips WHERE ativo = 1');
        $totalGrupos  = (int) Database::valor('SELECT COUNT(*) FROM ip_grupos WHERE ativo = 1');
        $totalDominios = (int) Database::valor('SELECT COUNT(*) FROM dominios WHERE ativo = 1');
        $totalNat     = (int) Database::valor('SELECT COUNT(*) FROM nat_um_para_um');

        $ultimosAcessos = Database::fetchAll(
            'SELECT data, ip_cliente, dominio, acessos, bytes
             FROM relatorio_diario
             ORDER BY data DESC, acessos DESC
             LIMIT 10'
        );

        $this->view('dashboard/index', compact(
            'servicos', 'totalIps', 'totalGrupos', 'totalDominios', 'totalNat', 'ultimosAcessos'
        ));
    }

    private function statusServicos(): array
    {
        $servicos = ['squid', 'named', 'nftables', 'nginx', 'mariadb'];
        $status   = [];

        foreach ($servicos as $svc) {
            $saida = shell_exec("systemctl is-active " . escapeshellarg($svc) . " 2>/dev/null");
            $status[$svc] = trim((string)$saida) === 'active';
        }

        return $status;
    }
}
