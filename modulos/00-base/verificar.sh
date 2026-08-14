#!/bin/bash
# GWOS — Módulo 00-base: verificação
# Saída 0 = tudo certo; 1 = há problemas.

set -uo pipefail

MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _l in "${MOD_DIR}/../comum/lib.sh" "/etc/gwos/lib.sh"; do
    # shellcheck disable=SC1090
    [ -f "$_l" ] && { . "$_l"; break; }
done
[ -n "${GWOS_LIB_CARREGADA:-}" ] || { echo "ERRO: comum/lib.sh não encontrado."; exit 1; }

carregar_conf
FALHAS=0
titulo "── Verificação: 00-base ──"

if [ -f "$GWOS_CONF" ]; then
    ok "Estado presente: ${GWOS_CONF}"
    echo "     WAN=${IFACE_WAN:-?}  LAN=${IFACE_LAN:-?}  rede=${REDE_LAN:-?}  gateway=${IP_GATEWAY:-?}"
else
    falha "Ausente: ${GWOS_CONF}"; FALHAS=$((FALHAS+1))
fi

for IF in "${IFACE_WAN:-}" "${IFACE_LAN:-}"; do
    [ -z "$IF" ] && continue
    if ip link show "$IF" &>/dev/null; then
        EST=$(cat "/sys/class/net/${IF}/operstate" 2>/dev/null || echo "?")
        IPS=$(ip -4 -o addr show "$IF" 2>/dev/null | awk '{print $4}' | paste -sd ' ' -)
        ok "Interface ${IF}: ${EST}  ${IPS:-sem IP}"
    else
        falha "Interface ${IF} não existe neste kernel."; FALHAS=$((FALHAS+1))
    fi
done

if [ -n "${IP_GATEWAY:-}" ] && ip -4 addr show 2>/dev/null | grep -q " ${IP_GATEWAY}/"; then
    ok "IP do gateway ${IP_GATEWAY} configurado."
else
    falha "IP ${IP_GATEWAY:-?} não está atribuído a nenhuma interface."; FALHAS=$((FALHAS+1))
fi

if [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" = "1" ]; then
    ok "Encaminhamento de pacotes (ip_forward) ativo."
else
    falha "ip_forward desativado — a máquina não roteia."; FALHAS=$((FALHAS+1))
fi

if ip route show default 2>/dev/null | grep -q .; then
    ok "Rota padrão: $(ip route show default | head -1)"
else
    falha "Sem rota padrão — sem saída para a internet."; FALHAS=$((FALHAS+1))
fi

echo ""
[ "$FALHAS" -eq 0 ] && ok "00-base OK." || falha "00-base com ${FALHAS} problema(s)."
exit $(( FALHAS > 0 ? 1 : 0 ))
