#!/bin/bash
# GWOS — Módulo 20-dns-bind9: desinstalação

set -euo pipefail

MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _l in "${MOD_DIR}/../comum/lib.sh" "/etc/gwos/lib.sh"; do
    # shellcheck disable=SC1090
    [ -f "$_l" ] && { . "$_l"; break; }
done
[ -n "${GWOS_LIB_CARREGADA:-}" ] || { echo "ERRO: comum/lib.sh não encontrado."; exit 1; }

exigir_root
carregar_conf
titulo "══ Removendo o módulo 20-dns-bind9 ══"

aviso "A LAN perde o resolver e o bloqueio de domínios por DNS."
confirmar_uma_vez "Continuar?" || { echo "Cancelado."; exit 0; }

svc_parar named
# named.conf do Debian inclui estes dois arquivos mesmo após remover o módulo.
# Restaura os originais quando disponíveis e repõe uma base neutra em
# instalações legadas que só tenham a configuração gerada pelo GWOS.
if [ -f /etc/bind/named.conf ]; then
    for arq in named.conf.options named.conf.local; do
        destino="/etc/bind/$arq"
        original="/etc/gwos/bind-originais/$arq"
        if [ -f "$destino" ] && ! grep -q 'GWOS .* BIND9' "$destino"; then
            continue
        fi
        if [ -f "$original" ]; then
            install -o root -g root -m 0644 "$original" "$destino"
        elif [ "$arq" = "named.conf.options" ]; then
            cat > "$destino" <<'OPCOES'
options {
    directory "/var/cache/bind";
    listen-on { 127.0.0.1; };
    listen-on-v6 { ::1; };
    recursion no;
};
OPCOES
        else
            printf '%s\n' '// Zonas locais do BIND9.' > "$destino"
        fi
    done
fi
rm -f /etc/bind/db.rpz.gwos \
      /etc/bind/named.conf.gwos-integracao \
      /etc/bind/named.conf.gwos-forwarders
rm -rf /var/log/named
ok "Configurações do GWOS removidas do BIND9."

# Zonas escritas à mão não são nossas para apagar
if [ -f /etc/bind/named.conf.zonas-locais ]; then
    aviso "Mantido: /etc/bind/named.conf.zonas-locais (suas zonas)."
fi

remover_pacotes bind9 bind9-utils

# Devolve o gateway a um resolver externo, senão a máquina fica sem DNS
if grep -q '^nameserver 127.0.0.1' /etc/resolv.conf 2>/dev/null; then
    { echo "# Restaurado ao remover o módulo 20-dns-bind9"
      echo "nameserver 8.8.8.8"
      echo "nameserver 1.1.1.1"
    } > /etc/resolv.conf
    ok "/etc/resolv.conf apontado para resolvers externos."
fi

desregistrar_modulo dns-bind9
integrar --silencioso
ok "Módulo 20-dns-bind9 removido."
