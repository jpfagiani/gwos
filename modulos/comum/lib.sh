#!/bin/bash
# ============================================================================
# GWOS — Biblioteca comum dos módulos de instalação
# ============================================================================
# Carregada por todos os modulos/*/instalar.sh, desinstalar.sh e verificar.sh.
#
# Fornece:
#   - saída padronizada (ok/info/erro/aviso/titulo)
#   - estado compartilhado em /etc/gwos/gwos.conf
#   - registro dos módulos instalados em /etc/gwos/modulos.d/
#   - detecção de quais módulos/serviços existem na máquina
#   - utilitários de rede, pacotes e serviços
#
# É a peça que permite instalar cada servidor isoladamente: quem precisa
# saber "qual é a LAN", "qual é a rede", "o BIND9 existe?" pergunta aqui,
# em vez de depender do instalador monolítico.
# ============================================================================

[ -n "${GWOS_LIB_CARREGADA:-}" ] && return 0
GWOS_LIB_CARREGADA=1

# ----------------------------------------------------------------------------
# Saída
# ----------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()     { echo -e "${GREEN}[OK]${NC} $1"; }
info()   { echo -e "${YELLOW}[..]${NC} $1"; }
aviso()  { echo -e "${YELLOW}[!]${NC} $1"; }
erro()   { echo -e "${RED}[ERRO]${NC} $1" >&2; exit 1; }
falha()  { echo -e "${RED}[ERRO]${NC} $1" >&2; }           # não encerra
titulo() { echo -e "\n${BOLD}${CYAN}$1${NC}"; }

exigir_root() { [ "$(id -u)" -eq 0 ] || erro "Execute como root."; }

# ----------------------------------------------------------------------------
# Caminhos
# ----------------------------------------------------------------------------
GWOS_ETC="/etc/gwos"
GWOS_CONF="${GWOS_ETC}/gwos.conf"
GWOS_MODULOS="${GWOS_ETC}/modulos.d"
GWOS_DB_CONF="${GWOS_ETC}/db.conf"

# Diretório modulos/ (um nível acima de comum/)
GWOS_MODULOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Raiz do projeto GWOS (repositório) — vazio se o módulo foi copiado sozinho
raiz_projeto() {
    local d
    for d in "${GWOS_MODULOS_DIR}/.." "/opt/gwos" "/var/www/gwos"; do
        [ -f "${d}/public/index.php" ] && { (cd "$d" && pwd); return 0; }
    done
    return 1
}

# ----------------------------------------------------------------------------
# Conversões de rede
# ----------------------------------------------------------------------------
mascara_de_prefixo() {
    local p="${1:-24}" m=0 i
    for i in $(seq 1 "$p"); do m=$(( m | (1 << (32-i)) )); done
    echo "$(( (m>>24)&0xFF )).$(( (m>>16)&0xFF )).$(( (m>>8)&0xFF )).$(( m&0xFF ))"
}

prefixo_de_mascara() {
    local oct bit p=0
    IFS='.' read -r _m1 _m2 _m3 _m4 <<< "${1:-255.255.255.0}"
    for oct in $_m1 $_m2 $_m3 $_m4; do
        for bit in 128 64 32 16 8 4 2 1; do
            (( oct & bit )) && p=$((p+1)) || true
        done
    done
    echo "$p"
}

# rede_de_ip <ip> <prefixo>  →  10.0.0.0/8
rede_de_ip() {
    local ip="$1" pref="${2:-24}" a b c d bits m na
    IFS='.' read -r a b c d <<< "$ip"
    bits=$((32 - pref))
    m=$(( (0xFFFFFFFF << bits) & 0xFFFFFFFF ))
    na=$(( (a << 24 | b << 16 | c << 8 | d) & m ))
    echo "$(( (na>>24)&0xFF )).$(( (na>>16)&0xFF )).$(( (na>>8)&0xFF )).$(( na&0xFF ))/${pref}"
}

valida_ip()   { echo "$1" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; }
valida_cidr() { echo "$1" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'; }

listar_ifaces() {
    ip -o link show 2>/dev/null \
        | awk -F': ' '{print $2}' \
        | grep -Ev '^(lo|docker|veth|br-|virbr|tun|tap)' \
        | sort
}

# ----------------------------------------------------------------------------
# Estado compartilhado — /etc/gwos/gwos.conf
# ----------------------------------------------------------------------------
# Chaves:
#   IFACE_WAN IFACE_LAN REDE_LAN IP_GATEWAY
#   REDE2_ATIVO IP_ALIAS REDE2_CIDR REDE2_MASK
#   DOMINIO_LOCAL SQUID_PORTA SQUID_PORTA_SSL SQUID_PORTA_FWD DNSMASQ_PORTA
# ----------------------------------------------------------------------------

carregar_conf() {
    mkdir -p "$GWOS_ETC" "$GWOS_MODULOS"
    chmod 755 "$GWOS_ETC"
    # shellcheck disable=SC1090
    [ -f "$GWOS_CONF" ] && { set -a; . "$GWOS_CONF"; set +a; }
    return 0
}

escrever_conf() {
    mkdir -p "$GWOS_ETC"
    cat > "$GWOS_CONF" <<CONF
# /etc/gwos/gwos.conf — estado compartilhado entre os módulos do GWOS
# Gerado em $(date '+%Y-%m-%d %H:%M:%S'). Editável, mas prefira 'gwos ip'
# para trocar o IP do gateway (ele revalida e recarrega tudo).

# ── Interfaces ──────────────────────────────────────────────────────────
IFACE_WAN=${IFACE_WAN}
IFACE_LAN=${IFACE_LAN}

# ── Rede interna principal ──────────────────────────────────────────────
REDE_LAN=${REDE_LAN}
IP_GATEWAY=${IP_GATEWAY}

# ── Rede secundária (alias LAN:1) ───────────────────────────────────────
REDE2_ATIVO=${REDE2_ATIVO:-0}
IP_ALIAS=${IP_ALIAS:-}
REDE2_CIDR=${REDE2_CIDR:-}
REDE2_MASK=${REDE2_MASK:-255.255.255.0}

# ── Nomes internos ──────────────────────────────────────────────────────
DOMINIO_LOCAL=${DOMINIO_LOCAL:-cdpni.local}

# ── Portas dos serviços ─────────────────────────────────────────────────
SQUID_PORTA_FWD=${SQUID_PORTA_FWD:-3127}
SQUID_PORTA=${SQUID_PORTA:-3128}
SQUID_PORTA_SSL=${SQUID_PORTA_SSL:-3129}
DNSMASQ_PORTA=${DNSMASQ_PORTA:-5353}
CONF
    chmod 644 "$GWOS_CONF"
}

# salvar_conf <chave> <valor> — altera uma chave preservando o resto
salvar_conf() {
    carregar_conf
    local chave="$1" valor="$2"
    printf -v "$chave" '%s' "$valor"
    escrever_conf
}

# Detecta rede a partir do sistema, sem perguntar nada.
# Usado quando um módulo é instalado isoladamente, sem o módulo 00-base.
detectar_rede() {
    local ifaces iface ip_cidr pref
    mapfile -t ifaces < <(listar_ifaces)

    IFACE_WAN="${IFACE_WAN:-$(ip route show default 2>/dev/null | awk '/default/{print $5}' | head -1)}"
    [ -n "${IFACE_WAN:-}" ] || IFACE_WAN="${ifaces[0]:-eth0}"

    if [ -z "${IFACE_LAN:-}" ]; then
        for iface in "${ifaces[@]}"; do
            [ "$iface" != "$IFACE_WAN" ] && { IFACE_LAN="$iface"; break; }
        done
    fi
    # Máquina de uma placa só: LAN = WAN (proxy/DNS isolado ainda funciona)
    IFACE_LAN="${IFACE_LAN:-$IFACE_WAN}"

    if [ -z "${IP_GATEWAY:-}" ] || [ -z "${REDE_LAN:-}" ]; then
        ip_cidr=$(ip -4 addr show "$IFACE_LAN" 2>/dev/null | awk '/inet /{print $2}' | head -1)
        if [ -n "$ip_cidr" ]; then
            IP_GATEWAY="${IP_GATEWAY:-$(echo "$ip_cidr" | cut -d/ -f1)}"
            pref=$(echo "$ip_cidr" | cut -d/ -f2)
            REDE_LAN="${REDE_LAN:-$(rede_de_ip "$IP_GATEWAY" "$pref")}"
        else
            IP_GATEWAY="${IP_GATEWAY:-192.168.1.1}"
            REDE_LAN="${REDE_LAN:-192.168.1.0/24}"
        fi
    fi
}

# Garante que /etc/gwos/gwos.conf existe. Nunca mexe em /etc/network/interfaces
# — só o módulo 00-base reconfigura a rede de verdade.
garantir_conf() {
    carregar_conf
    if [ ! -f "$GWOS_CONF" ]; then
        detectar_rede
        escrever_conf
        aviso "Sem ${GWOS_CONF} — parâmetros detectados automaticamente:"
        echo  "      WAN=${IFACE_WAN}  LAN=${IFACE_LAN}  rede=${REDE_LAN}  gateway=${IP_GATEWAY}"
        echo  "      Ajuste o arquivo (ou instale o módulo 00-base) se estiver errado."
        carregar_conf
    fi
    # Preenche buracos em conf antigo/parcial
    local antes="${IFACE_WAN:-}${IFACE_LAN:-}${REDE_LAN:-}${IP_GATEWAY:-}"
    detectar_rede
    [ "$antes" = "${IFACE_WAN}${IFACE_LAN}${REDE_LAN}${IP_GATEWAY}" ] || escrever_conf
    carregar_conf
}

# Todas as redes internas conhecidas (principal + secundária), separadas por espaço
redes_internas() {
    local r="$REDE_LAN"
    [ "${REDE2_ATIVO:-0}" = "1" ] && [ -n "${REDE2_CIDR:-}" ] && r="$r $REDE2_CIDR"
    echo "$r"
}

# ----------------------------------------------------------------------------
# Registro de módulos
# ----------------------------------------------------------------------------
registrar_modulo() {
    local nome="$1"
    mkdir -p "$GWOS_MODULOS"
    cat > "${GWOS_MODULOS}/${nome}" <<REG
instalado_em=$(date '+%Y-%m-%d %H:%M:%S')
origem=${GWOS_MODULOS_DIR}
REG
}

desregistrar_modulo() { rm -f "${GWOS_MODULOS}/${1}"; }
modulo_registrado()   { [ -f "${GWOS_MODULOS}/${1}" ]; }

modulos_instalados() {
    [ -d "$GWOS_MODULOS" ] || return 0
    find "$GWOS_MODULOS" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort
}

# ----------------------------------------------------------------------------
# Detecção de serviços — marcador do módulo OU serviço presente na máquina
# ----------------------------------------------------------------------------
tem_bind9()    { modulo_registrado dns-bind9        || command -v named    >/dev/null 2>&1; }
tem_dnsmasq()  { modulo_registrado dns-interno      || [ -f /etc/dnsmasq.d/gwos.conf ]; }
tem_chrony()   { modulo_registrado hora-chrony      || command -v chronyd  >/dev/null 2>&1; }
tem_firewall() { modulo_registrado firewall-nftables|| command -v nft      >/dev/null 2>&1; }
tem_squid()    { modulo_registrado proxy-squid      || { command -v squid >/dev/null 2>&1 && [ -f /etc/squid/squid.conf ]; }; }
tem_banco()    { modulo_registrado banco-mariadb    || [ -f "$GWOS_DB_CONF" ]; }
tem_painel()   { modulo_registrado painel-web; }

# Squid com suporte a SSL Bump (certgen presente e CA gerada)
tem_ssl_bump() { [ -f /etc/squid/ssl_cert/gwos-ca.crt ]; }

# ----------------------------------------------------------------------------
# Pacotes e serviços
# ----------------------------------------------------------------------------
apt_atualizado=0
apt_update_uma_vez() {
    [ "$apt_atualizado" = "1" ] && return 0
    info "Atualizando lista de pacotes..."
    apt-get update -qq
    apt_atualizado=1
}

# instalar_pacotes <pkg>...  (obrigatórios — aborta se falhar)
instalar_pacotes() {
    apt_update_uma_vez
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" \
        || erro "Falha ao instalar: $*"
}

# instalar_opcional <pkg>  (melhor esforço)
instalar_opcional() {
    apt_update_uma_vez
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$1" 2>/dev/null \
        && ok "Pacote opcional instalado: $1" \
        || aviso "Pacote opcional indisponível: $1"
}

svc_ativar()  { systemctl enable --now "$1" >/dev/null 2>&1 || systemctl enable --now "$1"; }
svc_parar()   { systemctl stop "$1" 2>/dev/null || true; systemctl disable "$1" 2>/dev/null || true; }
svc_ativo()   { systemctl is-active --quiet "$1"; }

backup_arquivo() {
    [ -f "$1" ] || return 0
    cp -a "$1" "${1}.bak.$(date +%Y%m%d%H%M%S)"
}

perguntar() {
    local __var="$1" __prompt="$2" __padrao="${3:-}" __resp
    read -rp "  ${__prompt} [${__padrao}]: " __resp
    printf -v "$__var" '%s' "${__resp:-$__padrao}"
}

confirmar() {
    local resp
    read -rp "  $1 [s/N]: " resp
    [[ "${resp:-N}" =~ ^[Ss]$ ]]
}

# ----------------------------------------------------------------------------
# Ferramentas comuns no sistema
# ----------------------------------------------------------------------------
# Instala lib.sh e integrar.sh fora do repositório, para que a integração
# funcione mesmo que a pasta modulos/ seja apagada ou movida depois.
instalar_ferramentas_comuns() {
    mkdir -p "$GWOS_ETC" "$GWOS_MODULOS"
    local origem="${GWOS_MODULOS_DIR}/comum"
    [ -f "${origem}/lib.sh" ]      && install -m 644 "${origem}/lib.sh"      "${GWOS_ETC}/lib.sh"
    [ -f "${origem}/integrar.sh" ] && install -m 755 "${origem}/integrar.sh" /usr/local/sbin/gwos-integrar
    return 0
}

# Re-costura as integrações entre os módulos presentes.
integrar() {
    if [ -x /usr/local/sbin/gwos-integrar ]; then
        /usr/local/sbin/gwos-integrar "$@"
    elif [ -f "${GWOS_MODULOS_DIR}/comum/integrar.sh" ]; then
        bash "${GWOS_MODULOS_DIR}/comum/integrar.sh" "$@"
    else
        aviso "integrar.sh não encontrado — integração entre módulos não executada."
    fi
}

# Cabeçalho padrão de módulo: root + conf + ferramentas comuns
iniciar_modulo() {
    local nome="$1"
    exigir_root
    titulo "══ Módulo: ${nome} ══"
    instalar_ferramentas_comuns
    garantir_conf
}
