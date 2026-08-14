# 60-painel-web — painel de administração

Nginx + PHP-FPM 8.4 servindo o painel, mais o comando `gwos`, as permissões
sudo e as tarefas de cron.

## Depende de

- repositório GWOS completo (`app/`, `public/`, `routes/`, `scripts/`)
- **10-banco-mariadb** — opcional; sem ele o painel sobe em modo leve

## Modo completo e modo leve

O painel se adapta ao que existe na máquina, igual aos instaladores.

| | Modo leve (sem banco) | Modo completo |
|---|---|---|
| Módulos, estado, status dos serviços | sim | sim |
| Rede, DNS, hora, nomes internos | sim | sim |
| Grupos, IPs, domínios, horários, NAT | não | sim |
| Dashboard e relatórios | não | sim |
| Usuários | `/etc/gwos/painel-usuarios.json` | tabela `admins` |

No modo leve a home passa a ser a tela **Módulos**. Para migrar depois, instale
o `10-banco-mariadb` e reexecute este módulo — o painel completo liga sozinho.

## A tela Módulos

Lê `/etc/gwos/modulos.d/` a cada carregamento: instalou o chrony pelo terminal,
a seção aparece na próxima página. Não há cadastro nem script de atualização.
Mostra o estado dos serviços de cada módulo, o `gwos.conf` em vigor e o comando
de instalação dos que ainda faltam.

## O que faz

- Adiciona o repositório sury.org (o PHP 8.4 não existe nos repos do Debian 13)
- Instala Nginx e PHP 8.4 com as extensões usadas pelo painel
- Publica o site em `public/`, com `try_files` para o front controller
- Gera o `.env` a partir de `/etc/gwos/db.conf`
- Cria `/etc/sudoers.d/gwos` — só para os scripts que existem — e **valida com
  `visudo -c` antes de manter o arquivo**
- Liga `/usr/local/bin/gwos` ao `scripts/gwos-cli.sh`
- Instala o cron: backup diário, parser de logs a cada 5 min, importação do log
  do Squid de hora em hora
- Põe o `www-data` no grupo `proxy` (é o que permite o dashboard ler o
  `access.log`)
- Define a senha padrão do painel, se ainda for a de fábrica

## Instalação

```bash
bash instalar.sh
```

## Acesso

| | |
|---|---|
| URL | `http://IP_DO_GATEWAY` |
| Login | `admin@gwos.local` |
| Senha | `gwos@2025` — troque no primeiro acesso |

## Como o painel conversa com os outros módulos

Ao salvar uma alteração, o painel chama via `sudo` os scripts de `scripts/`,
que regeram as configurações dos outros módulos:

| Ação no painel | Script | Afeta |
|----------------|--------|-------|
| Grupos e IPs | `aplicar_nftables.sh` | nftables + listas do Squid |
| Domínios | `gerar_squid_dominios.sh`, `aplicar_bind9_rpz.sh` | Squid + RPZ do BIND9 |
| Horários | `gerar_squid_acl.sh` | Squid |
| NAT 1:1 | `aplicar_nat.sh` | nftables + `tcp_outgoing_address` |

Se um desses módulos não estiver instalado, o script simplesmente não tem o
que atualizar — nada quebra.

## Verificação

```bash
bash verificar.sh
```

Testa os serviços, o `nginx -t`, o `.env` (inclusive as permissões 600), o
sudoers, o cron e faz um `curl` no painel.
