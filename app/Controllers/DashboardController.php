<?php

namespace App\Controllers;

use App\Core\{Auth, Database, Controller};

class DashboardController extends Controller
{
    public function info(): void
    {
        Auth::exigir();
        header('Content-Type: application/json');

        $iface = trim(shell_exec("ip route show default 2>/dev/null | awk '{print \$5;exit}'") ?? 'eth0');
        $rx    = (int)(file_get_contents("/sys/class/net/{$iface}/statistics/rx_bytes") ?: 0);
        $tx    = (int)(file_get_contents("/sys/class/net/{$iface}/statistics/tx_bytes") ?: 0);

        echo json_encode([
            'ip'    => trim(shell_exec("ip route get 1 2>/dev/null | awk '{print \$7;exit}'") ?? '') ?: '—',
            'gw'    => trim(shell_exec("ip route show default 2>/dev/null | awk '{print \$3;exit}'") ?? '') ?: '—',
            'dns'   => trim(shell_exec("awk '/^nameserver/{print \$2;exit}' /etc/resolv.conf 2>/dev/null") ?? '') ?: '—',
            'rx'    => $rx,
            'tx'    => $tx,
            'conn'  => (int)(Database::valor('SELECT COUNT(DISTINCT ip_cliente) FROM relatorio_diario WHERE data = CURDATE()') ?? 0),
            'log'   => self::lerLogSquid(20),
        ]);
        exit;
    }

    private static function lerLogSquid(int $n): array
    {
        $arquivo = '/var/log/squid/access.log';
        if (!is_readable($arquivo)) return [];
        $fp = popen('sudo tail -n ' . $n . ' ' . escapeshellarg($arquivo) . ' 2>/dev/null', 'r');
        if (!$fp) return [];
        $linhas = [];
        while (($l = fgets($fp)) !== false) $linhas[] = trim($l);
        pclose($fp);

        $result = [];
        foreach (array_reverse($linhas) as $l) {
            if (!$l) continue;
            $p    = preg_split('/\s+/', $l);
            $ip   = $p[2] ?? '—';
            $url  = $p[6] ?? '—';
            $host = parse_url($url, PHP_URL_HOST) ?: preg_replace('/:\d+$/', '', $url);
            $bloq = str_contains($p[3] ?? '', 'DENIED') || str_contains($p[3] ?? '', 'BLOCKED');
            $grupo = Database::fetch(
                'SELECT g.nome FROM ip_grupos g JOIN ips i ON i.grupo_id = g.id WHERE i.endereco = ? LIMIT 1', [$ip]
            )['nome'] ?? '—';
            $result[] = ['hora' => date('H:i:s', (int)($p[0] ?? 0)), 'ip' => $ip, 'dominio' => $host, 'grupo' => $grupo, 'bloqueado' => $bloq];
        }
        return $result;
    }

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
