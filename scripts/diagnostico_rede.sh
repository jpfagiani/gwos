#!/bin/bash
# GWOS — diagnóstico de conectividade do gateway.
# Uso: gwos rede [IP_DO_CLIENTE]      (como root)
# Só lê o estado; não altera nada. Cada linha diz OK / PROBLEMA e o que fazer.
set -uo pipefail
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _l in "$AQUI/../modulos/comum/lib.sh" /etc/gwos/lib.sh; do [ -f "$_l" ] && { . "$_l"; break; }; done
type carregar_conf >/dev/null 2>&1 && carregar_conf 2>/dev/null || true

CLIENTE="${1:-}"
P=0
okk()  { echo -e "  \e[32m[OK]\e[0m $*"; }
bad()  { echo -e "  \e[31m[PROBLEMA]\e[0m $*"; P=$((P+1)); }
inf()  { echo -e "  \e[36m[..]\e[0m $*"; }
sec()  { echo -e "\n\e[1m── $* ──\e[0m"; }

[ "$(id -u)" -eq 0 ] || { echo "Rode como root."; exit 1; }
WAN="${IFACE_WAN:-}"; LAN="${IFACE_LAN:-}"

sec "Interfaces"
inf "WAN=${WAN:-?}  LAN=${LAN:-?}"
for i in "$WAN" "$LAN"; do
    [ -n "$i" ] || continue
    if ip -4 addr show "$i" 2>/dev/null | grep -q 'inet '; then okk "$i: $(ip -4 -o addr show "$i" | awk '{print $4}' | paste -sd ' ' -)"
    else bad "$i sem IP IPv4."; fi
done
[ -n "$LAN" ] && [ -n "${IP_GATEWAY:-}" ] && inf "IP do gateway na LAN (gwos.conf): ${IP_GATEWAY}  — o cliente deve usar ESTE IP como gateway e como proxy."

sec "Rota e roteamento"
DEF="$(ip route show default 2>/dev/null | head -1)"
if [ -n "$DEF" ]; then okk "Rota padrão: $DEF"; else bad "Sem rota padrão: o servidor não sabe sair para a internet (veja o DHCP/gateway da WAN)."; fi
if [ -n "$WAN" ] && [ -n "$DEF" ] && ! echo "$DEF" | grep -q "dev $WAN"; then bad "A rota padrão não sai pela WAN ($WAN)."; fi
[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" = "1" ] && okk "ip_forward ligado." || bad "ip_forward DESLIGADO: o servidor não roteia. Corrija: sysctl -w net.ipv4.ip_forward=1"

sec "Saída do próprio servidor"
ping -c1 -W3 8.8.8.8 >/dev/null 2>&1 && okk "ping 8.8.8.8 funciona (internet por IP)." || bad "O servidor não alcança 8.8.8.8: o problema está antes do GWOS (WAN/NAT da VM, cabo, DHCP)."
if getent hosts google.com >/dev/null 2>&1; then okk "Resolve nomes (google.com)."; else bad "Servidor não resolve nomes. Veja /etc/resolv.conf e o BIND (abaixo)."; fi
grep -q '^nameserver' /etc/resolv.conf 2>/dev/null && okk "resolv.conf: $(awk '/^nameserver/{print $2}' /etc/resolv.conf | paste -sd ' ' -)" || bad "/etc/resolv.conf sem nameserver."

sec "Firewall (nftables)"
if nft list table ip gwos_nat >/dev/null 2>&1; then okk "Tabela NAT carregada."; else bad "Tabela gwos_nat não carregada. Rode: gwos reload nftables"; fi
nft list chain ip gwos_nat postrouting 2>/dev/null | grep -q masquerade && okk "Masquerade ativo na WAN." || bad "SEM masquerade: clientes saem com IP privado e a internet não responde. Ative o NAT no painel (NAT) e rode: gwos reload nftables"
nft list chain inet gwos forward 2>/dev/null | grep -q 'icmp accept' && okk "ICMP liberado no forward." || inf "Regra de ICMP no forward não encontrada."
if [ -n "$CLIENTE" ]; then
    em() { nft get element inet gwos "$1" "{ $CLIENTE }" >/dev/null 2>&1; }
    if ! nft list set inet gwos ip_acesso_livre >/dev/null 2>&1; then
        inf "Firewall sem os sets de login (regras antigas): rode 'gwos reload nftables'."
    elif em ip_bloqueados; then
        bad "$CLIENTE está em BLOQUEADOS: pinga o servidor (ICMP é aceito antes) mas NÃO sai para a internet. Mude o grupo em Equipamentos/Políticas."
    elif em ip_liberados; then
        okk "$CLIENTE = LIBERADO: sai direto, SEM passar pelo proxy (não aparece nos acessos)."
    elif em ip_acesso_livre; then
        okk "$CLIENTE = ISENTO/PARCIAL: passa pelo proxy, sem senha (aparece nos acessos)."
    elif em ip_autenticados; then
        okk "$CLIENTE = SEM GRUPO, COM LOGIN ativo: navega pelo proxy enquanto houver navegação."
    else
        inf "$CLIENTE = SEM GRUPO e sem login: HTTP vai para a tela de login; o resto fica bloqueado até entrar em https://${IP_GATEWAY:-<gateway>}:${ACESSO_PORTA:-8444}/acesso"
    fi
    ip neigh show "$CLIENTE" 2>/dev/null | grep -q lladdr && okk "Cliente visto na LAN: $(ip neigh show "$CLIENTE" | head -1)" || inf "Cliente $CLIENTE ainda não aparece na tabela ARP (ping nele primeiro)."
else
    inf "Informe o IP de um cliente para ver em qual regra ele cai: gwos rede 192.168.x.y"
fi

sec "DNS (BIND) e Squid"
systemctl is-active --quiet named && okk "named ativo." || inf "named inativo (se o módulo 20 não foi instalado, ok)."
if systemctl is-active --quiet named; then
    dig +short +time=3 +tries=1 google.com @127.0.0.1 2>/dev/null | grep -q . && okk "BIND responde em 127.0.0.1." || bad "BIND ativo mas NÃO resolve: o Squid (que usa 127.0.0.1) e os clientes ficam sem DNS. Veja forwarders: journalctl -u named -n 30"
fi
systemctl is-active --quiet squid && okk "squid ativo." || bad "squid inativo: tail -20 /var/log/squid/cache.log"
for p in ${SQUID_PORTA_FWD:-3127} ${SQUID_PORTA:-3128} ${SQUID_PORTA_SSL:-3129}; do
    ss -ltn 2>/dev/null | grep -q ":${p}\b" && okk "Porta ${p} escutando." || inf "Porta ${p} não está escutando."
done
inf "Proxy MANUAL no cliente: ${IP_GATEWAY:-<IP do gateway>} porta ${SQUID_PORTA_FWD:-3127} (HTTP e HTTPS). A ${SQUID_PORTA:-3128} é interceptada: não aceita proxy manual."
if [ -f /etc/squid/conf.d/gwos_integracao.conf ]; then inf "$(grep dns_nameservers /etc/squid/conf.d/gwos_integracao.conf)"; fi

echo ""
[ "$P" -eq 0 ] && okk "Nada de errado encontrado no servidor." || bad "$P problema(s) acima."
exit 0
