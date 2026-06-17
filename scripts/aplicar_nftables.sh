#!/bin/bash
# Regenera e aplica as regras nftables + arquivos de IPs do Squid.
# Executado pelo painel via sudo — não editar manualmente.

set -euo pipefail

GWOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$GWOS_DIR/.env" ]; then set -a; source "$GWOS_DIR/.env"; set +a; fi

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_BANCO="${DB_BANCO:-gwos}"
DB_USUARIO="${DB_USUARIO:-gwos}"
DB_SENHA="${DB_SENHA:-}"

SQUID_DIR="/etc/squid/conf.d"
mkdir -p "$SQUID_DIR"

mysql_q() {
    mysql -h"$DB_HOST" -u"$DB_USUARIO" -p"$DB_SENHA" "$DB_BANCO" \
        --batch --skip-column-names -e "$1"
}

# ------------------------------------------------------------------
# Lê configurações
# ------------------------------------------------------------------
IFACE_WAN=$(mysql_q "SELECT valor FROM configuracoes WHERE chave='iface_wan'")
IFACE_LAN=$(mysql_q "SELECT valor FROM configuracoes WHERE chave='iface_lan'")
NAT_ATIVO=$(mysql_q "SELECT valor FROM configuracoes WHERE chave='nat_ativo'")
SQUID_PORTA=$(mysql_q  "SELECT valor FROM configuracoes WHERE chave='squid_porta'")
SQUID_PORTA="${SQUID_PORTA:-3128}"
SQUID_PORTA_SSL=3129   # porta ssl-bump (fixa)

# ------------------------------------------------------------------
# Gera listas de IPs por tipo
# ------------------------------------------------------------------
IPS_BLOQUEADOS=$(mysql_q \
    "SELECT i.endereco FROM ips i JOIN ip_grupos g ON g.id = i.grupo_id
     WHERE g.tipo='bloqueado' AND i.ativo=1 AND g.ativo=1")

IPS_PARCIAIS=$(mysql_q \
    "SELECT i.endereco FROM ips i JOIN ip_grupos g ON g.id = i.grupo_id
     WHERE g.tipo='parcial' AND i.ativo=1 AND g.ativo=1")

IPS_LIBERADOS=$(mysql_q \
    "SELECT i.endereco FROM ips i JOIN ip_grupos g ON g.id = i.grupo_id
     WHERE g.tipo='liberado' AND i.ativo=1 AND g.ativo=1")

# Escreve arquivos para o Squid
echo "$IPS_BLOQUEADOS" > "$SQUID_DIR/gwos_ips_bloqueados.txt"
echo "$IPS_PARCIAIS"   > "$SQUID_DIR/gwos_ips_parciais.txt"
echo "$IPS_LIBERADOS"  > "$SQUID_DIR/gwos_ips_liberados.txt"

# ------------------------------------------------------------------
# Formata elementos para nft (separados por vírgula, ignora vazio)
# ------------------------------------------------------------------
fmt_nft() {
    echo "$1" | grep -v '^$' | paste -sd ',' - || true
}

ELEM_BLOQUEADOS=$(fmt_nft "$IPS_BLOQUEADOS")
ELEM_PARCIAIS=$(fmt_nft "$IPS_PARCIAIS")
ELEM_LIBERADOS=$(fmt_nft "$IPS_LIBERADOS")   # IPs que bypassam o proxy

# ------------------------------------------------------------------
# Regras 1:1 NAT
# ------------------------------------------------------------------
NAT_DNAT=""
NAT_SNAT=""
TCP_OUTGOING="# GWOS — tcp_outgoing_address gerado automaticamente"$'\n'
while IFS=$'\t' read -r ip_externo ip_interno; do
    [ -z "$ip_externo" ] || [ -z "$ip_interno" ] && continue
    NAT_DNAT+="        iif \"$IFACE_WAN\" ip daddr $ip_externo dnat to $ip_interno"$'\n'
    NAT_SNAT+="        oif \"$IFACE_WAN\" ip saddr $ip_interno snat to $ip_externo"$'\n'
    ACL_NOME="nat1to1_$(echo "$ip_interno" | tr '.' '_')"
    TCP_OUTGOING+="acl ${ACL_NOME} src ${ip_interno}"$'\n'
    TCP_OUTGOING+="tcp_outgoing_address ${ip_interno} ${ACL_NOME}"$'\n'
done < <(mysql_q "SELECT ip_externo, ip_interno FROM nat_um_para_um WHERE ativo=1" 2>/dev/null || true)
echo "$TCP_OUTGOING" > "$SQUID_DIR/gwos_tcp_outgoing.conf"

if [ "$NAT_ATIVO" = "1" ]; then
    MASQ="        oif \"$IFACE_WAN\" masquerade"
else
    MASQ="        # masquerade desativado"
fi

# ------------------------------------------------------------------
# Elementos dos sets (evita bloco vazio que pode falhar no nft)
# ------------------------------------------------------------------
elem_set() { [ -n "$1" ] && echo "elements = { $1 }" || true; }

# ------------------------------------------------------------------
# Gera arquivo nftables
# ------------------------------------------------------------------
cat > /tmp/gwos_nftables_test.conf << NFTEOF
#!/usr/sbin/nft -f

flush ruleset

# ═══════════════════════════════════════════════════════════════
# NAT — tabela IPv4
# ═══════════════════════════════════════════════════════════════
table ip gwos_nat {

    # IPs que bypassam o proxy transparente (grupo "liberado")
    set ip_bypass_proxy {
        type ipv4_addr
        flags interval
        auto-merge
        $(elem_set "$ELEM_LIBERADOS")
    }

    chain prerouting {
        type nat hook prerouting priority dstnat;

        # 1:1 NAT — DNAT: IP público → IP interno
${NAT_DNAT}
        # Força DNS da LAN pelo BIND9 local (impede bypass de RPZ)
        iif "$IFACE_LAN" udp dport 53 redirect
        iif "$IFACE_LAN" tcp dport 53 redirect

        # Tráfego LAN→LAN (inclui o gateway): não intercepta
        iif "$IFACE_LAN" ip daddr $(mysql_q "SELECT valor FROM configuracoes WHERE chave='rede_lan'" 2>/dev/null || echo "192.168.0.0/24") return

        # Proxy transparente — apenas tráfego saindo para internet
        iif "$IFACE_LAN" ip saddr != @ip_bypass_proxy tcp dport 80 redirect to :${SQUID_PORTA}
        iif "$IFACE_LAN" ip saddr != @ip_bypass_proxy tcp dport 443 redirect to :${SQUID_PORTA_SSL}
    }

    chain postrouting {
        type nat hook postrouting priority srcnat;

        # 1:1 NAT — SNAT: IP interno → IP público fixo
${NAT_SNAT}
        # Masquerade para IPs sem 1:1 NAT
$MASQ
    }
}

# ═══════════════════════════════════════════════════════════════
# FILTRO — tabela inet (IPv4 + IPv6)
# ═══════════════════════════════════════════════════════════════
table inet gwos {

    set ip_bloqueados {
        type ipv4_addr
        flags interval
        auto-merge
        $(elem_set "$ELEM_BLOQUEADOS")
    }

    set ip_parciais {
        type ipv4_addr
        flags interval
        auto-merge
        $(elem_set "$ELEM_PARCIAIS")
    }

    # ─── INPUT ───────────────────────────────────────────────────
    chain input {
        type filter hook input priority filter; policy drop;

        ct state { established, related } accept
        ct state invalid drop
        iif lo accept

        # ICMP da LAN livre
        iif "$IFACE_LAN" ip protocol icmp accept

        # Bloqueia IPs banidos
        iif "$IFACE_LAN" ip saddr @ip_bloqueados drop

        # Aceita todo tráfego da LAN destinado ao gateway
        # (Squid 3128/3129, BIND9 53, SSH, NTP, etc.)
        iif "$IFACE_LAN" accept

        # ICMP de resposta da WAN
        iif "$IFACE_WAN" icmp type { echo-reply, destination-unreachable, time-exceeded, parameter-problem } accept

        # SSH da WAN
        iif "$IFACE_WAN" ct state new tcp dport 22 accept comment "SSH"

        # Descarta novas conexões da WAN não explicitadas
        iif "$IFACE_WAN" ct state new drop
    }

    # ─── FORWARD ─────────────────────────────────────────────────
    chain forward {
        type filter hook forward priority filter; policy drop;

        ct state { established, related } accept
        ct state invalid drop

        # Bloqueia IPs banidos em qualquer direção
        iif "$IFACE_LAN" ip saddr @ip_bloqueados drop

        # ICMP livre (ping/traceroute)
        ip protocol icmp accept

        # LAN ↔ LAN (hosts em sub-redes diferentes na mesma interface)
        iif "$IFACE_LAN" oif "$IFACE_LAN" accept

        # WAN → LAN livre (hosts externos acessam a rede interna)
        iif "$IFACE_WAN" oif "$IFACE_LAN" accept

        # LAN → WAN: IPs liberados passam direto (sem proxy)
        # HTTP/HTTPS dos demais já foram redirecionados ao Squid no prerouting
        iif "$IFACE_LAN" oif "$IFACE_WAN" accept
    }
}
NFTEOF

# ------------------------------------------------------------------
# Valida antes de aplicar
# ------------------------------------------------------------------
nft -c -f /tmp/gwos_nftables_test.conf || {
    echo "ERRO: regras inválidas — nftables não alterado."
    rm -f /tmp/gwos_nftables_test.conf
    exit 1
}

cp /tmp/gwos_nftables_test.conf /etc/nftables.conf
nft -f /etc/nftables.conf

mysql -h"$DB_HOST" -u"$DB_USUARIO" -p"$DB_SENHA" "$DB_BANCO" \
    -e "INSERT INTO regras_historico (modulo, descricao) VALUES ('nftables', 'Regras aplicadas via painel')" \
    2>/dev/null || true

rm -f /tmp/gwos_nftables_test.conf

# Recarrega Squid para aplicar novos arquivos de ACL
squid -k reconfigure 2>/dev/null || true

echo "nftables e arquivos Squid aplicados com sucesso."
