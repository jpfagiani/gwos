#!/bin/bash
# ============================================================================
# GWOS — Módulo 20-dns-bind9: servidor DNS da rede
# ============================================================================
# Instala o BIND9 como resolver recursivo da LAN, com:
#   - encaminhamento para resolvers públicos (8.8.8.8 / 1.1.1.1)
#   - RPZ ativa (bloqueio de domínios por DNS)
#   - forward zones para os DNS internos do governo
#
# Sozinho: DNS funcional para a LAN, com bloqueio por RPZ editável à mão em
#          /etc/bind/db.rpz.gwos.
# Junto:   a RPZ passa a ser gerada do banco (módulo 10) pelo painel (módulo
#          60); o domínio interno é encaminhado ao dnsmasq (módulo 25); o
#          firewall (módulo 40) força todo DNS da LAN a passar por aqui.
# ============================================================================

set -euo pipefail

MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _l in "${MOD_DIR}/../comum/lib.sh" "/etc/gwos/lib.sh"; do
    # shellcheck disable=SC1090
    [ -f "$_l" ] && { . "$_l"; break; }
done
[ -n "${GWOS_LIB_CARREGADA:-}" ] || {
    echo "ERRO: comum/lib.sh não encontrado. Copie a pasta 'comum/' junto com o módulo."
    exit 1; }

iniciar_modulo "20-dns-bind9"

instalar_pacotes bind9 bind9-utils dnsutils

# ---------------------------------------------------------------------------
# Configuração
# ---------------------------------------------------------------------------
for arq in named.conf.options named.conf.local; do
    backup_arquivo "/etc/bind/${arq}"
    install -m 644 -o root -g bind "${MOD_DIR}/config/${arq}" "/etc/bind/${arq}"
done

# A zona RPZ só é criada se ainda não existir — nunca sobrescreve os bloqueios
# já aplicados pelo painel.
if [ ! -f /etc/bind/db.rpz.gwos ]; then
    install -m 644 -o bind -g bind "${MOD_DIR}/config/db.rpz.gwos" /etc/bind/db.rpz.gwos
    ok "Zona RPZ inicial criada."
else
    chown bind:bind /etc/bind/db.rpz.gwos
    aviso "Zona RPZ existente preservada (/etc/bind/db.rpz.gwos)."
fi

# Arquivos de integração — 'gwos-integrar' os regrava logo abaixo, mas
# precisam existir e ser válidos antes do primeiro named-checkconf.
[ -f /etc/bind/named.conf.gwos-integracao ] || \
    echo "// Gerado por gwos-integrar." > /etc/bind/named.conf.gwos-integracao

{
    echo "// Gerado por gwos-integrar a partir de DNS_FORWARDERS em ${GWOS_CONF}."
    echo "forwarders {"
    for _dns in $DNS_FORWARDERS; do
        echo "    ${_dns};"
    done
    echo "};"
    echo "forward only;"
} > /etc/bind/named.conf.gwos-forwarders

chown bind:bind /etc/bind/named.conf.gwos-integracao /etc/bind/named.conf.gwos-forwarders
ok "Resolvers upstream: ${DNS_FORWARDERS}"

mkdir -p /var/log/named
chown bind:bind /var/log/named
chmod 755 /var/log/named
ok "Diretório de log criado."

# AppArmor do Debian já libera /var/log/named para o named; nada a fazer.

named-checkconf || erro "named-checkconf reprovou a configuração — nada foi iniciado."
ok "Configuração validada."

svc_ativar named
ok "BIND9 ativo na porta 53."

# ---------------------------------------------------------------------------
# O gateway passa a resolver por si mesmo
# ---------------------------------------------------------------------------
if [ ! -L /etc/resolv.conf ] && ! grep -q '^nameserver 127.0.0.1' /etc/resolv.conf 2>/dev/null; then
    backup_arquivo /etc/resolv.conf
    { echo "# Gerado pelo módulo 20-dns-bind9 do GWOS"
      echo "nameserver 127.0.0.1"
      echo "search ${DOMINIO_LOCAL}"
    } > /etc/resolv.conf
    ok "/etc/resolv.conf aponta para o BIND9 local."
else
    aviso "/etc/resolv.conf não alterado (link simbólico ou já configurado)."
fi

registrar_modulo dns-bind9
integrar --silencioso

echo ""
ok "Módulo 20-dns-bind9 instalado."
echo -e "  Teste: ${BOLD}dig google.com @${IP_GATEWAY}${NC}"
echo -e "  Nos clientes da LAN, aponte o DNS para ${BOLD}${IP_GATEWAY}${NC}."
tem_dnsmasq || echo -e "  ${YELLOW}Nomes internos (${DOMINIO_LOCAL}) exigem o módulo 25-dns-interno-dnsmasq.${NC}"
echo ""
