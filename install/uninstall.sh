#!/bin/bash
# GWOS — Desinstalador
# Remove todos os pacotes, configurações e dados do GWOS.
# Execute como root: bash uninstall.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
info()  { echo -e "${YELLOW}[..]${NC} $1"; }
aviso() { echo -e "${YELLOW}[!]${NC} $1"; }

[ "$(id -u)" -eq 0 ] || { echo -e "${RED}[ERRO]${NC} Execute como root."; exit 1; }

GWOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "\n${BOLD}${RED}ATENÇÃO: Esta operação removerá o GWOS e todos os seus dados!${NC}\n"
echo -e "  Diretório do projeto : ${BOLD}${GWOS_DIR}${NC}"
echo -e "  Banco de dados       : ${BOLD}gwos${NC}"
echo -e "  Pacotes              : squid, bind9, nginx, php8.4*, mariadb-server"
echo ""
read -rp "  Confirma a desinstalação? [s/N]: " CONF
[[ "$CONF" =~ ^[Ss]$ ]] || { echo "Cancelado."; exit 0; }

# ------------------------------------------------------------------
# Para os serviços
# ------------------------------------------------------------------
info "Parando serviços..."
for svc in squid named nginx php8.4-fpm mariadb nftables chrony; do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
done
ok "Serviços parados."

# ------------------------------------------------------------------
# Remove banco de dados
# ------------------------------------------------------------------
info "Removendo banco de dados gwos..."
mysql -e "DROP DATABASE IF EXISTS gwos;" 2>/dev/null || true
mysql -e "DROP USER IF EXISTS 'gwos'@'localhost';" 2>/dev/null || true
ok "Banco removido."

# ------------------------------------------------------------------
# Remove pacotes
# ------------------------------------------------------------------
info "Removendo pacotes..."
DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y -qq \
    squid squid-openssl bind9 bind9-utils nginx \
    php8.4 php8.4-fpm php8.4-mysql php8.4-mbstring \
    php8.4-curl php8.4-zip php8.4-xml php8.4-intl \
    mariadb-server chrony sarg 2>/dev/null || true
apt-get autoremove -y -qq 2>/dev/null || true
ok "Pacotes removidos."

# ------------------------------------------------------------------
# Remove arquivos de configuração
# ------------------------------------------------------------------
info "Removendo configurações..."
rm -rf /etc/squid/conf.d /etc/squid/ssl_cert
rm -f  /etc/squid/squid.conf
rm -rf /var/lib/squid/ssl_db
rm -f  /etc/bind/db.rpz.gwos /etc/bind/named.conf.local /etc/bind/named.conf.options
rm -f  /etc/nginx/sites-available/gwos /etc/nginx/sites-enabled/gwos
rm -f  /etc/nftables.conf
rm -f  /etc/sysctl.d/99-gwos.conf
rm -f  /etc/sudoers.d/gwos
rm -f  /etc/cron.d/gwos
rm -rf /var/lib/gwos
rm -rf /var/log/named
ok "Configurações removidas."

# ------------------------------------------------------------------
# Remove arquivos do projeto (opcional)
# ------------------------------------------------------------------
read -rp "  Remover também o diretório do projeto (${GWOS_DIR})? [s/N]: " RM_PROJ
if [[ "$RM_PROJ" =~ ^[Ss]$ ]]; then
    rm -rf "$GWOS_DIR"
    ok "Diretório do projeto removido."
else
    aviso "Diretório do projeto mantido: ${GWOS_DIR}"
fi

# Restaura regras nftables vazias
nft flush ruleset 2>/dev/null || true

echo ""
echo -e "${GREEN}${BOLD}GWOS desinstalado com sucesso.${NC}"
echo ""
