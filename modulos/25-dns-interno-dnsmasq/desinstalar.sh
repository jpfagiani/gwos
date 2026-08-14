#!/bin/bash
# GWOS — Módulo 25-dns-interno-dnsmasq: desinstalação

set -euo pipefail

MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _l in "${MOD_DIR}/../comum/lib.sh" "/etc/gwos/lib.sh"; do
    # shellcheck disable=SC1090
    [ -f "$_l" ] && { . "$_l"; break; }
done
[ -n "${GWOS_LIB_CARREGADA:-}" ] || { echo "ERRO: comum/lib.sh não encontrado."; exit 1; }

exigir_root
carregar_conf
titulo "══ Removendo o módulo 25-dns-interno-dnsmasq ══"

aviso "Os nomes internos (${DOMINIO_LOCAL:-domínio local}) deixam de resolver."
confirmar "Continuar?" || { echo "Cancelado."; exit 0; }

svc_parar gwos-dnsmasq
rm -f /etc/systemd/system/gwos-dnsmasq.service
rm -f /etc/dnsmasq.d/gwos.conf
rm -f /etc/gwos/modelos/dnsmasq-gwos.conf.modelo
rm -f /usr/local/sbin/gwos-gerar-dnsmasq
rmdir /etc/gwos/modelos 2>/dev/null || true
systemctl daemon-reload
ok "Serviço e configuração removidos."

if confirmar "Remover também o pacote dnsmasq?"; then
    DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y -qq dnsmasq 2>/dev/null || true
    apt-get autoremove -y -qq 2>/dev/null || true
    ok "dnsmasq removido."
fi

aviso "As entradas de nomes continuam em /etc/hosts — remova à mão se quiser."

desregistrar_modulo dns-interno
integrar --silencioso
ok "Módulo 25-dns-interno-dnsmasq removido."
