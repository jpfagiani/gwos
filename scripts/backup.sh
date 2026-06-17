#!/bin/bash
# Backup automático — banco + arquivos de configuração.
# Configurar no cron: 0 2 * * * /opt/gwos/scripts/backup.sh

set -euo pipefail

GWOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$GWOS_DIR/.env" ]; then set -a; source "$GWOS_DIR/.env"; set +a; fi

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_BANCO="${DB_BANCO:-gwos}"
DB_USUARIO="${DB_USUARIO:-gwos}"
DB_SENHA="${DB_SENHA:-}"
BACKUP_DIR="${BACKUP_DIR:-/var/lib/gwos/backups}"
RETENCAO=30  # dias

mkdir -p "$BACKUP_DIR"

DATA=$(date +%Y%m%d_%H%M%S)
ARQUIVO="gwos_backup_${DATA}.tar.gz"
TMP="/tmp/gwos_bkp_${DATA}"
mkdir -p "$TMP"

# Dump do banco
mysqldump -h"$DB_HOST" -u"$DB_USUARIO" -p"$DB_SENHA" \
    --single-transaction --routines --triggers \
    "$DB_BANCO" > "$TMP/banco.sql"

# Arquivos de configuração
cp /etc/nftables.conf          "$TMP/" 2>/dev/null || true
cp /etc/bind/named.conf.local  "$TMP/" 2>/dev/null || true
cp /etc/bind/db.rpz.gwos       "$TMP/" 2>/dev/null || true
cp /etc/squid/squid.conf       "$TMP/" 2>/dev/null || true

# Compacta
tar -czf "$BACKUP_DIR/$ARQUIVO" -C /tmp "gwos_bkp_${DATA}"
rm -rf "$TMP"

TAMANHO=$(stat -c%s "$BACKUP_DIR/$ARQUIVO")

# Registra no banco
mysql -h"$DB_HOST" -u"$DB_USUARIO" -p"$DB_SENHA" "$DB_BANCO" -e \
    "INSERT INTO backups (arquivo, tamanho, tipo, status) VALUES ('$ARQUIVO', $TAMANHO, 'auto', 'ok')"

# Remove backups antigos
find "$BACKUP_DIR" -name "gwos_backup_*.tar.gz" -mtime +$RETENCAO -delete

echo "Backup concluído: $ARQUIVO ($(numfmt --to=iec $TAMANHO))"
