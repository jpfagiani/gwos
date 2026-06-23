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
            'ip'   => trim(shell_exec("ip route get 1 2>/dev/null | awk '{print \$7;exit}'") ?? '') ?: '—',
            'gw'   => trim(shell_exec("ip route show default 2>/dev/null | awk '{print \$3;exit}'") ?? '') ?: '—',
            'dns'  => trim(shell_exec("awk '/^nameserver/{print \$2;exit}' /etc/resolv.conf 2>/dev/null") ?? '') ?: '—',
            'rx'   => $rx,
            'tx'   => $tx,
            'conn' => (int)(Database::valor('SELECT COUNT(DISTINCT ip_cliente) FROM relatorio_diario WHERE data = CURDATE()') ?? 0),
            'log'  => self::lerLogSquid(100),
        ]);
        exit;
    }

    private static function grupoMap(): array
    {
        static $map = null;
        if ($map === null) {
            $rows = Database::fetchAll(
                'SELECT i.endereco, g.nome FROM ips i JOIN ip_grupos g ON g.id = i.grupo_id WHERE i.ativo = 1'
            );
            $map = array_column($rows, 'nome', 'endereco');
        }
        return $map;
    }

    private static function lerLogSquid(int $n): array
    {
        $arquivo = '/var/log/squid/access.log';
        if (!is_readable($arquivo)) return [];

        $fp = popen('tail -n ' . $n . ' ' . escapeshellarg($arquivo) . ' 2>/dev/null', 'r');
        if (!$fp) return [];

        $linhas = [];
        while (($l = fgets($fp)) !== false) $linhas[] = trim($l);
        pclose($fp);

        $grupos = self::grupoMap();
        $result = [];

        foreach (array_reverse($linhas) as $l) {
            if (!$l) continue;
            $p    = preg_split('/\s+/', $l);
            $ts   = (int)($p[0] ?? 0);
            $ip   = $p[2] ?? '—';
            $url  = $p[6] ?? '—';
            $host = parse_url($url, PHP_URL_HOST) ?: preg_replace('/:\d+$/', '', $url);
            $bloq = str_contains($p[3] ?? '', 'DENIED') || str_contains($p[3] ?? '', 'BLOCKED');

            $result[] = [
                'hora'      => date('d/m H:i:s', $ts),
                'ip'        => $ip,
                'dominio'   => $host,
                'grupo'     => $grupos[$ip] ?? '—',
                'bloqueado' => $bloq,
            ];
        }
        return $result;
    }

    private static function lerUltimosAcessos(int $n = 25): array
    {
        $arquivo = '/var/log/squid/access.log';
        if (!is_readable($arquivo)) return [];

        $fp = popen('tail -n 3000 ' . escapeshellarg($arquivo) . ' 2>/dev/null', 'r');
        if (!$fp) return [];

        $linhas = [];
        while (($l = fgets($fp)) !== false) $linhas[] = trim($l);
        pclose($fp);

        $grupos = self::grupoMap();
        $vistos = [];

        foreach (array_reverse($linhas) as $l) {
            if (!$l) continue;
            $p = preg_split('/\s+/', $l);
            if (count($p) < 7) continue;

            $ts    = (int)($p[0] ?? 0);
            $ip    = $p[2] ?? '';
            $url   = $p[6] ?? '';
            $bytes = (int)($p[4] ?? 0);
            $host  = parse_url($url, PHP_URL_HOST) ?: preg_replace('/:\d+$/', '', $url);
            $bloq  = str_contains($p[3] ?? '', 'DENIED') || str_contains($p[3] ?? '', 'BLOCKED');

            $chave = $ip . '|' . $host;
            if (isset($vistos[$chave])) continue;

            $vistos[$chave] = [
                'data_hora'  => date('d/m/Y H:i:s', $ts),
                'ip_cliente' => $ip,
                'dominio'    => $host,
                'grupo'      => $grupos[$ip] ?? '—',
                'bloqueado'  => $bloq,
                'bytes'      => $bytes,
            ];

            if (count($vistos) >= $n) break;
        }

        return array_values($vistos);
    }

    public function index(): void
    {
        Auth::exigir();

        $servicos = $this->statusServicos();

        $totalIps      = (int) Database::valor('SELECT COUNT(*) FROM ips WHERE ativo = 1');
        $totalGrupos   = (int) Database::valor('SELECT COUNT(*) FROM ip_grupos WHERE ativo = 1');
        $totalDominios = (int) Database::valor('SELECT COUNT(*) FROM dominios WHERE ativo = 1');
        $totalNat      = (int) Database::valor('SELECT COUNT(*) FROM nat_um_para_um');

        $ultimosAcessos = self::lerUltimosAcessos(25);

        $this->view('dashboard/index', compact(
            'servicos', 'totalIps', 'totalGrupos', 'totalDominios', 'totalNat', 'ultimosAcessos'
        ));
    }

    private function statusServicos(): array
    {
        $status = [];
        foreach (['squid', 'named', 'nftables', 'nginx', 'mariadb'] as $svc) {
            $status[$svc] = trim((string) shell_exec("systemctl is-active " . escapeshellarg($svc) . " 2>/dev/null")) === 'active';
        }
        return $status;
    }
}
