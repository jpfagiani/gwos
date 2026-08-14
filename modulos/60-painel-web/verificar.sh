#!/bin/bash
# GWOS — Módulo 60-painel-web: verificação

set -uo pipefail

MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _l in "${MOD_DIR}/../comum/lib.sh" "/etc/gwos/lib.sh"; do
    # shellcheck disable=SC1090
    [ -f "$_l" ] && { . "$_l"; break; }
done
[ -n "${GWOS_LIB_CARREGADA:-}" ] || { echo "ERRO: comum/lib.sh não encontrado."; exit 1; }

carregar_conf
FALHAS=0
titulo "── Verificação: 60-painel-web ──"

PHP_VER="$(detectar_php_instalado || echo '')"
[ -n "$PHP_VER" ] && ok "PHP instalado: ${PHP_VER}" || falha "Nenhum PHP-FPM encontrado em /etc/php."

for SVC in nginx ${PHP_VER:+php${PHP_VER}-fpm}; do
    if svc_ativo "$SVC"; then ok "Serviço ${SVC} ativo."
    else falha "Serviço ${SVC} parado."; FALHAS=$((FALHAS+1)); fi
done

if nginx -t >/dev/null 2>&1; then ok "nginx -t sem erros."
else falha "nginx -t com erros:"; nginx -t 2>&1 | tail -3; FALHAS=$((FALHAS+1)); fi

REPO="$(raiz_projeto || true)"
if [ -n "$REPO" ]; then
    ok "Projeto em ${REPO}"
    if [ -f "${REPO}/.env" ]; then
        ok ".env presente."
        [ "$(stat -c '%a' "${REPO}/.env")" = "600" ] \
            && ok "Permissões do .env corretas (600)." \
            || { falha ".env com permissão $(stat -c '%a' "${REPO}/.env") — deveria ser 600."; FALHAS=$((FALHAS+1)); }
    else
        falha ".env ausente — o painel não conecta no banco."; FALHAS=$((FALHAS+1))
    fi
else
    falha "Repositório do projeto não encontrado."; FALHAS=$((FALHAS+1))
fi

if [ -f /etc/sudoers.d/gwos ] && visudo -c -f /etc/sudoers.d/gwos >/dev/null 2>&1; then
    ok "sudoers do GWOS válido."
else
    falha "sudoers ausente ou inválido — o painel não consegue aplicar regras."
    FALHAS=$((FALHAS+1))
fi

[ -x /usr/local/bin/gwos ] && ok "Comando 'gwos' instalado." \
    || { falha "Comando 'gwos' ausente."; FALHAS=$((FALHAS+1)); }

[ -f /etc/cron.d/gwos ] && ok "Tarefas de cron instaladas." \
    || { falha "/etc/cron.d/gwos ausente — sem backup nem parser de logs."; FALHAS=$((FALHAS+1)); }

if id -nG www-data 2>/dev/null | grep -qw proxy; then
    ok "www-data no grupo proxy (lê o log do Squid)."
else
    tem_squid && { falha "www-data fora do grupo proxy — dashboard sem dados de acesso."; FALHAS=$((FALHAS+1)); }
fi

if command -v curl >/dev/null 2>&1; then
    COD=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1/" 2>/dev/null)
    case "$COD" in
        200|302|301) ok "Painel respondendo (HTTP ${COD})." ;;
        *) falha "Painel não respondeu como esperado (HTTP ${COD:-sem resposta})."; FALHAS=$((FALHAS+1)) ;;
    esac
fi

tem_banco || { falha "Módulo 10-banco-mariadb ausente — o painel não tem de onde ler."; FALHAS=$((FALHAS+1)); }

echo ""
[ "$FALHAS" -eq 0 ] && ok "60-painel-web OK." || falha "60-painel-web com ${FALHAS} problema(s)."
exit $(( FALHAS > 0 ? 1 : 0 ))
