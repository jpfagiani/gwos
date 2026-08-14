#!/bin/bash
# GWOS — Módulo 10-banco-mariadb: desinstalação
# Remove o banco 'gwos' e, se pedido, o próprio MariaDB.

set -euo pipefail

MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _l in "${MOD_DIR}/../comum/lib.sh" "/etc/gwos/lib.sh"; do
    # shellcheck disable=SC1090
    [ -f "$_l" ] && { . "$_l"; break; }
done
[ -n "${GWOS_LIB_CARREGADA:-}" ] || { echo "ERRO: comum/lib.sh não encontrado."; exit 1; }

exigir_root
titulo "══ Removendo o módulo 10-banco-mariadb ══"

aviso "Isto APAGA o banco 'gwos' — grupos, IPs, domínios, horários, relatórios."
if [ -x /usr/local/sbin/gwos-backup ] || [ -f "$(raiz_projeto 2>/dev/null)/scripts/backup.sh" ]; then
    aviso "Faça um backup antes: gwos backup criar"
fi
confirmar "Continuar?" || { echo "Cancelado."; exit 0; }

mysql -e "DROP DATABASE IF EXISTS gwos;"       2>/dev/null || true
mysql -e "DROP USER IF EXISTS 'gwos'@'localhost';" 2>/dev/null || true
ok "Banco e usuário removidos."

rm -f "$GWOS_DB_CONF" /usr/local/sbin/gwos-senha-padrao

if confirmar "Remover também o pacote mariadb-server?"; then
    svc_parar mariadb
    DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y -qq mariadb-server 2>/dev/null || true
    apt-get autoremove -y -qq 2>/dev/null || true
    ok "MariaDB removido."
else
    aviso "MariaDB mantido (outros bancos podem estar em uso)."
fi

desregistrar_modulo banco-mariadb
integrar --silencioso
ok "Módulo 10-banco-mariadb removido."
