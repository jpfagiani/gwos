#!/bin/bash
# Corrige nftables: exclui o IP do gateway da intercepção de porta 80/443.
# Necessário quando o painel GWOS retorna ERR_CONNECTION_REFUSED após instalação.

set -euo pipefail

GWOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$GWOS_DIR/.env" ]; then set -a; source "$GWOS_DIR/.env"; set +a; fi

[ "$(id -u)" -eq 0 ] || { echo "Execute como root: sudo bash $0"; exit 1; }

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_BANCO="${DB_BANCO:-gwos}"
DB_USUARIO="${DB_USUARIO:-gwos}"
DB_SENHA="${DB_SENHA:-}"

mysql_q() {
    mysql -h"$DB_HOST" -u"$DB_USUARIO" -p"$DB_SENHA" "$DB_BANCO" \
        --batch --skip-column-names -e "$1" 2>/dev/null
}

IFACE_WAN=$(mysql_q "SELECT valor FROM configuracoes WHERE chave='iface_wan'")
IFACE_LAN=$(mysql_q "SELECT valor FROM configuracoes WHERE chave='iface_lan'")
IP_GATEWAY=$(mysql_q "SELECT valor FROM configuracoes WHERE chave='ip_gateway'")
NAT_ATIVO=$(mysql_q "SELECT valor FROM configuracoes WHERE chave='nat_ativo'")

echo "[..] Interfaces: WAN=$IFACE_WAN  LAN=$IFACE_LAN  Gateway=$IP_GATEWAY"

if [ -z "$IP_GATEWAY" ]; then
    # Tenta detectar da interface LAN
    IP_GATEWAY=$(ip -4 addr show "$IFACE_LAN" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
    [ -z "$IP_GATEWAY" ] && { echo "[ERRO] Não foi possível detectar IP do gateway."; exit 1; }
    echo "[!] ip_gateway não está no banco — usando detectado: $IP_GATEWAY"
    mysql_q "INSERT INTO configuracoes (chave, valor, descricao)
             VALUES ('ip_gateway', '$IP_GATEWAY', 'IP do gateway na LAN')
             ON DUPLICATE KEY UPDATE valor='$IP_GATEWAY'"
fi

[ "$NAT_ATIVO" = "1" ] && MASQ="oif \"$IFACE_WAN\" masquerade" || MASQ="# masquerade desativado"

cat > /tmp/gwos_fix_nft.conf << NFTEOF
#!/usr/sbin/nft -f

flush ruleset

table ip gwos_nat {

    set ip_bypass_proxy {
        type ipv4_addr
        flags interval
        auto-merge
    }

    chain prerouting {
        type nat hook prerouting priority dstnat;

        # Força DNS pelo BIND9 local
        iif "$IFACE_LAN" udp dport 53 redirect
        iif "$IFACE_LAN" tcp dport 53 redirect

        # Proxy transparente — exclui o gateway (painel GWOS)
        iif "$IFACE_LAN" ip saddr != @ip_bypass_proxy ip daddr != $IP_GATEWAY tcp dport 80 redirect to :3128
        iif "$IFACE_LAN" ip saddr != @ip_bypass_proxy ip daddr != $IP_GATEWAY tcp dport 443 redirect to :3129
    }

    chain postrouting {
        type nat hook postrouting priority srcnat;
        $MASQ
    }
}

table inet gwos {

    set ip_bloqueados {
        type ipv4_addr
        flags interval
        auto-merge
    }

    chain input {
        type filter hook input priority filter; policy drop;
        ct state { established, related } accept
        ct state invalid drop
        iif lo accept
        iif "$IFACE_LAN" ip protocol icmp accept
        iif "$IFACE_LAN" ip saddr @ip_bloqueados drop
        iif "$IFACE_LAN" accept
        iif "$IFACE_WAN" icmp type { echo-reply, destination-unreachable, time-exceeded, parameter-problem } accept
        iif "$IFACE_WAN" ct state new tcp dport 22 accept
        iif "$IFACE_WAN" ct state new drop
    }

    chain forward {
        type filter hook forward priority filter; policy drop;
        ct state { established, related } accept
        ct state invalid drop
        iif "$IFACE_LAN" ip saddr @ip_bloqueados drop
        ip protocol icmp accept
        iif "$IFACE_LAN" oif "$IFACE_LAN" accept
        iif "$IFACE_WAN" oif "$IFACE_LAN" accept
        iif "$IFACE_LAN" oif "$IFACE_WAN" accept
    }
}
NFTEOF

nft -c -f /tmp/gwos_fix_nft.conf || { echo "[ERRO] Regras inválidas."; exit 1; }
cp /tmp/gwos_fix_nft.conf /etc/nftables.conf
nft -f /etc/nftables.conf
rm -f /tmp/gwos_fix_nft.conf

echo "[OK] nftables corrigido. Painel acessível em http://$IP_GATEWAY"
