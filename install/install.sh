#!/bin/bash
# GWOS — Instalador para Debian 13
# Execute como root: bash install.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
info()  { echo -e "${YELLOW}[..]${NC} $1"; }
erro()  { echo -e "${RED}[ERRO]${NC} $1"; exit 1; }
aviso() { echo -e "${YELLOW}[!]${NC} $1"; }
titulo(){ echo -e "\n${BOLD}${CYAN}$1${NC}"; }

[ "$(id -u)" -eq 0 ] || erro "Execute como root."

# Diretório raiz do projeto (um nível acima de install/)
GWOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
info "Diretório do projeto: $GWOS_DIR"

# ==================================================================
# DETECÇÃO DE REDE
# ==================================================================

titulo "══ Detecção de Interfaces de Rede ══"
echo ""

mapfile -t IFACES < <(ip -o link show \
    | awk -F': ' '{print $2}' \
    | grep -Ev '^(lo|docker|veth|br-|virbr|tun|tap)' \
    | sort)

[ ${#IFACES[@]} -gt 0 ] || erro "Nenhuma interface de rede encontrada."

echo -e "  ${BOLD}Interfaces disponíveis:${NC}\n"
printf "  %-4s %-14s %-22s %-8s %s\n" "Nº" "Interface" "IP/Máscara" "Status" "Velocidade"
echo "  ──────────────────────────────────────────────────────────"

IDX=1
for iface in "${IFACES[@]}"; do
    IP_CIDR=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet /{print $2}' | head -1)
    IP_CIDR="${IP_CIDR:-sem IP}"
    STATUS=$(cat "/sys/class/net/${iface}/operstate" 2>/dev/null || echo "?")
    case "$STATUS" in
        up)   SFMT="${GREEN}UP${NC}"   ;;
        down) SFMT="${RED}DOWN${NC}" ;;
        *)    SFMT="${YELLOW}${STATUS}${NC}" ;;
    esac
    SPEED=$(cat "/sys/class/net/${iface}/speed" 2>/dev/null || echo "?")
    [[ "$SPEED" =~ ^-?[0-9]+$ ]] && [ "$SPEED" -gt 0 ] && SPEED="${SPEED} Mb/s" || SPEED="?"
    printf "  %-4s %-14s %-22s " "$IDX" "$iface" "$IP_CIDR"
    echo -e "${SFMT}    ${SPEED}"
    IDX=$((IDX + 1))
done
echo ""

# Função para selecionar interface
# IMPORTANTE: todo output de exibição vai para >&2; apenas o resultado vai para stdout
selecionar_iface() {
    local PROMPT="$1"
    local SUGESTAO="$2"
    local RESULTADO=""

    while true; do
        if [ -n "$SUGESTAO" ]; then
            echo -e "  Sugestão: ${BOLD}${SUGESTAO}${NC}  (Enter para confirmar, ou digite outra)" >&2
        fi
        read -rp "  $PROMPT [${SUGESTAO:-nome ou número}]: " ENT
        ENT="${ENT:-$SUGESTAO}"

        if [[ "$ENT" =~ ^[0-9]+$ ]]; then
            POS=$((ENT - 1))
            if [ "$POS" -ge 0 ] && [ "$POS" -lt ${#IFACES[@]} ]; then
                RESULTADO="${IFACES[$POS]}"; break
            fi
            echo -e "  ${RED}Número inválido. Escolha entre 1 e ${#IFACES[@]}.${NC}" >&2
        elif [ -n "$ENT" ]; then
            # Aceita qualquer nome de interface que exista no kernel (permite enp0s8 sem IP)
            if ip link show "$ENT" &>/dev/null; then
                RESULTADO="$ENT"; break
            fi
            echo -e "  ${RED}Interface '${ENT}' não encontrada. Tente novamente.${NC}" >&2
        else
            echo -e "  ${RED}Por favor, informe a interface.${NC}" >&2
        fi
    done
    echo "$RESULTADO"
}

titulo "── Interface WAN (saída para a Internet) ──"
echo ""
WAN_AUTO=$(ip route show default 2>/dev/null | awk '/default/{print $5}' | head -1 || true)
IFACE_WAN=$(selecionar_iface "Interface WAN" "$WAN_AUTO")
ok "WAN: $IFACE_WAN"

titulo "── Interface LAN (rede interna) ──"
echo ""
LAN_AUTO=""
for iface in "${IFACES[@]}"; do
    [ "$iface" != "$IFACE_WAN" ] && LAN_AUTO="$iface" && break
done
IFACE_LAN=$(selecionar_iface "Interface LAN" "$LAN_AUTO")
[ "$IFACE_LAN" = "$IFACE_WAN" ] && erro "WAN e LAN não podem ser a mesma interface."
ok "LAN: $IFACE_LAN"

titulo "── Rede LAN ──"
echo ""

# Tenta detectar IP e rede já configurados na interface LAN
IP_LAN_CIDR=$(ip -4 addr show "$IFACE_LAN" 2>/dev/null | awk '/inet /{print $2}' | head -1 || true)

if [ -n "$IP_LAN_CIDR" ]; then
    # Interface já tem IP — usa como sugestão
    IP_GW_SUGERIDO=$(echo "$IP_LAN_CIDR" | cut -d/ -f1)
    PREFIXO=$(echo "$IP_LAN_CIDR" | cut -d/ -f2)
    IFS='.' read -r a b c d <<< "$IP_GW_SUGERIDO"
    BITS=$((32 - PREFIXO))
    M=$(( (0xFFFFFFFF << BITS) & 0xFFFFFFFF ))
    NA=$(( (a << 24 | b << 16 | c << 8 | d) & M ))
    REDE_SUGERIDA="$(( (NA>>24)&0xFF )).$(( (NA>>16)&0xFF )).$(( (NA>>8)&0xFF )).$(( NA&0xFF ))/${PREFIXO}"
else
    # Interface sem IP — sugere padrão 192.168.1.x
    REDE_SUGERIDA="192.168.1.0/24"
    IP_GW_SUGERIDO="192.168.1.1"
fi

echo -e "  Sugestão de rede LAN : ${BOLD}${REDE_SUGERIDA}${NC}"
echo -e "  Sugestão de IP       : ${BOLD}${IP_GW_SUGERIDO}${NC}"
echo -e "  ${YELLOW}(Pressione Enter para aceitar a sugestão ou digite outro valor)${NC}"
echo ""

read -rp "  Rede LAN em CIDR [${REDE_SUGERIDA}]: " REDE_LAN
REDE_LAN="${REDE_LAN:-$REDE_SUGERIDA}"

read -rp "  IP deste gateway na LAN [${IP_GW_SUGERIDO}]: " IP_GATEWAY
IP_GATEWAY="${IP_GATEWAY:-$IP_GW_SUGERIDO}"

# Valida REDE_LAN
while ! echo "$REDE_LAN" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'; do
    echo -e "  ${RED}Rede inválida: '${REDE_LAN}' — use formato CIDR (ex: 192.168.1.0/24)${NC}"
    read -rp "  Rede LAN em CIDR [${REDE_SUGERIDA}]: " REDE_LAN
    REDE_LAN="${REDE_LAN:-$REDE_SUGERIDA}"
done

# Valida IP_GATEWAY
while ! echo "$IP_GATEWAY" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; do
    echo -e "  ${RED}IP inválido: '${IP_GATEWAY}' — use formato IPv4 (ex: 192.168.1.1)${NC}"
    read -rp "  IP deste gateway na LAN [${IP_GW_SUGERIDO}]: " IP_GATEWAY
    IP_GATEWAY="${IP_GATEWAY:-$IP_GW_SUGERIDO}"
done

ok "Rede: $REDE_LAN  |  Gateway: $IP_GATEWAY"

# ------------------------------------------------------------------
# Configuração da WAN (DHCP ou estático)
# ------------------------------------------------------------------
titulo "── Configuração da WAN ──"
echo ""
WAN_IP_ATUAL=$(ip -4 addr show "$IFACE_WAN" 2>/dev/null | awk '/inet /{print $2}' | head -1 || true)
WAN_GW_ATUAL=$(ip route show default 2>/dev/null | awk '/default/{print $3}' | head -1 || true)

echo -e "  IP atual da WAN  : ${BOLD}${WAN_IP_ATUAL:-sem IP}${NC}"
echo -e "  Gateway WAN atual: ${BOLD}${WAN_GW_ATUAL:-não detectado}${NC}"
echo ""
read -rp "  WAN usa DHCP? [S/n]: " WAN_DHCP; WAN_DHCP="${WAN_DHCP:-S}"

if [[ "$WAN_DHCP" =~ ^[Ss]$ ]]; then
    WAN_MODO="dhcp"
    WAN_IP=""; WAN_MASK=""; WAN_GW=""; WAN_DNS=""
    ok "WAN: DHCP"
else
    WAN_MODO="static"
    WAN_IP_DEF=$(echo "$WAN_IP_ATUAL" | cut -d/ -f1)
    WAN_PREF=$(echo "$WAN_IP_ATUAL" | cut -d/ -f2)
    # Converte prefixo para máscara
    mascara_de_prefixo() {
        local p="${1:-24}"; local m=0
        for i in $(seq 1 "$p"); do m=$(( m | (1 << (32-i)) )); done
        echo "$(( (m>>24)&0xFF )).$(( (m>>16)&0xFF )).$(( (m>>8)&0xFF )).$(( m&0xFF ))"
    }
    WAN_MASK_DEF=$(mascara_de_prefixo "${WAN_PREF:-24}")
    read -rp "  IP estático WAN [${WAN_IP_DEF:-}]: " WAN_IP
    WAN_IP="${WAN_IP:-$WAN_IP_DEF}"
    read -rp "  Máscara de rede [${WAN_MASK_DEF}]: " WAN_MASK
    WAN_MASK="${WAN_MASK:-$WAN_MASK_DEF}"
    read -rp "  Gateway padrão [${WAN_GW_ATUAL:-}]: " WAN_GW
    WAN_GW="${WAN_GW:-$WAN_GW_ATUAL}"
    read -rp "  DNS primário [8.8.8.8]: " WAN_DNS
    WAN_DNS="${WAN_DNS:-8.8.8.8}"
    ok "WAN: IP=$WAN_IP  Máscara=$WAN_MASK  GW=$WAN_GW  DNS=$WAN_DNS"
fi

# Máscara da LAN a partir do CIDR
LAN_PREF=$(echo "$REDE_LAN" | cut -d/ -f2)
mascara_de_prefixo2() {
    local p="${1:-24}"; local m=0
    for i in $(seq 1 "$p"); do m=$(( m | (1 << (32-i)) )); done
    echo "$(( (m>>24)&0xFF )).$(( (m>>16)&0xFF )).$(( (m>>8)&0xFF )).$(( m&0xFF ))"
}
LAN_MASK=$(mascara_de_prefixo2 "$LAN_PREF")

titulo "── Resumo ──"
echo ""
echo -e "  WAN        : ${BOLD}${IFACE_WAN}${NC}"
echo -e "  LAN        : ${BOLD}${IFACE_LAN}${NC}"
echo -e "  Rede LAN   : ${BOLD}${REDE_LAN}${NC}"
echo -e "  IP Gateway : ${BOLD}${IP_GATEWAY}${NC}"
echo ""
read -rp "  Iniciar instalação? [S/n]: " INI; INI="${INI:-S}"
[[ "$INI" =~ ^[Ss]$ ]] || { echo "Cancelado."; exit 0; }

# ==================================================================
titulo "══ Instalando pacotes ══"
# ==================================================================

info "Atualizando lista de pacotes..."
apt-get update -qq

# ------------------------------------------------------------------
# PHP 8.4 — não existe nos repos padrão do Debian 13.
# Adiciona o repositório sury.org (padrão da comunidade PHP/Debian).
# ------------------------------------------------------------------
if ! apt-cache show php8.4 &>/dev/null; then
    info "Adicionando repositório PHP 8.4 (sury.org)..."
    apt-get install -y -qq curl gnupg2 lsb-release ca-certificates apt-transport-https
    curl -fsSL https://packages.sury.org/php/apt.gpg \
        | gpg --dearmor -o /etc/apt/trusted.gpg.d/php-sury.gpg
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" \
        > /etc/apt/sources.list.d/php-sury.list
    apt-get update -qq
    ok "Repositório PHP 8.4 adicionado."
fi

info "Instalando dependências..."
# squid-openssl é necessário para SSL Bump (intercepção HTTPS)
# No Debian 13, squid e squid-openssl são mutuamente exclusivos
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    nftables bind9 bind9-utils chrony ifupdown sudo \
    mariadb-server \
    php8.4 php8.4-fpm php8.4-mysql php8.4-mbstring \
    php8.4-curl php8.4-zip php8.4-xml php8.4-intl \
    nginx curl tar gzip openssl unzip iproute2

# Instala squid com suporte SSL (tenta squid-openssl primeiro, cai para squid)
if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq squid-openssl 2>/dev/null; then
    ok "Squid instalado com suporte SSL (squid-openssl)."
else
    aviso "squid-openssl não disponível — instalando squid padrão (SSL Bump desativado)."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq squid
fi

# SARG é opcional — pode não estar disponível no Debian 13
apt-get install -y -qq sarg 2>/dev/null && ok "SARG instalado." \
    || aviso "SARG não disponível — relatórios via painel serão usados."

ok "Pacotes instalados."

# ==================================================================
titulo "══ Configuração de Rede (/etc/network/interfaces) ══"
# ==================================================================

# Faz backup do arquivo atual
cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null || true

cat > /etc/network/interfaces << NETEOF
# /etc/network/interfaces — gerado pelo instalador GWOS em $(date '+%Y-%m-%d %H:%M:%S')
# Para alterar, edite este arquivo e execute: systemctl restart networking

source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

# WAN — saída para a internet
auto ${IFACE_WAN}
NETEOF

if [ "$WAN_MODO" = "dhcp" ]; then
    cat >> /etc/network/interfaces << NETEOF
iface ${IFACE_WAN} inet dhcp

NETEOF
else
    cat >> /etc/network/interfaces << NETEOF
iface ${IFACE_WAN} inet static
    address ${WAN_IP}
    netmask ${WAN_MASK}
    gateway ${WAN_GW}
    dns-nameservers ${WAN_DNS}

NETEOF
fi

cat >> /etc/network/interfaces << NETEOF
# LAN — rede interna (IP fixo — este servidor é o gateway)
auto ${IFACE_LAN}
iface ${IFACE_LAN} inet static
    address ${IP_GATEWAY}
    netmask ${LAN_MASK}

NETEOF

ok "/etc/network/interfaces configurado."

# Aplica a configuração sem reiniciar o serviço de rede inteiro
# (evita cair a sessão SSH na WAN se for DHCP já com IP)
ip addr flush dev "$IFACE_LAN" 2>/dev/null || true
ip addr add "${IP_GATEWAY}/${LAN_PREF}" dev "$IFACE_LAN" 2>/dev/null || true
ip link set "$IFACE_LAN" up 2>/dev/null || true

if [ "$WAN_MODO" = "static" ]; then
    ip addr flush dev "$IFACE_WAN" 2>/dev/null || true
    ip addr add "${WAN_IP}/${WAN_PREF:-24}" dev "$IFACE_WAN" 2>/dev/null || true
    ip link set "$IFACE_WAN" up 2>/dev/null || true
    ip route replace default via "$WAN_GW" dev "$IFACE_WAN" 2>/dev/null || true
fi

ok "Configuração de rede aplicada."
aviso "Para persistir após reinicialização, o /etc/network/interfaces foi atualizado."

# ==================================================================
titulo "══ MariaDB ══"
# ==================================================================

systemctl enable --now mariadb
DB_SENHA=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24)

mysql -e "DROP DATABASE IF EXISTS gwos;"
mysql -e "CREATE DATABASE gwos CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "DROP USER IF EXISTS 'gwos'@'localhost';"
mysql -e "CREATE USER 'gwos'@'localhost' IDENTIFIED BY '${DB_SENHA}';"
mysql -e "GRANT ALL PRIVILEGES ON gwos.* TO 'gwos'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"
mysql gwos < "${GWOS_DIR}/database/schema.sql"

# Gera hash correto da senha padrão (o schema.sql tem placeholder)
ADMIN_HASH=$(php -r "echo password_hash('gwos@2025', PASSWORD_BCRYPT, ['cost' => 12]);" 2>/dev/null || true)
if [ -n "$ADMIN_HASH" ]; then
    mysql gwos -e "UPDATE admins SET senha='${ADMIN_HASH}' WHERE email='admin@gwos.local';"
fi

mysql gwos -e "
    UPDATE configuracoes SET valor='${IFACE_WAN}'    WHERE chave='iface_wan';
    UPDATE configuracoes SET valor='${IFACE_LAN}'    WHERE chave='iface_lan';
    UPDATE configuracoes SET valor='${REDE_LAN}'     WHERE chave='rede_lan';
    UPDATE configuracoes SET valor='${IP_GATEWAY}'   WHERE chave='ip_gateway';
"
ok "MariaDB configurado."

# ==================================================================
titulo "══ PHP-FPM ══"
# ==================================================================

PHP_INI="/etc/php/8.4/fpm/php.ini"
sed -i "s|;date.timezone.*|date.timezone = America/Sao_Paulo|" "$PHP_INI"
sed -i "s|upload_max_filesize.*|upload_max_filesize = 64M|"    "$PHP_INI"
sed -i "s|post_max_size.*|post_max_size = 64M|"                "$PHP_INI"
systemctl enable --now php8.4-fpm
ok "PHP-FPM configurado."

# ==================================================================
titulo "══ Nginx ══"
# ==================================================================

cat > /etc/nginx/sites-available/gwos <<NGINX
server {
    listen 80 default_server;
    server_name _;
    root ${GWOS_DIR}/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\. { deny all; }
    location = /favicon.ico { log_not_found off; }
}
NGINX

ln -sf /etc/nginx/sites-available/gwos /etc/nginx/sites-enabled/gwos
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl enable --now nginx && systemctl reload nginx
ok "Nginx configurado."

# ==================================================================
titulo "══ BIND9 ══"
# ==================================================================

cp "${GWOS_DIR}/config/named.conf.options" /etc/bind/named.conf.options
cp "${GWOS_DIR}/config/named.conf.local"   /etc/bind/named.conf.local
cp "${GWOS_DIR}/config/db.rpz.gwos"        /etc/bind/db.rpz.gwos
chown bind:bind /etc/bind/named.conf.options /etc/bind/named.conf.local /etc/bind/db.rpz.gwos

sed -i "s|192\.168\.1\.1;|${IP_GATEWAY};|g" /etc/bind/named.conf.options

mkdir -p /var/log/named
chown bind:bind /var/log/named
chmod 755 /var/log/named

named-checkconf
systemctl enable --now named
ok "BIND9 configurado."

# ==================================================================
titulo "══ Squid ══"
# ==================================================================

cp "${GWOS_DIR}/config/squid.conf" /etc/squid/squid.conf
sed -i "s|acl localnet src 192.168.0.0/16|acl localnet src ${REDE_LAN}|" /etc/squid/squid.conf

mkdir -p /etc/squid/conf.d
cp "${GWOS_DIR}/config/squid_ips_liberados.txt"  /etc/squid/conf.d/gwos_ips_liberados.txt
cp "${GWOS_DIR}/config/squid_ips_parciais.txt"   /etc/squid/conf.d/gwos_ips_parciais.txt
cp "${GWOS_DIR}/config/squid_ips_bloqueados.txt" /etc/squid/conf.d/gwos_ips_bloqueados.txt
cp "${GWOS_DIR}/config/squid_horarios.conf"      /etc/squid/conf.d/gwos_horarios.conf

# Listas de domínios e arquivos Squid — truncar/criar vazios na instalação
> /etc/squid/conf.d/gwos_whitelist.txt
> /etc/squid/conf.d/gwos_blacklist.txt
> /etc/squid/conf.d/gwos_ips_livres.txt
> /etc/squid/conf.d/gwos_sites_livres.txt
> /etc/squid/conf.d/gwos_tcp_outgoing.conf

# Detecta binário de geração de certificados SSL do Squid
CERTGEN=""
for p in /usr/lib/squid/security_file_certgen \
          /usr/libexec/squid/security_file_certgen \
          /usr/lib/squid4/security_file_certgen; do
    [ -x "$p" ] && { CERTGEN="$p"; break; }
done

if [ -n "$CERTGEN" ]; then
    # Certificado CA para SSL Bump
    SSL_DIR="/etc/squid/ssl_cert"
    mkdir -p "$SSL_DIR"
    openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
        -subj "/C=BR/ST=SP/O=GWOS/CN=GWOS Gateway CA" \
        -keyout "${SSL_DIR}/gwos-ca.key" \
        -out    "${SSL_DIR}/gwos-ca.crt"
    chmod 640 "${SSL_DIR}/gwos-ca.key" "${SSL_DIR}/gwos-ca.crt"
    chown root:proxy "${SSL_DIR}/gwos-ca.key" "${SSL_DIR}/gwos-ca.crt"

    # Banco de certificados dinâmicos do Squid
    SSL_DB="/var/lib/squid/ssl_db"
    # Garante que o diretório pai existe com o dono correto antes do certgen
    mkdir -p /var/lib/squid
    chown proxy:proxy /var/lib/squid
    [ -d "$SSL_DB" ] && rm -rf "$SSL_DB"
    runuser -u proxy -- "$CERTGEN" -c -s "$SSL_DB" -M 16MB

    # Expõe CA para download pelo painel
    cp "${SSL_DIR}/gwos-ca.crt" "${GWOS_DIR}/public/gwos-ca.crt"
    chown www-data:www-data "${GWOS_DIR}/public/gwos-ca.crt"
    chmod 644 "${GWOS_DIR}/public/gwos-ca.crt"

    # Atualiza squid.conf com o caminho correto do certgen
    sed -i "s|/usr/lib/squid/security_file_certgen|${CERTGEN}|g" /etc/squid/squid.conf

    ok "SSL Bump configurado. CA disponível em http://${IP_GATEWAY}/gwos-ca.crt"
    aviso "Instale o CA nos navegadores dos clientes para evitar alertas de certificado."
else
    aviso "security_file_certgen não encontrado — SSL Bump desativado."
    aviso "Instale squid-openssl e reexecute o instalador para ativar HTTPS interception."
    # Desativa as directivas SSL no squid.conf
    sed -i 's|^https_port|#https_port|g'       /etc/squid/squid.conf
    sed -i 's|^sslcrtd_|#sslcrtd_|g'           /etc/squid/squid.conf
    sed -i 's|^ssl_bump|#ssl_bump|g'            /etc/squid/squid.conf
    sed -i 's|^acl step1|#acl step1|g'          /etc/squid/squid.conf
    sed -i 's|ssl::server_name|dstdomain|g'     /etc/squid/squid.conf
fi

# Inicializa diretórios de cache do Squid (deve rodar após ssl_db estar pronto)
squid -z 2>/dev/null || true

# Popula listas de domínios do banco antes de iniciar o Squid
DB_HOST=127.0.0.1 DB_BANCO=gwos DB_USUARIO=gwos DB_SENHA="${DB_SENHA}" \
    bash "${GWOS_DIR}/scripts/gerar_squid_dominios.sh" --no-reconfigure 2>/dev/null || true

systemctl enable --now squid
ok "Squid configurado."

# ==================================================================
titulo "══ Firewall (nftables) ══"
# ==================================================================

systemctl enable nftables

cat > /etc/sysctl.d/99-gwos.conf <<SYSCTL
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1
SYSCTL
sysctl -p /etc/sysctl.d/99-gwos.conf

# Regras iniciais — estrutura completa, sem IPs no banco ainda
cat > /etc/nftables.conf <<NFT
#!/usr/sbin/nft -f

flush ruleset

table ip gwos_nat {

    set ip_liberados_nat {
        type ipv4_addr
        flags interval
        auto-merge
    }

    chain prerouting {
        type nat hook prerouting priority dstnat;
        # Tráfego LAN→LAN (inclui o gateway/painel): não intercepta
        iif "${IFACE_LAN}" ip daddr ${REDE_LAN} return
        # Proxy transparente — apenas tráfego saindo para internet
        iif "${IFACE_LAN}" ip saddr != @ip_liberados_nat tcp dport 80 redirect to :3128
        iif "${IFACE_LAN}" ip saddr != @ip_liberados_nat tcp dport 443 redirect to :3129
    }

    chain postrouting {
        type nat hook postrouting priority srcnat;
        # 1:1 NAT SNAT será inserido aqui pelo painel
        oif "${IFACE_WAN}" masquerade
    }
}

table inet gwos {

    set ip_bloqueados {
        type ipv4_addr
        flags interval
        auto-merge
    }

    set ip_parciais {
        type ipv4_addr
        flags interval
        auto-merge
    }

    chain input {
        type filter hook input priority filter; policy drop;
        ct state { established, related } accept
        ct state invalid drop
        iif lo accept
        iif "${IFACE_LAN}" ip protocol icmp accept
        iif "${IFACE_LAN}" ip saddr @ip_bloqueados drop
        iif "${IFACE_LAN}" accept
        iif "${IFACE_WAN}" icmp type { echo-reply, destination-unreachable, time-exceeded, parameter-problem } accept
        iif "${IFACE_WAN}" ct state new tcp dport 22 accept
        iif "${IFACE_WAN}" ct state new drop
    }

    chain forward {
        type filter hook forward priority filter; policy drop;
        ct state { established, related } accept
        ct state invalid drop
        iif "${IFACE_LAN}" ip saddr @ip_bloqueados drop
        ip protocol icmp accept
        iif "${IFACE_LAN}" oif "${IFACE_LAN}" accept
        iif "${IFACE_WAN}" oif "${IFACE_LAN}" accept
        iif "${IFACE_LAN}" oif "${IFACE_WAN}" accept
    }
}
NFT

nft -f /etc/nftables.conf
ok "nftables configurado."

# ==================================================================
titulo "══ Chrony (NTP) ══"
# ==================================================================

sed -i '/^pool\|^server/d' /etc/chrony/chrony.conf
echo "pool pool.ntp.br iburst" >> /etc/chrony/chrony.conf
systemctl enable --now chrony
ok "Chrony configurado."

# ==================================================================
titulo "══ Sudo / permissões ══"
# ==================================================================

# Garante que /etc/sudoers inclui o diretório sudoers.d
grep -q '@includedir /etc/sudoers.d' /etc/sudoers || echo '@includedir /etc/sudoers.d' >> /etc/sudoers

cat > /etc/sudoers.d/gwos <<SUDO
Defaults:www-data !requiretty
www-data ALL=(root) NOPASSWD: ${GWOS_DIR}/scripts/aplicar_nftables.sh
www-data ALL=(root) NOPASSWD: ${GWOS_DIR}/scripts/aplicar_nat.sh
www-data ALL=(root) NOPASSWD: ${GWOS_DIR}/scripts/aplicar_bind9_rpz.sh
www-data ALL=(root) NOPASSWD: ${GWOS_DIR}/scripts/gerar_squid_dominios.sh
www-data ALL=(root) NOPASSWD: ${GWOS_DIR}/scripts/gerar_squid_acl.sh
www-data ALL=(root) NOPASSWD: ${GWOS_DIR}/scripts/backup.sh
www-data ALL=(root) NOPASSWD: ${GWOS_DIR}/scripts/restaurar_backup.sh
www-data ALL=(root) NOPASSWD: ${GWOS_DIR}/scripts/importar_log_squid.sh
SUDO
chmod 440 /etc/sudoers.d/gwos
visudo -c -f /etc/sudoers.d/gwos   # valida antes de continuar

chmod +x "${GWOS_DIR}/scripts/"*.sh

# Instala o comando 'gwos' globalmente
ln -sf "${GWOS_DIR}/scripts/gwos-cli.sh" /usr/local/bin/gwos
chmod +x /usr/local/bin/gwos
ok "Permissões configuradas. Comando 'gwos' disponível no terminal."

# ==================================================================
titulo "══ Arquivo de ambiente ══"
# ==================================================================

cat > "${GWOS_DIR}/.env" <<ENV
APP_URL=http://${IP_GATEWAY}
APP_DEBUG=false
DB_HOST=127.0.0.1
DB_BANCO=gwos
DB_USUARIO=gwos
DB_SENHA=${DB_SENHA}
ENV
chmod 600 "${GWOS_DIR}/.env"
ok ".env criado."

# ==================================================================
titulo "══ Cron jobs ══"
# ==================================================================

cat > /etc/cron.d/gwos <<CRON
# GWOS — tarefas automáticas
0 2 * * * root /bin/bash ${GWOS_DIR}/scripts/backup.sh >> /var/log/gwos_backup.log 2>&1
*/5 * * * * root /usr/bin/php ${GWOS_DIR}/scripts/parsear_logs.php >> /var/log/gwos_parser.log 2>&1
0 * * * * root /bin/bash ${GWOS_DIR}/scripts/importar_log_squid.sh >> /var/log/gwos_import_log.log 2>&1
CRON
chmod 644 /etc/cron.d/gwos
ok "Crons configurados."

# ==================================================================
titulo "══ Diretórios e permissões finais ══"
# ==================================================================

mkdir -p /var/lib/gwos/backups
mkdir -p "${GWOS_DIR}/storage"
chown -R www-data:www-data /var/lib/gwos
chown -R www-data:www-data "${GWOS_DIR}/public"
chown -R www-data:www-data "${GWOS_DIR}/storage"
chown    www-data:www-data "${GWOS_DIR}/.env"
ok "Diretórios criados."

# ==================================================================
echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  GWOS instalado com sucesso!${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════${NC}"
echo ""
echo -e "  URL de acesso  : ${BOLD}http://${IP_GATEWAY}${NC}"
echo -e "  Login padrão   : ${BOLD}admin@gwos.local${NC}"
echo -e "  Senha padrão   : ${BOLD}gwos@2025${NC}"
echo ""
echo -e "  Interface WAN  : ${BOLD}${IFACE_WAN}${NC}"
echo -e "  Interface LAN  : ${BOLD}${IFACE_LAN}${NC}"
echo -e "  Rede LAN       : ${BOLD}${REDE_LAN}${NC}"
echo ""
echo -e "${BOLD}${CYAN}  Certificado CA (SSL Bump):${NC}"
echo -e "  Download       : ${BOLD}http://${IP_GATEWAY}/gwos-ca.crt${NC}"
echo -e "  ${YELLOW}Instale o CA em todos os navegadores/dispositivos da rede${NC}"
echo -e "  ${YELLOW}para evitar alertas de certificado no HTTPS.${NC}"
echo ""
echo -e "  ${YELLOW}Altere a senha no primeiro acesso!${NC}"
echo -e "  Credenciais do banco: ${BOLD}${GWOS_DIR}/.env${NC}"
echo ""
