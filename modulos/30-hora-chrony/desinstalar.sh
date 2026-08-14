#!/bin/bash
# GWOS — Módulo 30-hora-chrony: desinstalação

set -euo pipefail

MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _l in "${MOD_DIR}/../comum/lib.sh" "/etc/gwos/lib.sh"; do
    # shellcheck disable=SC1090
    [ -f "$_l" ] && { . "$_l"; break; }
done
[ -n "${GWOS_LIB_CARREGADA:-}" ] || { echo "ERRO: comum/lib.sh não encontrado."; exit 1; }

exigir_root
titulo "══ Removendo o módulo 30-hora-chrony ══"

aviso "A LAN perde o servidor de hora deste gateway."
confirmar "Continuar?" || { echo "Cancelado."; exit 0; }

rm -f /etc/chrony/conf.d/gwos.conf
desregistrar_modulo hora-chrony

if confirmar "Remover também o pacote chrony?"; then
    svc_parar chrony
    DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y -qq chrony 2>/dev/null || true
    apt-get autoremove -y -qq 2>/dev/null || true
    systemctl enable --now systemd-timesyncd 2>/dev/null || true
    ok "chrony removido; systemd-timesyncd reativado para o relógio local."
else
    systemctl restart chrony 2>/dev/null || true
    aviso "chrony mantido, mas sem as configurações do GWOS."
fi

integrar --silencioso
ok "Módulo 30-hora-chrony removido."
