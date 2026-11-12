#!/bin/bash
# GWOS — atualizador. Faz tudo o que é preciso para subir uma versão nova:
#   valida o pacote → backup → copia o código (preserva .env e storage) →
#   verifica a sintaxe → reaplica os módulos instalados (migrations, cron,
#   sudoers) → confere → restaura o snapshot de arquivos em caso de falha.
#
# Uso no Debian, a partir da pasta instalada ou da pasta gwos extraída:
#   sudo bash atualizar.sh
#   sudo bash atualizar.sh --simular
#   sudo bash atualizar.sh --dir /caminho/da/instalacao
#
# Sem argumento, usa a árvore de arquivos que acompanha este script.
# Na instalação, execute depois de copiar os arquivos novos ou rodar git pull.
# Também aceita um caminho explícito de outra pasta extraída ou ZIP.
# Opções:
#   --dir /opt/gwos        diretório da instalação (detecta sozinho se omitido)
#   --sem-backup-banco     não roda scripts/backup.sh (a cópia dos arquivos continua)
#   --sem-modulos          só copia o código (não reaplica módulos)
#   --simular              mostra o que faria, sem alterar nada
#   --sim                  não pergunta confirmação
set -Eeuo pipefail
umask 022

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[1m'; N='\033[0m'
LOG=/var/log/gwos-atualizacao.log
ok()    { echo -e "${G}[OK]${N} $*"  | tee -a "$LOG"; }
info()  { echo -e "${Y}[..]${N} $*"  | tee -a "$LOG"; }
aviso() { echo -e "${Y}[!]${N} $*"   | tee -a "$LOG"; }
falha() { echo -e "${R}[ERRO]${N} $*" | tee -a "$LOG" >&2; }

ORIGEM=""; DESTINO=""; SEM_BKP_BANCO=0; SEM_MODULOS=0; SIMULAR=0; SIM=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dir) [ "$#" -ge 2 ] || { falha "--dir exige um caminho."; exit 2; }; DESTINO="$2"; shift 2 ;;
        --sem-backup-banco) SEM_BKP_BANCO=1; shift ;;
        --sem-modulos) SEM_MODULOS=1; shift ;;
        --simular) SIMULAR=1; shift ;;
        --sim) SIM=1; shift ;;
        -h|--help) sed -n '2,/^set -/ { /^set -/d; p; }' "$0"; exit 0 ;;
        -*) falha "Opção desconhecida: $1"; exit 2 ;;
        *) [ -z "$ORIGEM" ] || { falha "Informe somente uma origem."; exit 2; }; ORIGEM="$1"; shift ;;
    esac
done

[ "$(id -u)" -eq 0 ] || { falha "Execute como root (sudo bash $0 ...)."; exit 2; }
mkdir -p "$(dirname "$LOG")"; echo "=== $(date '+%F %T') atualizar.sh $* ===" >> "$LOG"

# ── 0. Onde este script está? ──────────────────────────────────────────
AQUI="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
RAIZ_SCRIPT="$(cd "$AQUI/.." && pwd)"
if [ -z "$ORIGEM" ]; then
    ORIGEM="$RAIZ_SCRIPT"
fi
if [ -z "$DESTINO" ] && [ -f "$RAIZ_SCRIPT/.env" ] && [ -d "$RAIZ_SCRIPT/app" ]; then
    DESTINO="$RAIZ_SCRIPT"
fi

# ── 1. Localiza a instalação atual ─────────────────────────────────────
if [ -z "$DESTINO" ]; then
    if [ -L /usr/local/bin/gwos ]; then
        DESTINO="$(cd "$(dirname "$(readlink -f /usr/local/bin/gwos)")/.." && pwd)"
    else
        for d in /opt/gwos /opt/dns /srv/gwos "$HOME/gwos"; do
            [ -f "$d/.env" ] && [ -d "$d/app" ] && { DESTINO="$d"; break; }
        done
    fi
fi
[ -n "$DESTINO" ] && [ -d "$DESTINO/app" ] && [ -d "$DESTINO/modulos" ] \
    || { falha "Instalação do GWOS não encontrada. Informe com --dir /caminho."; exit 1; }
DESTINO="$(cd "$DESTINO" && pwd)"
info "Instalação atual: ${B}${DESTINO}${N}"

NO_LOCAL=0
if [ "$(readlink -f -- "$ORIGEM")" = "$DESTINO" ]; then
    [ -f "$DESTINO/.env" ] || { falha "A pasta de destino ainda não está instalada (.env ausente)."; exit 1; }
    NO_LOCAL=1
    info "Modo local: reaplicando a instalação com os arquivos que já estão em $DESTINO."
else
    info "Origem da atualização: $ORIGEM"
fi
if [ "$NO_LOCAL" -eq 1 ] && [ "$SEM_MODULOS" -eq 1 ]; then
    falha "--sem-modulos só faz sentido ao copiar de outra origem."
    exit 2
fi

# ── 2. Prepara o pacote novo ───────────────────────────────────────────
TMP="$(mktemp -d /tmp/gwos-atualizar.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
if [ -f "$ORIGEM" ]; then
    command -v unzip >/dev/null || { info "Instalando unzip..."; apt-get install -y -qq unzip >/dev/null; }
    unzip -tq "$ORIGEM" >/dev/null || { falha "ZIP corrompido: $ORIGEM"; exit 1; }
    unzip -q "$ORIGEM" -d "$TMP/novo"
    NOVO="$TMP/novo"
    # ZIP com uma pasta raiz única? Entra nela.
    if [ ! -d "$NOVO/app" ] && [ "$(find "$NOVO" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ]; then
        NOVO="$(find "$NOVO" -mindepth 1 -maxdepth 1 -type d | head -1)"
    fi
elif [ -d "$ORIGEM" ]; then
    NOVO="$(cd "$ORIGEM" && pwd)"
else
    falha "Não encontrei: $ORIGEM"; exit 1
fi
for f in app/Core/Router.php routes/web.php modulos/comum/lib.sh database/schema.sql config/config.php scripts/backup.sh scripts/ler_env.sh; do
    [ -f "$NOVO/$f" ] || { falha "Pacote inválido: falta $f"; exit 1; }
done
VERSAO_NOVA="$(grep -o "'versao' *=> *'[^']*'" "$NOVO/config/config.php" | sed "s/.*=> *'//;s/'//" || true)"
VERSAO_ATUAL="$(grep -o "'versao' *=> *'[^']*'" "$DESTINO/config/config.php" 2>/dev/null | sed "s/.*=> *'//;s/'//" || true)"
if [ "$NO_LOCAL" -eq 1 ]; then
    info "Versão dos arquivos presentes: ${VERSAO_NOVA:-desconhecida}"
else
    info "Versão atual: ${VERSAO_ATUAL:-desconhecida}  →  nova: ${VERSAO_NOVA:-desconhecida}"
fi
if [ "$NO_LOCAL" -eq 0 ] && [ -n "$VERSAO_NOVA" ] && [ "$VERSAO_NOVA" = "$VERSAO_ATUAL" ]; then
    aviso "O pacote tem a MESMA versão da instalação. Se não era isso, informe o caminho do pacote certo."
elif [ "$NO_LOCAL" -eq 0 ] && [ -n "$VERSAO_NOVA" ] && [ -n "$VERSAO_ATUAL" ] && [ "$(printf '%s\n%s\n' "$VERSAO_NOVA" "$VERSAO_ATUAL" | sort -V | head -1)" = "$VERSAO_NOVA" ]; then
    aviso "O pacote parece MAIS ANTIGO que a instalação (${VERSAO_NOVA} < ${VERSAO_ATUAL})."
    if [ "$SIM" -eq 1 ]; then falha "Recusado em modo --sim: versão mais antiga. Rode sem --sim para confirmar."; exit 1; fi
fi

# Sintaxe do código novo ANTES de tocar em qualquer coisa
if command -v php >/dev/null; then
    ruins=0
    while IFS= read -r -d '' f; do if ! detalhe=$(php -l "$f" 2>&1); then falha "Erro de sintaxe: ${f#$NOVO/}"; printf '%s\n' "$detalhe" | tee -a "$LOG" >&2; ruins=1; fi; done < <(find "$NOVO" -name '*.php' -print0)
    [ "$ruins" -eq 0 ] || { falha "Pacote com erro de sintaxe PHP; nada foi alterado."; exit 1; }
    ok "Sintaxe PHP do pacote novo verificada."
fi
while IFS= read -r -d '' f; do bash -n "$f" || { falha "Erro de sintaxe shell: ${f#$NOVO/}"; exit 1; }; done < <(find "$NOVO" -name '*.sh' -print0)
ok "Sintaxe shell do pacote novo verificada."

if [ "$SIMULAR" -eq 1 ]; then
    if [ "$NO_LOCAL" -eq 1 ]; then
        info "Simulação local: faria backup e reaplicaria os módulos instalados, sem copiar o código."
        exit 0
    fi
    command -v rsync >/dev/null || { falha "Instale rsync para simular a atualização."; exit 1; }
    info "Simulação: arquivos que seriam alterados em ${DESTINO}:"
    rsync -anic --exclude '.env' --exclude 'storage/' --exclude 'docs/capturas/' "$NOVO/" "$DESTINO/" | sed -n '1,60p'
    ok "Simulação concluída; nada foi alterado."; exit 0
fi

if [ "$NO_LOCAL" -eq 0 ] && [ "$SIM" -ne 1 ]; then
    read -rp "Atualizar ${DESTINO} para ${VERSAO_NOVA:-a versão nova}? Será feito backup antes. [s/N] " r
    [[ "$r" =~ ^[sSyY]$ ]] || { info "Cancelado."; exit 0; }
fi

# ── 3. Backup ──────────────────────────────────────────────────────────
command -v rsync >/dev/null || { info "Instalando rsync..."; apt-get install -y -qq rsync >/dev/null; }
BKP_BASE=/var/lib/gwos/atualizacoes; mkdir -p "$BKP_BASE"; chmod 700 "$BKP_BASE"
BKP="$(mktemp -d "$BKP_BASE/antes_$(date +%Y%m%d_%H%M%S)_XXXXXX")"
if [ "$NO_LOCAL" -eq 1 ]; then
    install -m 0600 "$DESTINO/.env" "$BKP/env-local"
    aviso "Backup local registra a configuração atual; o código anterior à cópia ou ao git pull depende de snapshot ou do Git."
else
    rsync -a --exclude '/storage/' --exclude '/.git/' "$DESTINO/" "$BKP/codigo/"
fi
# Snapshot dos arquivos gerenciados pelos módulos reaplicados.
DIRS_ESTADO=(/etc/gwos /etc/nginx/sites-available /etc/nginx/sites-enabled)
ARQS_ESTADO=(/etc/cron.d/gwos /etc/sudoers /etc/sudoers.d/gwos
    /usr/local/bin/gwos /usr/local/sbin/gwos-gerar-nginx /usr/local/sbin/gwos-gerar-portal-acesso)
for caminho in "${DIRS_ESTADO[@]}" "${ARQS_ESTADO[@]}"; do
    if [ -e "$caminho" ] || [ -L "$caminho" ]; then
        cp -a --parents "$caminho" "$BKP"
    fi
done
ok "Snapshot de atualização em ${BKP}"
if [ "$SEM_BKP_BANCO" -eq 0 ] && [ -f /etc/gwos/modulos.d/banco-mariadb ]; then
    [ -f "$DESTINO/.env" ] || { falha ".env ausente em uma instalação com banco."; exit 1; }
    # Usa o leitor literal da versão nova também no backup pré-atualização.
    mkdir -p "$TMP/backup/scripts"
    cp "$NOVO/scripts/"{backup,ler_env}.sh "$TMP/backup/scripts/"
    install -m 0600 "$DESTINO/.env" "$TMP/backup/.env"
    if bash "$TMP/backup/scripts/backup.sh" >>"$LOG" 2>&1; then
        ok "Backup do banco concluído (/var/lib/gwos/backups)."
    else
        falha "Backup do banco falhou. Corrija ou use --sem-backup-banco."; exit 1
    fi
else
    aviso "Backup do banco ignorado (módulo do banco ausente ou --sem-backup-banco)."
fi

reverter() {
    trap - ERR
    falha "Falha na atualização. Restaurando os arquivos do snapshot..."
    local falhou=0 caminho unidade
    if [ "$NO_LOCAL" -eq 1 ]; then
        install -m 0600 "$BKP/env-local" "$DESTINO/.env" || falhou=1
        aviso "Restauração local: o código que já estava na pasta continua lá."
    else
        rsync -a --delete --exclude '/storage/' --exclude '/.git/' "$BKP/codigo/" "$DESTINO/" || falhou=1
    fi
    if [ -f "$DESTINO/.env" ]; then
        chown root:www-data "$DESTINO/.env" && chmod 0640 "$DESTINO/.env" || falhou=1
    fi
    if [ "$SEM_MODULOS" -eq 0 ]; then
        for caminho in "${DIRS_ESTADO[@]}"; do
            if [ -d "$BKP$caminho" ]; then
                rsync -a --delete "$BKP$caminho/" "$caminho/" || falhou=1
            fi
        done
        for caminho in "${ARQS_ESTADO[@]}"; do
            if [ -e "$BKP$caminho" ] || [ -L "$BKP$caminho" ]; then
                cp -a --remove-destination "$BKP$caminho" "$caminho" || falhou=1
            else
                rm -f -- "$caminho" || falhou=1
            fi
        done
        if systemctl is-active --quiet nginx; then
            nginx -t >>"$LOG" 2>&1 && systemctl reload nginx >>"$LOG" 2>&1 || falhou=1
        fi
    fi
    for unidade in $(systemctl list-units --no-legend 'php*-fpm.service' 2>/dev/null | awk '{print $1}'); do
        systemctl restart "$unidade" >>"$LOG" 2>&1 || falhou=1
    done
    if [ "$falhou" -eq 0 ]; then
        aviso "Arquivos do snapshot restaurados de ${BKP}."
    else
        falha "Reversão incompleta. Confira o snapshot em ${BKP} e o log."
    fi
    aviso "O banco mantém as migrations executadas. Detalhes em ${LOG}."
    exit 1
}
trap 'reverter' ERR

# ── 4. Copia o código novo (preserva .env, storage e capturas) ─────────
if [ "$NO_LOCAL" -eq 0 ]; then
    info "Copiando o código novo..."
    rsync -ac --exclude '.env' --exclude '/storage/' --exclude '/.git/' --exclude 'docs/capturas/' "$NOVO/" "$DESTINO/"
fi
mkdir -p "$DESTINO/storage/tarefas"
chmod +x "$DESTINO"/scripts/*.sh "$DESTINO"/modulos/*.sh "$DESTINO"/modulos/*/*.sh 2>/dev/null || true
if id www-data >/dev/null 2>&1; then
    chown root:root "$DESTINO"
    chmod go-w "$DESTINO"
    chown -hR root:root "$DESTINO/app" "$DESTINO/bootstrap" "$DESTINO/routes" "$DESTINO/public" "$DESTINO/config/config.php"
    find "$DESTINO/app" "$DESTINO/bootstrap" "$DESTINO/routes" "$DESTINO/public" "$DESTINO/config/config.php" -type d -exec chmod 0755 {} +
    find "$DESTINO/app" "$DESTINO/bootstrap" "$DESTINO/routes" "$DESTINO/public" "$DESTINO/config/config.php" -type f -exec chmod 0644 {} +
    chown -R www-data:www-data "$DESTINO/storage"
    if [ -f "$DESTINO/.env" ]; then
        chown root:www-data "$DESTINO/.env"
        chmod 0640 "$DESTINO/.env"
    fi
fi
ok "Arquivos da instalação preparados."

# ── 5. Reaplica os módulos que já estão instalados ─────────────────────
VERIFICACAO_FALHOU=0
REG=/etc/gwos/modulos.d
if [ "$SEM_MODULOS" -eq 0 ]; then
    cd "$DESTINO/modulos"
    if [ -f "$REG/banco-mariadb" ]; then
        info "Reaplicando 10-banco-mariadb (migrations)..."
        bash 10-banco-mariadb/instalar.sh >>"$LOG" 2>&1 && ok "Banco: migrations aplicadas." || { falha "10-banco-mariadb falhou (veja $LOG)"; false; }
    fi
    if [ -f "$REG/painel-web" ]; then
        info "Reaplicando 60-painel-web (cron, permissões, sudoers, nginx)..."
        # Conta de admin já personalizada: não pergunta nada. Se precisar de
        # senha e houver terminal, o próprio módulo pergunta.
        bash 60-painel-web/instalar.sh --reaplicar 2>&1 | tee -a "$LOG" \
            && ok "Painel reaplicado." || { falha "60-painel-web falhou (veja $LOG)"; false; }
    fi
    # Módulos de rede NÃO são reinstalados (mexem em DNS/firewall/proxy), mas as REGRAS
    # do portal de login (squid.conf e nftables) acompanham a versão do painel:
    if [ -f "$REG/proxy-squid" ] && [ -f /etc/squid/squid.conf ] && ! cmp -s "$DESTINO/modulos/50-proxy-squid/config/squid.conf" /etc/squid/squid.conf; then
        info "Atualizando as regras do Squid (squid.conf)..."
        SQBAK="/etc/squid/squid.conf.bak.atualizar.$(date +%Y%m%d%H%M%S)"
        cp -a /etc/squid/squid.conf "$SQBAK"
        install -m 644 "$DESTINO/modulos/50-proxy-squid/config/squid.conf" /etc/squid/squid.conf
        install -m 755 "$DESTINO/modulos/50-proxy-squid/helpers/gwos-sessao.pl" /usr/local/sbin/gwos-squid-sessao 2>/dev/null || true
        [ -x /usr/local/sbin/gwos-integrar ] && /usr/local/sbin/gwos-integrar >>"$LOG" 2>&1 || true
        if squid -k parse >>"$LOG" 2>&1 &&
           { squid -k reconfigure >>"$LOG" 2>&1 || systemctl reload squid >>"$LOG" 2>&1; }; then
            ok "Squid atualizado (backup: $SQBAK)."
        else
            cp -a "$SQBAK" /etc/squid/squid.conf
            squid -k reconfigure >>"$LOG" 2>&1 || aviso "Falha ao recarregar a configuração anterior do Squid."
            aviso "Squid não confirmou as regras novas. Confira $LOG."
            VERIFICACAO_FALHOU=1
        fi
    fi
    if [ -f "$REG/firewall-nftables" ] && [ -x "$DESTINO/scripts/aplicar_nftables.sh" ]; then
        info "Reaplicando o firewall com as regras novas (login obrigatório / QUIC)..."
        bash "$DESTINO/scripts/aplicar_nftables.sh" >>"$LOG" 2>&1 \
            && ok "Firewall reaplicado." || { aviso "Não foi possível reaplicar o firewall (veja $LOG)."; VERIFICACAO_FALHOU=1; }
    fi
    aviso "Módulos de DNS, hora e a instalação dos pacotes de rede não foram reinstalados de propósito."
else
    aviso "--sem-modulos: migrations, cron e sudoers NÃO foram reaplicados."
fi

# ── 6. Confere ─────────────────────────────────────────────────────────
cd "$DESTINO"
if command -v php >/dev/null && [ -f .env ]; then
    php -r 'chdir($argv[1]); require "bootstrap/app.php"; echo "bootstrap OK\n";' "$DESTINO" >>"$LOG" 2>&1 \
        && ok "Aplicação carrega sem erro." || { false; }
fi
if [ -f modulos/verificar-todos.sh ] && [ "$SEM_MODULOS" -eq 0 ]; then
    bash modulos/verificar-todos.sh 2>&1 | tee -a "$LOG" || VERIFICACAO_FALHOU=1
fi
URL="$(grep -E '^APP_URL=' .env 2>/dev/null | cut -d= -f2- || true)"
if [ -n "$URL" ] && command -v curl >/dev/null; then
    cod="$(curl --noproxy "*" -ks -o /dev/null -m 8 -w '%{http_code}' "${URL%/}/login" || true)"
    [ "$cod" = "200" ] && ok "Painel respondeu 200 em ${URL%/}/login" || { aviso "Painel respondeu '${cod:-sem resposta}' em ${URL%/}/login."; VERIFICACAO_FALHOU=1; }
fi

trap - ERR
if [ "$VERIFICACAO_FALHOU" -eq 0 ]; then
    # Remove somente os dois auxiliares legados do destino atual.
    rm -f -- "$DESTINO/atualiz.sh" "$DESTINO/scripts/atualiz.sh"
fi
echo ""
if [ "$VERIFICACAO_FALHOU" -eq 0 ]; then
    if [ "$NO_LOCAL" -eq 1 ]; then
        ok "Reaplicação local concluída: ${VERSAO_NOVA:-?}"
    else
        ok "Atualização concluída: ${VERSAO_ATUAL:-?} → ${VERSAO_NOVA:-?}"
    fi
else
    aviso "Atualização aplicada com pendências na verificação dos módulos. Confira os erros acima e o log completo."
fi
echo -e "  Backup (código/config): ${B}${BKP}${N}"
echo -e "  Log: ${B}${LOG}${N}"
echo -e "  Próximo passo: entre no painel, abra ${B}Diagnóstico${N} e teste uma ação rápida em um PC de teste."

[ "$VERIFICACAO_FALHOU" -eq 0 ] || exit 2
