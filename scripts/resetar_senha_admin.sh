#!/bin/bash
# Redefine a senha do admin principal via PDO (seguro com bcrypt)
# Uso: sudo bash /opt/gwos/scripts/resetar_senha_admin.sh [email] [nova_senha]
set -euo pipefail

GWOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$GWOS_DIR/.env"

[ -f "$ENV_FILE" ] || { echo "ERRO: .env não encontrado em $GWOS_DIR"; exit 1; }
set -a; source "$ENV_FILE"; set +a

EMAIL="${1:-admin@gwos.local}"
SENHA="${2:-gwos@2025}"

resultado=$(php -r "
    try {
        \$pdo  = new PDO('mysql:host=${DB_HOST:-127.0.0.1};dbname=${DB_BANCO:-gwos};charset=utf8mb4',
                         '${DB_USUARIO:-gwos}', '${DB_SENHA}');
        \$hash = password_hash('${SENHA}', PASSWORD_BCRYPT, ['cost' => 12]);
        \$st   = \$pdo->prepare('UPDATE admins SET senha=?, tentativas=0, bloqueado_ate=NULL, primeiro_login=1 WHERE email=?');
        \$st->execute([\$hash, '${EMAIL}']);
        echo 'ok';
    } catch (Exception \$e) {
        echo 'erro:' . \$e->getMessage();
    }
" 2>/dev/null)

if [[ "$resultado" == "ok" ]]; then
    echo "✔  Senha do admin '${EMAIL}' redefinida para: ${SENHA}"
    echo "   O painel pedirá troca de senha no primeiro acesso."
else
    echo "✘  Falha: ${resultado#erro:}" >&2
    exit 1
fi
