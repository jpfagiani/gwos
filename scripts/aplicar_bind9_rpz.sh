#!/bin/bash
# Gera a zona RPZ do BIND9 a partir das blacklists do banco.
# Executado pelo painel via sudo.

set -euo pipefail

GWOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$GWOS_DIR/.env" ]; then set -a; source "$GWOS_DIR/.env"; set +a; fi

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_BANCO="${DB_BANCO:-gwos}"
DB_USUARIO="${DB_USUARIO:-gwos}"
DB_SENHA="${DB_SENHA:-}"
RPZ_ARQUIVO="/etc/bind/db.rpz.gwos"

SERIAL=$(date +%Y%m%d%H%M%S)

cat > "$RPZ_ARQUIVO" <<ZONA
\$TTL 60
@   IN SOA localhost. root.localhost. (
        $SERIAL ; serial
        3600    ; refresh
        900     ; retry
        86400   ; expire
        60 )    ; minimum
    IN NS  localhost.

ZONA

# Adiciona domínios da blacklist
mysql -h"$DB_HOST" -u"$DB_USUARIO" -p"$DB_SENHA" "$DB_BANCO" -sNe \
    "SELECT dominio FROM dominios WHERE tipo='blacklist' AND ativo=1" | \
while IFS= read -r dominio; do
    echo "${dominio}.    IN CNAME ." >> "$RPZ_ARQUIVO"
    echo "*.${dominio}.  IN CNAME ." >> "$RPZ_ARQUIVO"
done

rndc reload 2>/dev/null || { named-checkconf && rndc reload; }

echo "RPZ aplicado com sucesso (serial: $SERIAL)."
