#!/bin/bash
# Restaura um backup GWOS.
# Uso: restaurar_backup.sh /caminho/para/arquivo.tar.gz

set -euo pipefail

GWOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$GWOS_DIR/.env" ]; then set -a; source "$GWOS_DIR/.env"; set +a; fi

ARQUIVO="$1"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_BANCO="${DB_BANCO:-gwos}"
DB_USUARIO="${DB_USUARIO:-gwos}"
DB_SENHA="${DB_SENHA:-}"
TMP="/tmp/gwos_restaurar_$$"

[ -f "$ARQUIVO" ] || { echo "Arquivo não encontrado: $ARQUIVO"; exit 1; }

mkdir -p "$TMP"
tar -xzf "$ARQUIVO" -C "$TMP" --strip-components=1

# Restaurar banco
[ -f "$TMP/banco.sql" ] && mysql -h"$DB_HOST" -u"$DB_USUARIO" -p"$DB_SENHA" "$DB_BANCO" < "$TMP/banco.sql"

# Restaurar configurações
[ -f "$TMP/nftables.conf"      ] && cp "$TMP/nftables.conf"      /etc/nftables.conf
[ -f "$TMP/named.conf.local"   ] && cp "$TMP/named.conf.local"    /etc/bind/named.conf.local
[ -f "$TMP/db.rpz.gwos"        ] && cp "$TMP/db.rpz.gwos"         /etc/bind/db.rpz.gwos
[ -f "$TMP/squid.conf"         ] && cp "$TMP/squid.conf"          /etc/squid/squid.conf

rm -rf "$TMP"

# Reinicia serviços
systemctl reload-or-restart nftables named squid 2>/dev/null || true

echo "Backup restaurado com sucesso."
