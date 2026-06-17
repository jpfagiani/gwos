#!/bin/bash
# Exporta listas de domínios (whitelist/blacklist) para os arquivos do Squid.
# Executado pelo painel após qualquer alteração em domínios.
# Uso: gerar_squid_dominios.sh [--no-reconfigure]

set -euo pipefail

GWOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$GWOS_DIR/.env" ]; then set -a; source "$GWOS_DIR/.env"; set +a; fi

NO_RECONFIGURE=0
[[ "${1:-}" == "--no-reconfigure" ]] && NO_RECONFIGURE=1

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_BANCO="${DB_BANCO:-gwos}"
DB_USUARIO="${DB_USUARIO:-gwos}"
DB_SENHA="${DB_SENHA:-}"

SQUID_DIR="/etc/squid/conf.d"
mkdir -p "$SQUID_DIR"

mysql_q() {
    mysql -h"$DB_HOST" -u"$DB_USUARIO" -p"$DB_SENHA" "$DB_BANCO" \
        --batch --skip-column-names -e "$1"
}

dedup_dominios() {
    awk '
    {
        dom = $0
        redundante = 0
        for (i in aceitos) {
            sufixo = aceitos[i]
            if (length(dom) > length(sufixo) &&
                substr(dom, length(dom) - length(sufixo) + 1) == sufixo) {
                redundante = 1
                break
            }
        }
        if (!redundante) {
            aceitos[length(aceitos) + 1] = dom
            print dom
        }
    }'
}

# Whitelist: domínios com prefixo "." para cobrir subdomínios no Squid
# Ex: gov.br → .gov.br (cobre receita.gov.br, www.gov.br, etc.)
mysql_q "SELECT CONCAT('.', dominio) FROM dominios
         WHERE tipo='whitelist' AND ativo=1
         ORDER BY LENGTH(dominio), dominio" \
    | dedup_dominios > "$SQUID_DIR/gwos_whitelist.txt"

# Blacklist: mesma lógica
mysql_q "SELECT CONCAT('.', dominio) FROM dominios
         WHERE tipo='blacklist' AND ativo=1
         ORDER BY LENGTH(dominio), dominio" \
    | dedup_dominios > "$SQUID_DIR/gwos_blacklist.txt"

# Recarrega Squid (parse + reconfigure) — apenas se não for --no-reconfigure
if [ "$NO_RECONFIGURE" -eq 0 ]; then
    squid -k parse && squid -k reconfigure
fi

echo "Listas de domínios Squid atualizadas com sucesso."
