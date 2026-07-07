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

# ------------------------------------------------------------------
# Preserva a configuração de REDE ATUAL antes de restaurar o banco.
# Um backup antigo pode ter sido feito com outro IP/interfaces — restaurá-lo
# não pode reverter a rede do servidor (causa perda de acesso).
# ------------------------------------------------------------------
mysql_q() {
    mysql -h"$DB_HOST" -u"$DB_USUARIO" -p"$DB_SENHA" "$DB_BANCO" \
        --batch --skip-column-names -e "$1" 2>/dev/null
}

declare -A REDE_ATUAL
for CHAVE in iface_wan iface_lan rede_lan ip_gateway; do
    REDE_ATUAL[$CHAVE]=$(mysql_q "SELECT valor FROM configuracoes WHERE chave='$CHAVE'" || true)
done

# Restaurar banco
[ -f "$TMP/banco.sql" ] && mysql -h"$DB_HOST" -u"$DB_USUARIO" -p"$DB_SENHA" "$DB_BANCO" < "$TMP/banco.sql"

# Reaplica as chaves de rede atuais (não podem vir do backup)
for CHAVE in iface_wan iface_lan rede_lan ip_gateway; do
    [ -n "${REDE_ATUAL[$CHAVE]}" ] && \
        mysql_q "UPDATE configuracoes SET valor='${REDE_ATUAL[$CHAVE]}' WHERE chave='$CHAVE'"
done

# Restaurar configurações de DNS (não dependem do IP do gateway)
[ -f "$TMP/named.conf.local"   ] && cp "$TMP/named.conf.local"    /etc/bind/named.conf.local
[ -f "$TMP/db.rpz.gwos"        ] && cp "$TMP/db.rpz.gwos"         /etc/bind/db.rpz.gwos

rm -rf "$TMP"

# nftables NÃO é copiado do backup: é regenerado a partir do banco já
# restaurado, com as interfaces/rede ATUAIS (validado com nft -c internamente).
GWOS_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$GWOS_SCRIPTS/aplicar_nftables.sh" || echo "AVISO: falha ao regenerar nftables — regras atuais mantidas."

# squid.conf também não é sobrescrito pelo backup (pode conter rede antiga);
# as listas/ACLs do Squid são regeneradas do banco restaurado.
DB_HOST="$DB_HOST" DB_BANCO="$DB_BANCO" DB_USUARIO="$DB_USUARIO" DB_SENHA="$DB_SENHA" \
    bash "$GWOS_SCRIPTS/gerar_squid_dominios.sh" 2>/dev/null || true

# Reinicia serviços
systemctl reload-or-restart named squid 2>/dev/null || true

echo "Backup restaurado com sucesso (configuração de rede atual preservada)."
