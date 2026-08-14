#!/bin/bash
# ============================================================================
# GWOS — Módulo 60-painel-web: painel de administração
# ============================================================================
# Instala o Nginx + PHP-FPM 8.4, publica o painel, cria o comando 'gwos', as
# permissões sudo dos scripts e as tarefas de cron.
#
# Depende do módulo 10-banco-mariadb (é dele que o painel lê tudo).
# Junto:   é por aqui que grupos, IPs, domínios, horários e NAT são editados;
#          ao salvar, o painel chama os scripts que regeram Squid, BIND9 e
#          nftables dos outros módulos.
#
# Este módulo precisa do repositório GWOS completo (app/, public/, scripts/).
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

iniciar_modulo "60-painel-web"

REPO="$(raiz_projeto)" || erro "Repositório GWOS não encontrado — este módulo precisa de app/, public/ e scripts/."
info "Projeto: ${REPO}"

tem_banco || erro "Instale antes o módulo 10-banco-mariadb (o painel não funciona sem banco)."
[ -f "$GWOS_DB_CONF" ] || erro "Credenciais do banco ausentes (${GWOS_DB_CONF}) — reexecute o módulo 10."
# shellcheck disable=SC1090
. "$GWOS_DB_CONF"

# ---------------------------------------------------------------------------
# Repositório do PHP 8.4 (não existe nos repos padrão do Debian 13)
# ---------------------------------------------------------------------------
if ! apt-cache show php8.4 &>/dev/null; then
    info "Adicionando o repositório PHP 8.4 (sury.org)..."
    instalar_pacotes curl gnupg2 lsb-release ca-certificates apt-transport-https
    curl -fsSL https://packages.sury.org/php/apt.gpg \
        | gpg --dearmor -o /etc/apt/trusted.gpg.d/php-sury.gpg
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" \
        > /etc/apt/sources.list.d/php-sury.list
    apt-get update -qq
    ok "Repositório PHP 8.4 adicionado."
fi

instalar_pacotes nginx \
    php8.4 php8.4-fpm php8.4-mysql php8.4-mbstring \
    php8.4-curl php8.4-zip php8.4-xml php8.4-intl \
    tar gzip unzip

# ---------------------------------------------------------------------------
# PHP-FPM
# ---------------------------------------------------------------------------
PHP_INI="/etc/php/8.4/fpm/php.ini"
sed -i "s|;date.timezone.*|date.timezone = America/Sao_Paulo|" "$PHP_INI"
sed -i "s|upload_max_filesize.*|upload_max_filesize = 64M|"    "$PHP_INI"
sed -i "s|post_max_size.*|post_max_size = 64M|"                "$PHP_INI"
svc_ativar php8.4-fpm
ok "PHP-FPM configurado."

# ---------------------------------------------------------------------------
# Nginx
# ---------------------------------------------------------------------------
cat > /etc/nginx/sites-available/gwos <<NGINX
server {
    listen 80 default_server;
    server_name _;
    root ${REPO}/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\. { deny all; }
    location = /favicon.ico { log_not_found off; }
}
NGINX

ln -sf /etc/nginx/sites-available/gwos /etc/nginx/sites-enabled/gwos
rm -f /etc/nginx/sites-enabled/default
nginx -t || erro "nginx -t reprovou a configuração."
svc_ativar nginx
systemctl reload nginx
ok "Nginx configurado."

# ---------------------------------------------------------------------------
# .env
# ---------------------------------------------------------------------------
cat > "${REPO}/.env" <<ENV
APP_URL=http://${IP_GATEWAY}
APP_DEBUG=false
DB_HOST=${DB_HOST}
DB_BANCO=${DB_BANCO}
DB_USUARIO=${DB_USUARIO}
DB_SENHA=${DB_SENHA}
ENV
chmod 600 "${REPO}/.env"
chown www-data:www-data "${REPO}/.env"
ok ".env do painel criado."

# ---------------------------------------------------------------------------
# Sudo — o painel roda como www-data e precisa aplicar as regras
# ---------------------------------------------------------------------------
grep -q '@includedir /etc/sudoers.d' /etc/sudoers || echo '@includedir /etc/sudoers.d' >> /etc/sudoers

{
    echo "Defaults:www-data !requiretty"
    for s in aplicar_nftables aplicar_nat aplicar_bind9_rpz gerar_squid_dominios \
             gerar_squid_acl backup restaurar_backup importar_log_squid aplicar_dns_hosts; do
        [ -f "${REPO}/scripts/${s}.sh" ] && \
            echo "www-data ALL=(root) NOPASSWD: ${REPO}/scripts/${s}.sh"
    done
    echo "www-data ALL=(root) NOPASSWD: /usr/local/sbin/gwos-gerar-nftables"
    echo "www-data ALL=(root) NOPASSWD: /usr/local/sbin/gwos-integrar"
} > /etc/sudoers.d/gwos
chmod 440 /etc/sudoers.d/gwos
visudo -c -f /etc/sudoers.d/gwos >/dev/null || {
    rm -f /etc/sudoers.d/gwos
    erro "sudoers gerado é inválido — arquivo removido para não travar o sudo."
}
ok "Permissões sudo configuradas."

chmod +x "${REPO}/scripts/"*.sh

# ---------------------------------------------------------------------------
# Comando 'gwos'
# ---------------------------------------------------------------------------
ln -sf "${REPO}/scripts/gwos-cli.sh" /usr/local/bin/gwos
chmod +x /usr/local/bin/gwos
ok "Comando 'gwos' disponível no terminal."

# ---------------------------------------------------------------------------
# Cron
# ---------------------------------------------------------------------------
cat > /etc/cron.d/gwos <<CRON
# GWOS — tarefas automáticas (módulo 60-painel-web)
0 2 * * * root /bin/bash ${REPO}/scripts/backup.sh >> /var/log/gwos_backup.log 2>&1
*/5 * * * * root /usr/bin/php ${REPO}/scripts/parsear_logs.php >> /var/log/gwos_parser.log 2>&1
0 * * * * root /bin/bash ${REPO}/scripts/importar_log_squid.sh >> /var/log/gwos_import_log.log 2>&1
CRON
chmod 644 /etc/cron.d/gwos
ok "Tarefas de cron instaladas."

# ---------------------------------------------------------------------------
# Diretórios e permissões
# ---------------------------------------------------------------------------
mkdir -p /var/lib/gwos/backups "${REPO}/storage"
chown -R www-data:www-data /var/lib/gwos "${REPO}/public" "${REPO}/storage"
usermod -aG proxy www-data 2>/dev/null || true   # leitura do access.log do Squid
ok "Diretórios e permissões ajustados."

# ---------------------------------------------------------------------------
# Senha padrão do painel (só se ainda for o hash de exemplo do schema)
# ---------------------------------------------------------------------------
if [ -x /usr/local/sbin/gwos-senha-padrao ]; then
    /usr/local/sbin/gwos-senha-padrao || aviso "Não foi possível definir a senha padrão."
fi

# Publica a CA do Squid, se existir
if tem_ssl_bump; then
    install -m 644 /etc/squid/ssl_cert/gwos-ca.crt "${REPO}/public/gwos-ca.crt"
    chown www-data:www-data "${REPO}/public/gwos-ca.crt"
    ok "CA do Squid publicada para download."
fi

registrar_modulo painel-web
integrar

echo ""
ok "Módulo 60-painel-web instalado."
echo -e "  URL          : ${BOLD}http://${IP_GATEWAY}${NC}"
echo -e "  Login        : ${BOLD}admin@gwos.local${NC}"
echo -e "  Senha padrão : ${BOLD}gwos@2025${NC}  ${YELLOW}(troque no primeiro acesso)${NC}"
echo ""
