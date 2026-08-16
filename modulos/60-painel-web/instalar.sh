#!/bin/bash
# ============================================================================
# GWOS — Módulo 60-painel-web: painel de administração
# ============================================================================
# Instala o Nginx + PHP-FPM (a versão da própria distribuição), publica o
# painel, cria o comando 'gwos', as permissões sudo e as tarefas de cron.
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
# PHP — usa a versão da própria distribuição
# ---------------------------------------------------------------------------
# Debian 12 traz 8.2, Debian 13 traz 8.4. Qualquer uma serve para o painel.
# O repositório sury.org só entra em cena se o Debian for antigo demais — é de
# terceiros, e uma fonte a menos é uma coisa a menos para quebrar.
apt_update_uma_vez
PHP_VER="$(detectar_php_disponivel || echo '')"

if [ -n "$PHP_VER" ] && php_versao_suficiente "$PHP_VER" "$PHP_MINIMO"; then
    ok "PHP ${PHP_VER} disponível no Debian $(. /etc/os-release 2>/dev/null; echo "${VERSION_ID:-?}") — sem repositório extra."
else
    aviso "PHP da distribuição ${PHP_VER:-ausente} é inferior ao mínimo ${PHP_MINIMO}."
    info "Adicionando o repositório PHP (sury.org)..."
    instalar_pacotes curl gnupg2 lsb-release ca-certificates apt-transport-https
    curl -fsSL https://packages.sury.org/php/apt.gpg \
        | gpg --dearmor -o /etc/apt/trusted.gpg.d/php-sury.gpg
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" \
        > /etc/apt/sources.list.d/php-sury.list
    apt-get update -qq
    PHP_VER="$(detectar_php_disponivel || echo '8.4')"
    ok "Repositório sury.org adicionado — PHP ${PHP_VER}."
fi

instalar_pacotes nginx \
    "php${PHP_VER}" "php${PHP_VER}-fpm" "php${PHP_VER}-mysql" "php${PHP_VER}-mbstring" \
    "php${PHP_VER}-curl" "php${PHP_VER}-zip" "php${PHP_VER}-xml" "php${PHP_VER}-intl" \
    tar gzip unzip

# ---------------------------------------------------------------------------
# PHP-FPM
# ---------------------------------------------------------------------------
PHP_INI="/etc/php/${PHP_VER}/fpm/php.ini"
[ -f "$PHP_INI" ] || erro "php.ini não encontrado em ${PHP_INI} — instalação do PHP falhou."
sed -i "s|;date.timezone.*|date.timezone = America/Sao_Paulo|" "$PHP_INI"
sed -i "s|upload_max_filesize.*|upload_max_filesize = 64M|"    "$PHP_INI"
sed -i "s|post_max_size.*|post_max_size = 64M|"                "$PHP_INI"
svc_ativar "php${PHP_VER}-fpm"

PHP_SOCK="/run/php/php${PHP_VER}-fpm.sock"
ok "PHP-FPM ${PHP_VER} configurado (${PHP_SOCK})."

# Guarda a versão no estado compartilhado — o painel usa para saber qual
# serviço monitorar, e o desinstalador para saber o que remover.
salvar_conf PHP_VERSAO "$PHP_VER"

# ---------------------------------------------------------------------------
# Nginx — o painel precisa de uma porta só dele
# ---------------------------------------------------------------------------
# Numa unidade é comum a mesma máquina hospedar mais de um portal (o de
# sistemas, o do Samba). Dois deles na porta 80 não convivem: quem subir
# primeiro fica, o outro entra em laço de reinício. Por isso a porta é
# PERGUNTADA, com um padrão que já leva em conta o que existe na máquina.
SITES_EXISTENTES="$(nginx_outros_sites)"
DONO_80="$(porta_em_uso 80)"

if [ "${SITES_EXISTENTES:-0}" -gt 0 ] || { [ -n "$DONO_80" ] && ! echo "$DONO_80" | grep -q nginx; }; then
    PORTA_SUGERIDA="$(primeira_porta_livre 8080 8081 8090 9080 || echo 8080)"
    [ "${SITES_EXISTENTES:-0}" -gt 0 ]         && aviso "Esta máquina já serve ${SITES_EXISTENTES} outro(s) site(s) no nginx."         || aviso "A porta 80 já está em uso por: ${DONO_80}"
    echo "      O painel do GWOS precisa de uma porta própria."
else
    PORTA_SUGERIDA=80
fi

titulo "── Porta do painel ──"
echo ""
echo "  Em quem já usa a 80 para outro portal, escolha 8080 (ou outra)."
echo "  Depois dá para mudar com: gwos-definir PAINEL_PORTA <porta>"
echo ""
perguntar PAINEL_PORTA "Porta do painel GWOS" "$PORTA_SUGERIDA"

while ! echo "$PAINEL_PORTA" | grep -qE '^[0-9]{1,5}$' || [ "$PAINEL_PORTA" -lt 1 ] || [ "$PAINEL_PORTA" -gt 65535 ]; do
    aviso "Porta inválida: '${PAINEL_PORTA}'"
    perguntar PAINEL_PORTA "Porta do painel GWOS" "$PORTA_SUGERIDA"
done

OCUPANTE="$(porta_em_uso "$PAINEL_PORTA")"
while [ -n "$OCUPANTE" ] && ! echo "$OCUPANTE" | grep -q nginx; do
    aviso "A porta ${PAINEL_PORTA} está ocupada por: ${OCUPANTE}"
    perguntar PAINEL_PORTA "Outra porta para o painel" "$(primeira_porta_livre 8080 8081 8090 9080 || echo 8080)"
    OCUPANTE="$(porta_em_uso "$PAINEL_PORTA")"
done

salvar_conf PAINEL_PORTA "$PAINEL_PORTA"

# O site 'default' de fábrica só sai se o painel assumir a 80 sozinho.
if [ -e /etc/nginx/sites-enabled/default ]    && [ "${SITES_EXISTENTES:-0}" -eq 0 ] && [ "$PAINEL_PORTA" = "80" ]; then
    rm -f /etc/nginx/sites-enabled/default
    info "Site 'default' do Debian removido."
fi

# Instalação anterior usava o nome 'gwos' — dois vhosts do mesmo painel na
# mesma porta faria o nginx recusar a configuração.
rm -f /etc/nginx/sites-enabled/gwos /etc/nginx/sites-available/gwos

install -m 755 "${MOD_DIR}/gerar-nginx.sh" /usr/local/sbin/gwos-gerar-nginx

if ! /usr/local/sbin/gwos-gerar-nginx; then
    falha "Não foi possível publicar o site do painel."
    journalctl -xeu nginx --no-pager -n 15 2>/dev/null | sed 's/^/      /' || true
    erro "Módulo interrompido."
fi

svc_ativar nginx
ok "Nginx configurado na porta ${PAINEL_PORTA}."

# ---------------------------------------------------------------------------
# .env
# ---------------------------------------------------------------------------
if [ "$PAINEL_PORTA" = "80" ]; then
    APP_URL_PAINEL="http://${IP_GATEWAY}"
else
    APP_URL_PAINEL="http://${IP_GATEWAY}:${PAINEL_PORTA}"
fi

if [ "$MODO_LEVE" = "0" ]; then
    cat > "${REPO}/.env" <<ENV
APP_URL=${APP_URL_PAINEL}
APP_DEBUG=false
DB_HOST=${DB_HOST}
DB_BANCO=${DB_BANCO}
DB_USUARIO=${DB_USUARIO}
DB_SENHA=${DB_SENHA}
ENV
else
    cat > "${REPO}/.env" <<ENV
APP_URL=${APP_URL_PAINEL}
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
    # Únicos caminhos de escrita do painel fora do banco. A lista de chaves, a
    # validação dos valores e o named-checkconf ficam dentro dos scripts.
    echo "www-data ALL=(root) NOPASSWD: /usr/local/sbin/gwos-definir"
    echo "www-data ALL=(root) NOPASSWD: /usr/local/sbin/gwos-zona"
    # Leitura e recarga dos serviços, com par (ação, módulo) de lista fechada
    echo "www-data ALL=(root) NOPASSWD: /usr/local/sbin/gwos-servico"
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
echo -e "  URL          : ${BOLD}${APP_URL_PAINEL}${NC}"
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
