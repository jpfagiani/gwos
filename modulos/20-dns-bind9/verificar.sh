#!/bin/bash
# GWOS — Módulo 20-dns-bind9: verificação

set -uo pipefail

MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _l in "${MOD_DIR}/../comum/lib.sh" "/etc/gwos/lib.sh"; do
    # shellcheck disable=SC1090
    [ -f "$_l" ] && { . "$_l"; break; }
done
[ -n "${GWOS_LIB_CARREGADA:-}" ] || { echo "ERRO: comum/lib.sh não encontrado."; exit 1; }

carregar_conf
FALHAS=0
titulo "── Verificação: 20-dns-bind9 ──"

if svc_ativo named; then ok "Serviço named ativo."
else falha "Serviço named parado."; FALHAS=$((FALHAS+1)); fi

if named-checkconf >/dev/null 2>&1; then ok "named-checkconf sem erros."
else falha "named-checkconf com erros:"; named-checkconf; FALHAS=$((FALHAS+1)); fi

if grep -q 'response-policy' /etc/bind/named.conf.options 2>/dev/null; then
    ok "RPZ ativa (response-policy presente)."
else
    falha "RPZ declarada mas NÃO ativada — bloqueio por DNS não funciona."; FALHAS=$((FALHAS+1))
fi

if command -v dig >/dev/null 2>&1; then
    if dig +short +time=3 +tries=1 google.com @127.0.0.1 2>/dev/null | grep -qE '^[0-9]'; then
        ok "Resolução externa OK (google.com via 127.0.0.1)."
    else
        falha "Não resolveu google.com — verifique forwarders e saída para a internet."
        FALHAS=$((FALHAS+1))
    fi

    if tem_dnsmasq; then
        if dig +short +time=3 +tries=1 "teste.${DOMINIO_LOCAL}" @127.0.0.1 >/dev/null 2>&1; then
            ok "Encaminhamento de ${DOMINIO_LOCAL} respondendo."
        else
            falha "Domínio interno ${DOMINIO_LOCAL} não respondeu."; FALHAS=$((FALHAS+1))
        fi
    else
        info "Módulo 25-dns-interno ausente — nomes internos não resolvem (esperado)."
    fi
else
    aviso "dig não instalado (pacote dnsutils) — testes de resolução pulados."
fi

BLOQ=$(grep -c 'IN CNAME \.' /etc/bind/db.rpz.gwos 2>/dev/null || echo 0)
info "Domínios na zona RPZ: $(( BLOQ / 2 ))"

echo ""
[ "$FALHAS" -eq 0 ] && ok "20-dns-bind9 OK." || falha "20-dns-bind9 com ${FALHAS} problema(s)."
exit $(( FALHAS > 0 ? 1 : 0 ))
