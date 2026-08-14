#!/bin/bash
# ============================================================================
# GWOS — Módulo 00-base: rede, hardware e estado compartilhado
# ============================================================================
# É o único módulo que mexe em /etc/network/interfaces. Todos os outros só
# LEEM os parâmetros de rede em /etc/gwos/gwos.conf.
#
# Instala/configura:
#   - firmware de placas de rede e microcode da CPU (só em máquina física)
#   - fixação do nome das interfaces pelo MAC (só em máquina física)
#   - /etc/network/interfaces (WAN + LAN + alias da rede secundária)
#   - /etc/sysctl.d/90-gwos-base.conf (encaminhamento de pacotes)
#   - /etc/gwos/gwos.conf (estado lido por todos os demais módulos)
#
# Opcional: os outros módulos detectam a rede sozinhos se este não for usado.
# ============================================================================

set -euo pipefail

MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _l in "${MOD_DIR}/../comum/lib.sh" "/etc/gwos/lib.sh"; do
    # shellcheck disable=SC1090
    [ -f "$_l" ] && { . "$_l"; break; }
done
[ -n "${GWOS_LIB_CARREGADA:-}" ] || {
    echo "ERRO: comum/lib.sh não encontrado. Copie a pasta 'comum/' junto com o módulo."
    exit 1; }

exigir_root
titulo "══ Módulo 00-base — rede e preparação da máquina ══"
instalar_ferramentas_comuns

instalar_pacotes ifupdown iproute2 sudo curl ca-certificates

# ===========================================================================
# 1. Interfaces de rede
# ===========================================================================
titulo "── Interfaces de rede ──"
echo ""

mapfile -t IFACES < <(listar_ifaces)
[ ${#IFACES[@]} -gt 0 ] || erro "Nenhuma interface de rede encontrada."

# ---------------------------------------------------------------------------
# Uma placa só: esta máquina não pode ser gateway, e o 00-base não se aplica.
# Sai com código 2 — o instalar-todos entende como "não aplicável", não falha.
# ---------------------------------------------------------------------------
if [ ${#IFACES[@]} -lt 2 ]; then
    echo ""
    aviso "Esta máquina tem uma única interface de rede (${IFACES[0]})."
    echo ""
    echo "  O módulo 00-base configura o roteamento entre a internet (WAN) e a"
    echo "  rede interna (LAN). Isso exige duas placas — é o módulo de gateway."
    echo ""
    echo -e "  ${BOLD}Se este servidor é só DNS, hora, proxy ou painel, você não precisa dele.${NC}"
    echo "  Os demais módulos detectam a rede sozinhos e não encostam no"
    echo "  /etc/network/interfaces:"
    echo ""
    echo -e "    ${BOLD}bash ${GWOS_MODULOS_DIR}/20-dns-bind9/instalar.sh${NC}"
    echo -e "    ${BOLD}bash ${GWOS_MODULOS_DIR}/30-hora-chrony/instalar.sh${NC}"
    echo ""
    echo "  Se a segunda placa existe mas não apareceu, verifique o firmware"
    echo "  (ip -br link) e reexecute este módulo."
    echo ""
    info "Módulo 00-base não se aplica — nada foi alterado."
    exit 2
fi

printf "  %-4s %-14s %-22s %-8s %s\n" "Nº" "Interface" "IP/Máscara" "Status" "Velocidade"
echo "  ──────────────────────────────────────────────────────────────"
IDX=1
for iface in "${IFACES[@]}"; do
    IP_CIDR=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet /{print $2}' | head -1)
    IP_CIDR="${IP_CIDR:-sem IP}"
    STATUS=$(cat "/sys/class/net/${iface}/operstate" 2>/dev/null || echo "?")
    case "$STATUS" in
        up)   SFMT="${GREEN}UP${NC}"   ;;
        down) SFMT="${RED}DOWN${NC}"   ;;
        *)    SFMT="${YELLOW}${STATUS}${NC}" ;;
    esac
    SPEED=$(cat "/sys/class/net/${iface}/speed" 2>/dev/null || echo "?")
    if [[ "$SPEED" =~ ^-?[0-9]+$ ]] && [ "$SPEED" -gt 0 ]; then SPEED="${SPEED} Mb/s"; else SPEED="?"; fi
    printf "  %-4s %-14s %-22s " "$IDX" "$iface" "$IP_CIDR"
    echo -e "${SFMT}    ${SPEED}"
    IDX=$((IDX + 1))
done
echo ""

selecionar_iface() {
    local PROMPT="$1" SUGESTAO="$2" RESULTADO="" ENT POS
    while true; do
        [ -n "$SUGESTAO" ] && \
            echo -e "  Sugestão: ${BOLD}${SUGESTAO}${NC}  (Enter para confirmar, ou digite outra)" >&2
        read -rp "  $PROMPT [${SUGESTAO:-nome ou número}]: " ENT
        ENT="${ENT:-$SUGESTAO}"
        if [[ "$ENT" =~ ^[0-9]+$ ]]; then
            POS=$((ENT - 1))
            if [ "$POS" -ge 0 ] && [ "$POS" -lt ${#IFACES[@]} ]; then
                RESULTADO="${IFACES[$POS]}"; break
            fi
            echo -e "  ${RED}Número inválido. Escolha entre 1 e ${#IFACES[@]}.${NC}" >&2
        elif [ -n "$ENT" ]; then
            if ip link show "$ENT" &>/dev/null; then RESULTADO="$ENT"; break; fi
            echo -e "  ${RED}Interface '${ENT}' não encontrada.${NC}" >&2
        else
            echo -e "  ${RED}Informe a interface.${NC}" >&2
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
    [ "$iface" != "$IFACE_WAN" ] && { LAN_AUTO="$iface"; break; }
done
IFACE_LAN=$(selecionar_iface "Interface LAN" "$LAN_AUTO")
if [ "$IFACE_LAN" = "$IFACE_WAN" ]; then
    echo ""
    aviso "WAN e LAN não podem ser a mesma interface — um gateway roteia de uma"
    aviso "placa para a outra."
    echo "  Interfaces disponíveis: ${IFACES[*]}"
    echo "  Se esta máquina não é gateway, pule o 00-base e instale só os"
    echo "  serviços que você precisa (DNS, hora, proxy, painel)."
    exit 1
fi
ok "LAN: $IFACE_LAN"

# ===========================================================================
# 2. Rede interna
# ===========================================================================
titulo "── Rede LAN ──"
echo ""

IP_LAN_CIDR=$(ip -4 addr show "$IFACE_LAN" 2>/dev/null | awk '/inet /{print $2}' | head -1 || true)
if [ -n "$IP_LAN_CIDR" ]; then
    IP_GW_SUGERIDO=$(echo "$IP_LAN_CIDR" | cut -d/ -f1)
    REDE_SUGERIDA=$(rede_de_ip "$IP_GW_SUGERIDO" "$(echo "$IP_LAN_CIDR" | cut -d/ -f2)")
else
    REDE_SUGERIDA="192.168.1.0/24"
    IP_GW_SUGERIDO="192.168.1.1"
fi

echo -e "  Sugestão de rede LAN : ${BOLD}${REDE_SUGERIDA}${NC}"
echo -e "  Sugestão de IP       : ${BOLD}${IP_GW_SUGERIDO}${NC}"
echo -e "  ${YELLOW}(Enter aceita a sugestão)${NC}"
echo ""

perguntar REDE_LAN "Rede LAN em CIDR" "$REDE_SUGERIDA"
while ! valida_cidr "$REDE_LAN"; do
    echo -e "  ${RED}Rede inválida: '${REDE_LAN}' — use CIDR (ex: 192.168.1.0/24)${NC}"
    perguntar REDE_LAN "Rede LAN em CIDR" "$REDE_SUGERIDA"
done

perguntar IP_GATEWAY "IP deste gateway na LAN" "$IP_GW_SUGERIDO"
while ! valida_ip "$IP_GATEWAY"; do
    echo -e "  ${RED}IP inválido: '${IP_GATEWAY}' — use IPv4 (ex: 192.168.1.1)${NC}"
    perguntar IP_GATEWAY "IP deste gateway na LAN" "$IP_GW_SUGERIDO"
done
ok "Rede: $REDE_LAN  |  Gateway: $IP_GATEWAY"

# --- Rede secundária (alias) -----------------------------------------------
titulo "── Rede Secundária / Alias (opcional) ──"
echo ""
echo -e "  IP secundário na LAN para rotear entre duas sub-redes."
echo -e "  Exemplo: GWOS em 172.14.29.10 + alias 10.14.29.254 para a rede 10.x"
echo ""

REDE2_ATIVO=0; IP_ALIAS=""; REDE2_MASK="255.255.255.0"; REDE2_CIDR=""; REDE2_PREFIX=24
if confirmar "Configurar rede secundária?"; then
    REDE2_ATIVO=1
    perguntar IP_ALIAS "IP do alias na rede secundária (ex: 10.14.29.254)" ""
    while ! valida_ip "$IP_ALIAS"; do
        echo -e "  ${RED}IP inválido.${NC}"
        perguntar IP_ALIAS "IP do alias" ""
    done
    perguntar REDE2_MASK "Máscara da rede secundária" "255.255.255.0"
    REDE2_PREFIX=$(prefixo_de_mascara "$REDE2_MASK")
    REDE2_CIDR=$(rede_de_ip "$IP_ALIAS" "$REDE2_PREFIX")
    ok "Alias: ${IFACE_LAN}:1  IP: ${IP_ALIAS}  Rede: ${REDE2_CIDR}"
fi

# --- Domínio interno --------------------------------------------------------
titulo "── Domínio interno ──"
echo ""
perguntar DOMINIO_LOCAL "Domínio dos nomes da LAN" "${DOMINIO_LOCAL:-cdpni.local}"

# --- WAN --------------------------------------------------------------------
titulo "── Configuração da WAN ──"
echo ""
WAN_IP_ATUAL=$(ip -4 addr show "$IFACE_WAN" 2>/dev/null | awk '/inet /{print $2}' | head -1 || true)
WAN_GW_ATUAL=$(ip route show default 2>/dev/null | awk '/default/{print $3}' | head -1 || true)
echo -e "  IP atual da WAN  : ${BOLD}${WAN_IP_ATUAL:-sem IP}${NC}"
echo -e "  Gateway WAN atual: ${BOLD}${WAN_GW_ATUAL:-não detectado}${NC}"
echo ""

perguntar WAN_DHCP "WAN usa DHCP? (S/n)" "S"
if [[ "$WAN_DHCP" =~ ^[Ss]$ ]]; then
    WAN_MODO="dhcp"; WAN_IP=""; WAN_MASK=""; WAN_GW=""; WAN_DNS=""
    ok "WAN: DHCP"
else
    WAN_MODO="static"
    WAN_IP_DEF=$(echo "$WAN_IP_ATUAL" | cut -d/ -f1)
    WAN_PREF=$(echo "$WAN_IP_ATUAL" | cut -d/ -f2)
    perguntar WAN_IP   "IP estático WAN" "$WAN_IP_DEF"
    perguntar WAN_MASK "Máscara de rede" "$(mascara_de_prefixo "${WAN_PREF:-24}")"
    perguntar WAN_GW   "Gateway padrão"  "$WAN_GW_ATUAL"
    perguntar WAN_DNS  "DNS primário"    "8.8.8.8"
    WAN_PREF=$(prefixo_de_mascara "$WAN_MASK")
    ok "WAN: IP=$WAN_IP  Máscara=$WAN_MASK  GW=$WAN_GW  DNS=$WAN_DNS"
fi

LAN_PREF=$(echo "$REDE_LAN" | cut -d/ -f2)
LAN_MASK=$(mascara_de_prefixo "$LAN_PREF")

# --- Resumo -----------------------------------------------------------------
titulo "── Resumo ──"
echo ""
echo -e "  WAN            : ${BOLD}${IFACE_WAN}${NC} (${WAN_MODO})"
echo -e "  LAN            : ${BOLD}${IFACE_LAN}${NC}"
echo -e "  Rede LAN       : ${BOLD}${REDE_LAN}${NC}"
echo -e "  IP Gateway     : ${BOLD}${IP_GATEWAY}${NC}"
echo -e "  Domínio interno: ${BOLD}${DOMINIO_LOCAL}${NC}"
[ "$REDE2_ATIVO" = "1" ] && \
    echo -e "  Rede 2         : ${BOLD}${REDE2_CIDR}  alias ${IFACE_LAN}:1 → ${IP_ALIAS}${NC}"
echo ""
confirmar "Aplicar esta configuração de rede?" || { echo "Cancelado."; exit 0; }

# ===========================================================================
# 3. Preparação do hardware (só em máquina física)
# ===========================================================================
titulo "══ Preparação do hardware ══"

VIRT="$(systemd-detect-virt 2>/dev/null || echo desconhecido)"
if [ "$VIRT" != "none" ]; then
    info "Ambiente virtualizado (${VIRT}) — firmware de hardware não é necessário."
else
    info "Máquina real detectada — habilitando firmware e microcode..."

    if ! grep -Rqs "non-free-firmware" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
        if [ -f /etc/apt/sources.list.d/debian.sources ]; then
            sed -i 's/^Components: \(.*\)/Components: \1 non-free-firmware/' \
                /etc/apt/sources.list.d/debian.sources
        elif [ -f /etc/apt/sources.list ]; then
            sed -Ei '/debian\.org/ s/^(deb[[:space:]].*[[:space:]]main)([[:space:]]|$)/\1 non-free-firmware\2/' \
                /etc/apt/sources.list
        fi
        apt-get update -qq
        apt_atualizado=1
        ok "Componente non-free-firmware habilitado."
    fi

    for pkg in firmware-linux firmware-realtek firmware-misc-nonfree; do
        instalar_opcional "$pkg"
    done

    CPU_VENDOR=$(grep -m1 vendor_id /proc/cpuinfo | awk '{print $3}' || true)
    case "$CPU_VENDOR" in
        GenuineIntel) instalar_opcional intel-microcode ;;
        AuthenticAMD) instalar_opcional amd64-microcode ;;
        *)            aviso "CPU não identificada (${CPU_VENDOR:-vazio}) — microcode não instalado." ;;
    esac

    if dmesg 2>/dev/null | grep -iE "firmware.*(failed|error)|failed to load firmware" | head -3 | grep -q .; then
        aviso "O kernel registrou falhas de firmware no boot atual — reinicie após a instalação."
    fi

    if systemctl is-enabled NetworkManager &>/dev/null; then
        systemctl disable --now NetworkManager 2>/dev/null || true
        aviso "NetworkManager desativado — as interfaces passam ao controle do ifupdown."
    fi
fi

# ===========================================================================
# 4. /etc/network/interfaces
# ===========================================================================
titulo "══ Configuração de rede ══"

backup_arquivo /etc/network/interfaces

cat > /etc/network/interfaces <<NETEOF
# /etc/network/interfaces — gerado pelo módulo 00-base do GWOS
# em $(date '+%Y-%m-%d %H:%M:%S').
# Para trocar o IP do gateway use 'gwos ip', nunca edite à mão.

source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

# WAN — saída para a internet
auto ${IFACE_WAN}
NETEOF

if [ "$WAN_MODO" = "dhcp" ]; then
    printf 'iface %s inet dhcp\n\n' "$IFACE_WAN" >> /etc/network/interfaces
else
    cat >> /etc/network/interfaces <<NETEOF
iface ${IFACE_WAN} inet static
    address ${WAN_IP}
    netmask ${WAN_MASK}
    gateway ${WAN_GW}
    dns-nameservers ${WAN_DNS}

NETEOF
fi

cat >> /etc/network/interfaces <<NETEOF
# LAN — rede interna (IP fixo — este servidor é o gateway)
auto ${IFACE_LAN}
iface ${IFACE_LAN} inet static
    address ${IP_GATEWAY}
    netmask ${LAN_MASK}

NETEOF

if [ "$REDE2_ATIVO" = "1" ]; then
    cat >> /etc/network/interfaces <<NETEOF
# Alias secundário — roteamento para a rede ${REDE2_CIDR}
auto ${IFACE_LAN}:1
iface ${IFACE_LAN}:1 inet static
    address ${IP_ALIAS}
    netmask ${REDE2_MASK}

NETEOF
fi

ok "/etc/network/interfaces gerado."

# Fixa o nome das interfaces pelo MAC (só em máquina real)
if [ "$VIRT" = "none" ]; then
    mkdir -p /etc/systemd/network
    for IFPIN in "$IFACE_WAN" "$IFACE_LAN"; do
        MACPIN=$(cat "/sys/class/net/${IFPIN}/address" 2>/dev/null || true)
        if [ -n "$MACPIN" ] && [ "$MACPIN" != "00:00:00:00:00:00" ]; then
            cat > "/etc/systemd/network/70-gwos-${IFPIN}.link" <<LINKEOF
# Gerado pelo GWOS — mantém o nome '${IFPIN}' amarrado a esta placa física.
# Se trocar a placa de rede, apague este arquivo e reexecute o módulo 00-base.
[Match]
MACAddress=${MACPIN}

[Link]
Name=${IFPIN}
LINKEOF
            ok "Nome '${IFPIN}' fixado ao MAC ${MACPIN}."
        fi
    done
    update-initramfs -u -k all >/dev/null 2>&1 || true
fi

# Aplica sem reiniciar o serviço de rede (não derruba a sessão SSH)
ip addr flush dev "$IFACE_LAN" 2>/dev/null || true
ip addr add "${IP_GATEWAY}/${LAN_PREF}" dev "$IFACE_LAN" 2>/dev/null || true
ip link set "$IFACE_LAN" up 2>/dev/null || true
[ "$REDE2_ATIVO" = "1" ] && \
    ip addr add "${IP_ALIAS}/${REDE2_PREFIX}" dev "$IFACE_LAN" 2>/dev/null || true

if [ "$WAN_MODO" = "static" ]; then
    ip addr flush dev "$IFACE_WAN" 2>/dev/null || true
    ip addr add "${WAN_IP}/${WAN_PREF:-24}" dev "$IFACE_WAN" 2>/dev/null || true
    ip link set "$IFACE_WAN" up 2>/dev/null || true
    ip route replace default via "$WAN_GW" dev "$IFACE_WAN" 2>/dev/null || true
fi
ok "Configuração de rede aplicada."

# ===========================================================================
# 5. Encaminhamento de pacotes
# ===========================================================================
cat > /etc/sysctl.d/90-gwos-base.conf <<SYSCTL
# GWOS — parâmetros de kernel do gateway (módulo 00-base)
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1
SYSCTL
sysctl -p /etc/sysctl.d/90-gwos-base.conf >/dev/null
ok "Encaminhamento de pacotes ativado."

# ===========================================================================
# 6. Estado compartilhado
# ===========================================================================
escrever_conf
ok "Estado gravado em ${GWOS_CONF}."

registrar_modulo base
integrar

echo ""
ok "Módulo 00-base instalado."
echo -e "  Próximos módulos: ${BOLD}10-banco-mariadb${NC}, ${BOLD}20-dns-bind9${NC}, ${BOLD}25-dns-interno-dnsmasq${NC},"
echo -e "                    ${BOLD}30-hora-chrony${NC}, ${BOLD}40-firewall-nftables${NC}, ${BOLD}50-proxy-squid${NC}, ${BOLD}60-painel-web${NC}"
echo ""
