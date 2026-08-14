#!/bin/bash
# ============================================================================
# GWOS — Define a senha padrão do painel (gwos@2025)
# Instalado como /usr/local/sbin/gwos-senha-padrao
# ============================================================================
# O schema.sql traz um hash bcrypt de exemplo. Este script o substitui por um
# hash gerado nesta máquina — só quando ainda for o hash de exemplo, para não
# derrubar a senha que o administrador já trocou.
#
# Precisa do PHP CLI (password_hash). Uso:
#   gwos-senha-padrao [email] [senha]
# ============================================================================

set -uo pipefail

EMAIL="${1:-admin@gwos.local}"
SENHA="${2:-gwos@2025}"
HASH_EXEMPLO='$2y$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi'

[ -f /etc/gwos/db.conf ] || { echo "[ERRO] /etc/gwos/db.conf não encontrado."; exit 1; }
# shellcheck disable=SC1091
. /etc/gwos/db.conf

command -v php >/dev/null 2>&1 || { echo "[ERRO] PHP CLI não instalado."; exit 1; }

_GW_HOST="$DB_HOST" _GW_BANCO="$DB_BANCO" _GW_USER="$DB_USUARIO" _GW_PASS="$DB_SENHA" \
_GW_EMAIL="$EMAIL" _GW_NOVA="$SENHA" _GW_EXEMPLO="$HASH_EXEMPLO" _GW_FORCAR="${FORCAR:-0}" \
php <<'PHP'
<?php
try {
    $pdo = new PDO(
        "mysql:host={$_SERVER['_GW_HOST']};dbname={$_SERVER['_GW_BANCO']};charset=utf8mb4",
        $_SERVER['_GW_USER'],
        $_SERVER['_GW_PASS']
    );
    $hash = password_hash($_SERVER['_GW_NOVA'], PASSWORD_BCRYPT, ['cost' => 12]);

    if ($_SERVER['_GW_FORCAR'] === '1') {
        $st = $pdo->prepare('UPDATE admins SET senha=?, primeiro_login=1 WHERE email=?');
        $st->execute([$hash, $_SERVER['_GW_EMAIL']]);
    } else {
        // Só troca se ainda for o hash de exemplo do schema
        $st = $pdo->prepare('UPDATE admins SET senha=?, primeiro_login=1 WHERE email=? AND senha=?');
        $st->execute([$hash, $_SERVER['_GW_EMAIL'], $_SERVER['_GW_EXEMPLO']]);
    }

    echo $st->rowCount() > 0
        ? "[OK] Senha padrao definida para {$_SERVER['_GW_EMAIL']}.\n"
        : "[..] Senha ja personalizada — nada alterado.\n";
} catch (Exception $e) {
    fwrite(STDERR, '[ERRO] ' . $e->getMessage() . PHP_EOL);
    exit(1);
}
PHP
