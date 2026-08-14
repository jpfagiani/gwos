#!/bin/bash
# ============================================================================
# GWOS — Instala todos os módulos, na ordem
# ============================================================================
# Equivale ao instalador antigo, só que montado a partir dos módulos: cada um
# continua instalável sozinho, e este script apenas os executa em sequência.
#
#   bash instalar-todos.sh                  # tudo
#   bash instalar-todos.sh 20-dns-bind9 50-proxy-squid   # só os listados
#   bash instalar-todos.sh --pular 00-base  # tudo menos os listados
#   bash instalar-todos.sh --listar         # mostra a ordem e sai
# ============================================================================

set -uo pipefail

MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${MOD_DIR}/comum/lib.sh"

ORDEM=(
    00-base
    10-banco-mariadb
    20-dns-bind9
    25-dns-interno-dnsmasq
    30-hora-chrony
    40-firewall-nftables
    50-proxy-squid
    60-painel-web
)

if [ "${1:-}" = "--listar" ]; then
    echo "Ordem de instalação:"
    for m in "${ORDEM[@]}"; do echo "  $m"; done
    exit 0
fi

exigir_root

PULAR=()
SELECIONADOS=()
if [ "${1:-}" = "--pular" ]; then
    shift; PULAR=("$@")
elif [ $# -gt 0 ]; then
    SELECIONADOS=("$@")
fi

pular() {
    local m="$1" p
    for p in ${PULAR[@]+"${PULAR[@]}"}; do [ "$p" = "$m" ] && return 0; done
    return 1
}
selecionado() {
    local m="$1" s
    [ ${#SELECIONADOS[@]} -eq 0 ] && return 0
    for s in "${SELECIONADOS[@]}"; do [ "$s" = "$m" ] && return 0; done
    return 1
}

echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}  GWOS — instalação modular${NC}"
echo -e "${BOLD}${CYAN}══════════════════════════════════════════════${NC}"

FALHOU=()
INSTALADOS=()

for m in "${ORDEM[@]}"; do
    selecionado "$m" || continue
    pular "$m" && { aviso "Pulando ${m}."; continue; }
    [ -f "${MOD_DIR}/${m}/instalar.sh" ] || { aviso "Módulo ${m} não encontrado — pulando."; continue; }

    if bash "${MOD_DIR}/${m}/instalar.sh"; then
        INSTALADOS+=("$m")
    else
        FALHOU+=("$m")
        falha "Módulo ${m} falhou."
        confirmar "Continuar com os próximos módulos?" || break
    fi
done

# Passe final de integração: agora que todos existem, refaz as amarrações
integrar

echo ""
echo -e "${BOLD}${CYAN}══════════════════════════════════════════════${NC}"
if [ ${#FALHOU[@]} -eq 0 ]; then
    echo -e "${GREEN}${BOLD}  GWOS instalado com sucesso!${NC}"
else
    echo -e "${YELLOW}${BOLD}  GWOS instalado com pendências.${NC}"
    echo -e "  Módulos com falha: ${BOLD}${FALHOU[*]}${NC}"
fi
echo -e "${BOLD}${CYAN}══════════════════════════════════════════════${NC}"
echo ""

carregar_conf
echo -e "  Painel      : ${BOLD}http://${IP_GATEWAY:-?}${NC}"
echo -e "  Login       : ${BOLD}admin@gwos.local${NC}   Senha: ${BOLD}gwos@2025${NC}"
echo -e "  Interfaces  : WAN ${BOLD}${IFACE_WAN:-?}${NC}  |  LAN ${BOLD}${IFACE_LAN:-?}${NC}"
echo -e "  Rede LAN    : ${BOLD}${REDE_LAN:-?}${NC}"
if tem_ssl_bump; then
    echo -e "  Certificado : ${BOLD}http://${IP_GATEWAY}/gwos-ca.crt${NC} — instale nos clientes"
fi
echo ""
echo -e "  Conferir tudo: ${BOLD}bash ${MOD_DIR}/verificar-todos.sh${NC}"
echo -e "  ${YELLOW}Troque a senha no primeiro acesso.${NC}"
echo ""

[ ${#FALHOU[@]} -eq 0 ]
