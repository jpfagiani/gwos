#!/bin/bash
# GWOS — espelha as sessões de login no firewall.
# Lê /var/lib/gwos/sessions/sessoes.txt (ip<TAB>expira_epoch<TAB>email) e troca o
# conteúdo do set "ip_autenticados" (nftables) numa única operação atômica.
# Instalado em /usr/local/sbin/gwos-sessoes-nft; o painel o chama via sudo.
set -uo pipefail
ARQ=/var/lib/gwos/sessions/sessoes.txt
exec 9>/run/gwos-nftables.lock || exit 1
flock -x 9 || exit 1
# Sem o firewall do GWOS carregado (ou sem o set), não há o que sincronizar.
nft list set inet gwos ip_autenticados >/dev/null 2>&1 || exit 0

agora=$(date +%s)
[ -e "$ARQ" ] || exit 0
ips=$(awk -F'\t' -v n="$agora" '$2+0>n && $1 ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/ {print $1}' "$ARQ"  | sort -u | paste -sd, -) || exit 1
{
    echo "flush set inet gwos ip_autenticados"
    [ -n "$ips" ] && echo "add element inet gwos ip_autenticados { $ips }"
} | nft -f - || exit 1
exit 0
