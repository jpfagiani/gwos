#!/bin/bash
# GWOS — Módulo 40-firewall-nftables: desinstalação

set -euo pipefail

MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _l in "${MOD_DIR}/../comum/lib.sh" "/etc/gwos/lib.sh"; do
    # shellcheck disable=SC1090
    [ -f "$_l" ] && { . "$_l"; break; }
done
[ -n "${GWOS_LIB_CARREGADA:-}" ] || { echo "ERRO: comum/lib.sh não encontrado."; exit 1; }

exigir_root
titulo "══ Removendo o módulo 40-firewall-nftables ══"

aviso "O gateway deixa de mascarar (NAT) e de filtrar — a LAN perde a internet"
aviso "As regras de outros serviços serão preservadas."
confirmar_uma_vez "Continuar?" || { echo "Cancelado."; exit 0; }

# Uma transação remove somente as tabelas GWOS, mesmo se já estiverem ausentes.
nft -f - <<'NFT'
add table ip gwos_nat
delete table ip gwos_nat
add table inet gwos
delete table inet gwos
NFT

# Remova apenas a configuração gerada pelo GWOS (inclui versões antigas).
if [ -f /etc/nftables.conf ] &&
   grep -Fxq 'add table ip gwos_nat' /etc/nftables.conf &&
   grep -Fxq 'add table inet gwos' /etc/nftables.conf; then
    if ! awk '$1 == "include" || (($1 == "table" || $2 == "table") && $0 !~ /^[[:space:]]*((add|delete)[[:space:]]+)?table[[:space:]]+(ip[[:space:]]+gwos_nat|inet[[:space:]]+gwos)([[:space:]{]|$)/) { externo = 1 } END { exit !externo }' /etc/nftables.conf; then
        printf '%s\n' '#!/usr/sbin/nft -f' '# Sem regras persistentes do GWOS.' > /etc/nftables.conf
    else
        aviso "Configuração compartilhada em /etc/nftables.conf preservada. Remova as declarações persistentes das tabelas GWOS antes de recarregar o serviço."
    fi
fi
rm -f /etc/sysctl.d/91-gwos-firewall.conf
rm -f /usr/local/sbin/gwos-gerar-nftables
ok "Regras e gerador removidos."

desregistrar_modulo firewall-nftables
integrar --silencioso
ok "Módulo 40-firewall-nftables removido."
