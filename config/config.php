<?php
/**
 * GWOS — Configurações centrais da aplicação
 * Lê variáveis do .env (carregado antes pelo bootstrap ou pelo próprio PHP-FPM)
 */

// Lê .env se ainda não foi carregado
$envFile = dirname(__DIR__) . '/.env';
if (file_exists($envFile)) {
    foreach (file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $linha) {
        if (str_starts_with(trim($linha), '#') || !str_contains($linha, '=')) continue;
        [$chave, $valor] = explode('=', $linha, 2);
        $_ENV[trim($chave)] = trim($valor);
        if (!isset($_SERVER[trim($chave)])) {
            $_SERVER[trim($chave)] = trim($valor);
        }
    }
}

$env = fn(string $k, mixed $d = null) => $_ENV[$k] ?? $_SERVER[$k] ?? getenv($k) ?: $d;

return [

    'app' => [
        'nome'     => $env('APP_NOME', 'GWOS'),
        'url'      => $env('APP_URL', 'http://192.168.0.1'),
        'debug'    => filter_var($env('APP_DEBUG', 'false'), FILTER_VALIDATE_BOOLEAN),
        'timezone' => $env('APP_TIMEZONE', 'America/Sao_Paulo'),
        'versao'   => '1.0.0',
    ],

    'db' => [
        'host'   => $env('DB_HOST', '127.0.0.1'),
        'banco'  => $env('DB_BANCO', 'gwos'),
        'usuario'=> $env('DB_USUARIO', 'gwos'),
        'senha'  => $env('DB_SENHA', ''),
        'charset'=> 'utf8mb4',
    ],

    'session' => [
        'nome'    => 'GWOS_SESSION',
        'duracao' => 7200,  // 2 horas
    ],

];
