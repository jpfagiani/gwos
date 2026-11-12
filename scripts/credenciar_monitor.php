<?php
if (PHP_SAPI !== 'cli' || !function_exists('posix_geteuid') || posix_geteuid() !== 0) exit(1);
require dirname(__DIR__) . '/bootstrap/app.php';

use App\Core\{Database, AcessoInternet};

$ip = $argv[1] ?? '';
if (!filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
    fwrite(STDERR, "Uso: sudo php scripts/credenciar_monitor.php IP_DO_WINDOWS\n");
    exit(2);
}
$chave = bin2hex(random_bytes(32));
Database::execute(
    'INSERT INTO monitores_internet (ip,chave_hash) VALUES (?,?)
     ON DUPLICATE KEY UPDATE chave_hash=VALUES(chave_hash), ciclo_hash=NULL, presente_ate=NULL',
    [$ip, hash('sha256', $chave)]
);
AcessoInternet::sair($ip);
echo "Chave para {$ip}. Entregue em particular ao responsável pela estação.\n{$chave}\n";
