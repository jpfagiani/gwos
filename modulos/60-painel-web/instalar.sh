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

# O banco é opcional. Com ele, o painel mostra grupos, IPs, domínios, horários
# e relatórios. Sem ele, sobe em MODO LEVE: só as telas cujos dados vivem em
# arquivo (módulos, rede, DNS, hora, nomes). É o que permite ter painel num
# servidor que só roda DNS, sem subir um MariaDB para guardar uma senha.
MODO_LEVE=1
if tem_banco && [ -f "$GWOS_DB_CONF" ]; then
    MODO_LEVE=0
    # shellcheck disable=SC1090
    . "$GWOS_DB_CONF"
    ok "Módulo 10-banco-mariadb encontrado — painel completo."
else
    aviso "Sem o módulo 10-banco-mariadb — painel em modo leve."
    aviso "Grupos, domínios, horários e relatórios ficam indisponíveis."
fi

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
if [ "$MODO_LEVE" = "0" ]; then
    cat > "${REPO}/.env" <<ENV
APP_URL=http://${IP_GATEWAY}
APP_DEBUG=false
DB_HOST=${DB_HOST}
DB_BANCO=${DB_BANCO}
DB_USUARIO=${DB_USUARIO}
DB_SENHA=${DB_SENHA}
ENV
else
    cat > "${REPO}/.env" <<ENV
APP_URL=http://${IP_GATEWAY}
APP_DEBUG=false
# Modo leve — sem banco de dados. Os usuários do painel ficam em
# /etc/gwos/painel-usuarios.json. Instale o módulo 10-banco-mariadb e
# reexecute este módulo para ligar o painel completo.
ENV
fi
chmod 600 "${REPO}/.env"
chown www-data:www-data "${REPO}/.env"
ok ".env do painel criado."

# ---------------------------------------------------------------------------
# Usuários do painel em arquivo (só no modo leve)
# ---------------------------------------------------------------------------
if [ "$MODO_LEVE" = "1" ]; then
    ARQ_USUARIOS="/etc/gwos/painel-usuarios.json"
    if [ -f "$ARQ_USUARIOS" ]; then
        aviso "Usuários do painel preservados (${ARQ_USUARIOS})."
    else
        HASH=$(php -r 'echo password_hash("gwos@2025", PASSWORD_BCRYPT, ["cost" => 12]);')
        cat > "$ARQ_USUARIOS" <<USUARIOS
[
    {
        "id": 1,
        "nome": "Administrador",
        "email": "admin@gwos.local",
        "senha": "${HASH}",
        "perfil": "superadmin",
        "ativo": 1,
        "primeiro_login": 1,
        "tentativas": 0,
        "bloqueado_ate": null,
        "ultimo_login": null,
        "reset_token": null,
        "reset_expira": null
    }
]
USUARIOS
        ok "Usuário do painel criado em ${ARQ_USUARIOS}."
    fi
    # O painel precisa escrever aqui (tentativas, bloqueio, troca de senha)
    chown root:www-data "$ARQ_USUARIOS"
    chmod 660 "$ARQ_USUARIOS"
fi

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
    # Único caminho de escrita do painel no /etc/gwos/gwos.conf. A lista de
    # chaves e a validação dos valores ficam dentro do gwos-definir.
    echo "www-data ALL=(root) NOPASSWD: /usr/local/sbin/gwos-definir"
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
if [ "$MODO_LEVE" = "0" ] && [ -x /usr/local/sbin/gwos-senha-padrao ]; then
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
if [ "$MODO_LEVE" = "1" ]; then
    echo ""
    aviso "Modo leve: o painel mostra os módulos e o que vive em arquivo."
    echo  "      Para o painel completo: bash ../10-banco-mariadb/instalar.sh"
    echo  "      e depois reexecute este módulo."
fi
echo ""
echo -e "  Módulos instalados nesta máquina: ${BOLD}$(modulos_instalados | paste -sd ', ' -)${NC}"
echo -e "  A tela ${BOLD}Módulos${NC} do painel se atualiza sozinha quando você instalar outro."
echo ""
