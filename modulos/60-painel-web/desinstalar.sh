#!/bin/bash
# GWOS — Módulo 60-painel-web: desinstalação

set -euo pipefail

MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _l in "${MOD_DIR}/../comum/lib.sh" "/etc/gwos/lib.sh"; do
    # shellcheck disable=SC1090
    [ -f "$_l" ] && { . "$_l"; break; }
done
[ -n "${GWOS_LIB_CARREGADA:-}" ] || { echo "ERRO: comum/lib.sh não encontrado."; exit 1; }

exigir_root
titulo "══ Removendo o módulo 60-painel-web ══"

aviso "O painel e o comando 'gwos' deixam de existir. O banco NÃO é apagado."
confirmar "Continuar?" || { echo "Cancelado."; exit 0; }

REPO="$(raiz_projeto || true)"

svc_parar nginx
svc_parar php8.4-fpm
rm -f /etc/nginx/sites-available/gwos /etc/nginx/sites-enabled/gwos
rm -f /etc/sudoers.d/gwos
rm -f /etc/cron.d/gwos
rm -f /usr/local/bin/gwos
ok "Nginx, sudoers, cron e comando 'gwos' removidos."

if [ -n "$REPO" ]; then
    rm -f "${REPO}/public/gwos-ca.crt"
    if confirmar "Remover o .env do projeto (${REPO}/.env)?"; then
        rm -f "${REPO}/.env"
        ok ".env removido."
    fi
fi

if confirmar "Remover também Nginx e PHP 8.4?"; then
    DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y -qq \
        nginx php8.4 php8.4-fpm php8.4-mysql php8.4-mbstring \
        php8.4-curl php8.4-zip php8.4-xml php8.4-intl 2>/dev/null || true
    apt-get autoremove -y -qq 2>/dev/null || true
    ok "Nginx e PHP removidos."
fi

if confirmar "Remover os backups em /var/lib/gwos?"; then
    rm -rf /var/lib/gwos
    ok "Backups removidos."
fi

desregistrar_modulo painel-web
integrar --silencioso
ok "Módulo 60-painel-web removido."
