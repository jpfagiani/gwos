#!/bin/bash
# GWOS — Gerencia entradas DNS na zona cdpni.local
# Chamado internamente pelo comando: gwos dns
# Não execute diretamente.

set -euo pipefail

ZONE_FILE="/etc/bind/db.cdpni.local"
ZONE_NAME="cdpni.local"

_serial_novo() {
    # Serial formato YYYYMMDDnn — incrementa se já usou o mesmo dia
    local hoje; hoje=$(date +%Y%m%d)
    local atual; atual=$(grep -oP '(?<=\()[\s\n]*\K[0-9]+' "$ZONE_FILE" | head -1 | tr -d ' ')
    if [[ "$atual" == "${hoje}"* ]]; then
        local seq=$(( ${atual: -2} + 1 ))
        printf "%s%02d" "$hoje" "$seq"
    else
        printf "%s01" "$hoje"
    fi
}

_reload_bind() {
    named-checkzone "$ZONE_NAME" "$ZONE_FILE" >/dev/null 2>&1 || {
        echo "ERRO: zona inválida após edição — verifique $ZONE_FILE" >&2
        exit 1
    }
    systemctl reload named
}

_atualiza_serial() {
    local serial; serial=$(_serial_novo)
    sed -i "s/[0-9]\{10\}[[:space:]]*; serial/${serial}  ; serial/" "$ZONE_FILE"
}

cmd_list() {
    echo ""
    echo "  Hosts em $ZONE_NAME:"
    echo "  ──────────────────────────────────────────"
    grep -P '^\w[\w-]*\s+IN\s+A\s+' "$ZONE_FILE" \
        | awk '{printf "  %-20s %s\n", $1, $4}' \
        || echo "  (nenhum host cadastrado)"
    echo ""
}

cmd_add() {
    local host="$1" ip="$2"
    if grep -qP "^${host}\s+IN\s+A\s+" "$ZONE_FILE"; then
        echo "AVISO: host '$host' já existe. Use 'gwos dns update' para alterar." >&2
        exit 1
    fi
    echo "${host}    IN A    ${ip}" >> "$ZONE_FILE"
    _atualiza_serial
    _reload_bind
    echo "OK: $host → $ip adicionado e BIND9 recarregado."
}

cmd_update() {
    local host="$1" ip_novo="$2"
    if ! grep -qP "^${host}\s+IN\s+A\s+" "$ZONE_FILE"; then
        echo "ERRO: host '$host' não encontrado. Use 'gwos dns add' para criar." >&2
        exit 1
    fi
    local ip_antigo; ip_antigo=$(grep -P "^${host}\s+IN\s+A\s+" "$ZONE_FILE" | awk '{print $4}')
    sed -i "s/^${host}\s\+IN\s\+A\s\+.*/${host}    IN A    ${ip_novo}/" "$ZONE_FILE"
    _atualiza_serial
    _reload_bind
    echo "OK: $host atualizado de $ip_antigo → $ip_novo. BIND9 recarregado."
    echo "    Clientes receberão o novo IP em até 60 segundos (TTL da zona)."
}

cmd_del() {
    local host="$1"
    if ! grep -qP "^${host}\s+IN\s+A\s+" "$ZONE_FILE"; then
        echo "ERRO: host '$host' não encontrado." >&2
        exit 1
    fi
    sed -i "/^${host}\s\+IN\s\+A\s\+/d" "$ZONE_FILE"
    _atualiza_serial
    _reload_bind
    echo "OK: $host removido e BIND9 recarregado."
}

SUBCMD="${1:-list}"; shift 2>/dev/null || true

case "$SUBCMD" in
    list|ls)       cmd_list ;;
    add)           [[ $# -ge 2 ]] || { echo "Uso: gwos dns add <host> <ip>"; exit 1; }
                   cmd_add "$1" "$2" ;;
    update|change) [[ $# -ge 2 ]] || { echo "Uso: gwos dns update <host> <novo-ip>"; exit 1; }
                   cmd_update "$1" "$2" ;;
    del|rm)        [[ $# -ge 1 ]] || { echo "Uso: gwos dns del <host>"; exit 1; }
                   cmd_del "$1" ;;
    *)             echo "Uso: gwos dns <list|add|update|del>"
                   exit 1 ;;
esac
