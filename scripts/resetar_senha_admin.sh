#!/bin/bash
# Redefine a senha do admin principal
# Uso: sudo gwos senha [email] [nova_senha]
# Ou diretamente: sudo bash /opt/gwos/scripts/resetar_senha_admin.sh [email] [nova_senha]
set -euo pipefail

GWOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$GWOS_DIR/.env"
[ -f "$ENV_FILE" ] || { echo "ERRO: .env não encontrado em $GWOS_DIR"; exit 1; }
set -a; source "$ENV_FILE"; set +a

EMAIL="${1:-admin@gwos.local}"
NOVA="${2:-gwos@2025}"

resultado=$(
    _GW_HOST="${DB_HOST:-127.0.0.1}" \
    _GW_BANCO="${DB_BANCO:-gwos}" \
    _GW_USER="${DB_USUARIO:-gwos}" \
    _GW_PASS="${DB_SENHA}" \
    _GW_EMAIL="${EMAIL}" \
    _GW_NOVA="${NOVA}" \
    php << 'PHP'
<?php
try {
    $pdo = new PDO(
        "mysql:host={$_SERVER['_GW_HOST']};dbname={$_SERVER['_GW_BANCO']};charset=utf8mb4",
        $_SERVER['_GW_USER'],
        $_SERVER['_GW_PASS']
    );
    $hash = password_hash($_SERVER['_GW_NOVA'], PASSWORD_BCRYPT, ['cost' => 12]);
    $st   = $pdo->prepare(
        'UPDATE admins SET senha=?, tentativas=0, bloqueado_ate=NULL, primeiro_login=1 WHERE email=?'
    );
    $st->execute([$hash, $_SERVER['_GW_EMAIL']]);
    echo 'ok';
} catch (Exception $e) {
    echo 'erro:' . $e->getMessage();
}
PHP
)

if [[ "$resultado" == "ok" ]]; then
    echo "✔  Senha do admin '${EMAIL}' redefinida para: ${NOVA}"
    echo "   O painel pedirá troca de senha no primeiro acesso."
else
    echo "✘  Falha: ${resultado#erro:}" >&2
    exit 1
fi
