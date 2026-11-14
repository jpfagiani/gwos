# GWOS — documentação consolidada

Pacote GWOS 2.0.54-dev. As seções de diagnóstico e histórico registram o estado das revisões citadas. Consulte os testes para verificar a evidência disponível nesta versão.

## Índice

- [Visão geral](#visao-geral)
- [Instalação em VM](#instalacao-vm)
- [Atualização e recuperação](#atualizacao)
- [Manual de instalação e uso](#manual)
- [Instalação modular](#modulos)
- [00-base — rede e preparação da máquina](#modulo-00-base)
- [10-banco-mariadb — banco de dados](#modulo-10-banco-mariadb)
- [20-dns-bind9 — servidor DNS da rede](#modulo-20-dns-bind9)
- [25-dns-interno-dnsmasq — nomes internos da LAN](#modulo-25-dns-interno-dnsmasq)
- [30-hora-chrony — servidor de hora (NTP)](#modulo-30-hora-chrony)
- [40-firewall-nftables — firewall e NAT](#modulo-40-firewall-nftables)
- [50-proxy-squid — proxy HTTP/HTTPS com SSL Bump](#modulo-50-proxy-squid)
- [60-painel-web — painel de administração](#modulo-60-painel-web)
- [Arquitetura](#arquitetura)
- [Matriz de funcionalidades](#funcionalidades)
- [Diagnóstico da revisão anterior](#diagnostico)
- [Resumo executivo da versão 2.0.1-dev](#resumo-historico)
- [Histórico de implementação até a versão 2.0.1-dev](#historico)
- [Testes, resultados e pendências](#testes)

<a id="visao-geral"></a>

## Visão geral

Gateway para rede local em Debian 12/13: DNS com bloqueio por domínio, proxy
HTTP/HTTPS com inspeção de TLS, firewall com NAT, servidor de hora e um painel
web para administrar tudo.

Cada servidor é um **módulo independente**. Dá para instalar só o DNS numa
máquina, só o proxy em outra, ou todos no mesmo gateway — quando convivem, se
integram sozinhos.

---

### Instalação

```bash
apt install -y git
git clone https://github.com/jpfagiani/gwos.git /opt/gwos
cd /opt/gwos

# Tudo, na ordem
bash install/install.sh

# Ou um servidor isolado
bash modulos/20-dns-bind9/instalar.sh
```

O painel inclui visões de monitoramento, equipamentos observados, ranking de
consumo, alertas, agenda de políticas e simulação. A telemetria depende dos
módulos correspondentes instalados e de haver registros coletados; valores sem
fonte aparecem vazios. Para VMs já instaladas, use [Atualização e recuperação](#atualizacao)
para atualizar o pacote e reaplicar o módulo do banco, que executa as migrations.

Ao final: `http://IP_DO_GATEWAY:8080`. Durante a instalação do módulo do
painel o instalador **pede a senha do administrador** (digitação oculta, com
confirmação, mínimo 8 caracteres); nada é gerado nem exibido. Para instalação
sem terminal, exporte `GWOS_ADMIN_SENHA` antes de rodar.

### Instalar usando o ZIP

Siga o roteiro de [instalação em VM](#instalacao-vm).

---

### Os módulos

| Pasta | Serviço | Função |
|-------|---------|--------|
| `modulos/00-base` | — | Rede, firmware, encaminhamento de pacotes, estado compartilhado |
| `modulos/10-banco-mariadb` | `mariadb` | Grupos, IPs, domínios, horários, relatórios |
| `modulos/20-dns-bind9` | `named` | DNS da rede, RPZ, zonas dos domínios internos |
| `modulos/25-dns-interno-dnsmasq` | `gwos-dnsmasq` | Nomes internos da LAN |
| `modulos/30-hora-chrony` | `chrony` | Servidor de hora (NTP) |
| `modulos/40-firewall-nftables` | `nftables` | Firewall, NAT e redirecionamentos |
| `modulos/50-proxy-squid` | `squid` | Proxy 3127/3128/3129 com SSL Bump |
| `modulos/60-painel-web` | `nginx`, PHP-FPM da distribuição | Painel de administração |

Nenhuma dependência é obrigatória: sem o banco, o painel sobe em modo leve com
as telas cujos dados vivem em arquivo.

Detalhes em [Instalação modular](#modulos).

---

### Como funcionam isolados

Nenhum módulo depende do instalador para descobrir a rede. Quem precisa saber
a LAN, a rede ou o domínio interno lê `/etc/gwos/gwos.conf`; se o arquivo não
existir, é criado a partir do que o sistema já tem — **sem tocar em
`/etc/network/interfaces`**. Só o `00-base` reconfigura a rede de verdade.

### Como se integram

Ao terminar, todo módulo roda `gwos-integrar`, que olha o que existe na máquina
e reescreve só os pontos de contato:

- o firewall só redireciona 80/443 se houver Squid;
- o Squid só resolve por `127.0.0.1` se houver BIND9;
- o BIND9 só encaminha o domínio interno se houver dnsmasq;
- o chrony libera as redes internas atuais.

Por isso a ordem não importa: instale o Squid depois do firewall e o firewall
se reajusta; remova o Squid e os redirecionamentos somem antes de a rede ficar
sem internet.

---

### Painel

O menu é montado a partir de `/etc/gwos/modulos.d`: instalou um módulo pelo
terminal, a seção aparece na próxima página.

| Tela | O que dá para fazer |
|------|---------------------|
| Módulos | O que está instalado, estado dos serviços, o que falta |
| DNS | Resolvers, teste de cada um, zonas, resolução ao vivo |
| Nomes internos | Vincular nome a IP |
| Hora | Servidores NTP, sincronização, quem consulta |
| Firewall | Regras em vigor e a origem de cada uma; regerar |
| Proxy | Portas, SSL Bump, listas, últimos acessos |
| Grupos, Domínios, Horários, NAT, Relatórios | Exigem o módulo de banco |

O painel nunca escreve em `/etc` nem recarrega serviço por conta própria: tudo
passa por `gwos-definir`, `gwos-zona` ou `gwos-servico`, que validam com a
ferramenta do próprio serviço (`named-checkconf`, `nft -c`, `squid -k parse`)
antes de aplicar e desfazem sozinhos se a configuração não passar.

---

### Linha de comando

```bash
gwos status                  # estado dos serviços
gwos diag                    # diagnóstico completo
gwos ip 10.14.29.20          # trocar o IP do gateway com validação e backup
gwos dns add portal 10.14.29.8
gwos log live                # acessos em tempo real
gwos backup criar

bash modulos/verificar-todos.sh   # diagnóstico módulo a módulo
```

Referência completa no [Manual de instalação e uso](#manual).

---

### Requisitos

- Debian 12 ou 13, instalação mínima
- Duas interfaces de rede para uso como gateway (uma só basta para DNS ou hora)
- Acesso root

> **Trocar o IP do gateway é sempre `gwos ip`**, nunca edição manual seguida de
> `systemctl restart networking`. O comando valida com `ifquery`, faz backup e
> adiciona o IP novo antes de remover o antigo — a interface nunca fica sem
> endereço e a sessão SSH não cai.

### Evolução de segurança e dashboard

A cópia de entrega inclui endurecimento de sessão, autenticação por padrão no roteador, CSRF centralizado para alterações, logout via POST e monitoramento com estados de coleta. Consulte [Diagnóstico da revisão anterior](#diagnostico), [Matriz de funcionalidades](#funcionalidades), [Histórico de implementação até a versão 2.0.1-dev](#historico), [Testes, resultados e pendências](#testes) e [Atualização e recuperação](#atualizacao).

A entrega ainda requer validação com PHP CLI e homologação em Debian de laboratório. Para uma VM, siga [Instalação em VM](#instalacao-vm); não use em produção antes de concluir esses testes.

<a id="instalacao-vm"></a>

## Instalação em VM

Este roteiro instala o pacote `0.2.0-dev` em uma VM Debian limpa. Ele foi
preparado para laboratório; o pacote ainda não foi homologado em hardware ou
rede de produção.

### 1. Criar a VM

Recomendação para uma VM de teste: Debian 13 minimal, 2 vCPU, 4 GB de RAM e
40 GB de disco. Reserve um snapshot antes da instalação. O instalador pode
reescrever a configuração de rede da VM.

Configure duas placas de rede:

1. **WAN:** NAT do hypervisor, com DHCP e saída para a internet. Ela permite
   baixar os pacotes Debian sem expor a VM diretamente à rede externa.
2. **LAN:** rede host-only/interna, para acessar o painel a partir do host e
   conectar VMs cliente de teste. Escolha uma sub-rede privada sem conflito
   com a rede real; desative o DHCP embutido do host-only se ele conflitar.

Não conecte a LAN da VM a uma rede de produção. O instalador `00-base` grava a
configuração de interfaces da VM. Com uma só placa, o projeto entra em modo
servidor e não instala o firewall de gateway.

### 2. Copiar e extrair o pacote

Anexe o ZIP à VM por ISO, pasta compartilhada ou SCP. No Debian, como `root`:

```bash
apt update
apt install -y unzip
unzip -q /caminho/GWOS-v2.0.54-dev-liberacao.zip -d /opt
cd /opt/gwos
```

O ZIP contém a pasta `gwos/`. O comando acima cria `/opt/gwos` em uma VM limpa. Não copie `.env`:
ele é criado pelo instalador com as credenciais geradas na VM.

### 3. Instalar os módulos

Confirme que a VM tem as duas placas esperadas e rode:

```bash
bash install/install.sh
```

O instalador solicita identidade, domínio, WAN, LAN, endereço do gateway LAN e
perfil. Confira com atenção os nomes das interfaces, a sub-rede e o resumo
antes de confirmar cada módulo. Para o painel completo, mantenha selecionados
os módulos `10-banco-mariadb` e `60-painel-web`; para funções de gateway,
mantenha também DNS, firewall e proxy.

Durante o módulo do painel, o instalador pede que você digite a senha do
administrador (`admin@gwos.local`) duas vezes, sem eco. Use a que escolher aqui
para entrar. Para instalar sem terminal: `GWOS_ADMIN_SENHA='...' bash modulos/instalar-todos.sh`.

### 4. Acessar e conferir

Do host, abra `http://<IP-LAN-DA-VM>:8080`. A porta usa HTTP simples e deve
ficar restrita à rede isolada do laboratório. Para verificar os módulos:

```bash
gwos status
bash /opt/gwos/modulos/verificar-todos.sh
```

No painel, confira **Módulos**, **Histórico de tarefas** e o dashboard. O
worker de tarefas roda pelo cron como `www-data`; se tarefas ficarem na fila,
verifique `/etc/cron.d/gwos`, o serviço cron e os logs locais.

Na revisão v2, use **Monitoramento**, **Ranking de consumo**, **Equipamentos**,
**Controle de acesso**, **Alertas e eventos** e **Agenda e simulador** para verificar os registros
observados. Depois de atualizar uma VM já instalada, reaplique o módulo
`10-banco-mariadb` para executar as migrations sem apagar os dados. O painel de
alertas e inventário depende das tarefas cron instaladas pelo módulo web.

Antes de aplicar mudanças, abra **Firewall** e gere a prévia/diff. Mudanças de
endereço IP devem ser feitas com acesso ao console da VM disponível. Exercite o
rollback em um snapshot descartável antes de confiar nele operacionalmente.

Teste primeiro com uma VM cliente conectada somente à LAN host-only. Use uma
configuração IP estática no cliente para conferir conectividade, regras do
firewall, DNS e Squid. Testes do portal cativo e SSL Bump exigem clientes e
certificado de CA instalados no laboratório.

### 5. Validação antes de avançar

- Execute `php -l` para os arquivos PHP se estiver validando uma cópia de
  desenvolvimento; execute também `bash -n` nos scripts alterados.
- Confira o login, a troca inicial de senha, a sessão, os perfis e CSRF.
- Crie uma tarefa de cada tipo habilitado e confira seu resultado e estado no
  histórico.
- Faça backup e restaure em uma VM descartável antes de confiar na recuperação.
- Verifique regras, DNS, acesso HTTP/HTTPS, comportamento dos grupos e logs.
- Tire um novo snapshot da VM somente depois de confirmar o login com a senha que você definiu,
  registrar os endereços escolhidos e confirmar o acesso pelo console.

Se algum módulo falhar, não conecte a VM a uma rede de produção. Restaure o
snapshot do hypervisor e consulte os registros do instalador e
[Testes, resultados e pendências](#testes).

<a id="atualizacao"></a>

## Atualização e recuperação

### Atualizar na própria instalação

Depois de copiar os arquivos novos para a pasta instalada do GWOS, ou de
executar `git pull` nessa pasta, rode:

```bash
cd /opt/gwos
sudo bash atualizar.sh
```

O modo local valida os arquivos presentes e reaplica os módulos instalados.
Ele não copia a pasta sobre si mesma. O backup protege o estado que existe
quando o script começa. Para recuperar o código de antes da cópia ou do
`git pull`, use o Git ou um snapshot tirado antes dessa etapa.

O fluxo por pasta extraída separada ou ZIP também está disponível. Use
`--dir /opt/gwos` se precisar informar o destino e `--simular` para conferir
qual fluxo será usado.

O script detecta a instalação, valida o pacote (ZIP e sintaxe PHP/shell, antes de alterar qualquer coisa), faz backup do código, da configuração e do banco, copia o código preservando `.env` e `storage/`, reaplica os módulos de banco e painel (migrations, cron, sudoers), confere se a aplicação carrega e se o painel responde, e tenta restaurar o snapshot de arquivos se uma etapa obrigatória falhar. A reversão cobre o código e os arquivos capturados de GWOS, cron, Nginx e sudoers. Migrações SQL, alterações de pacotes e outros efeitos no sistema exigem o snapshot da VM ou recuperação manual. Opções: `--simular` (só mostra o que mudaria), `--sim` (sem confirmação), `--dir /opt/gwos`, `--sem-backup-banco`, `--sem-modulos`. Log: `/var/log/gwos-atualizacao.log`; backups: `/var/lib/gwos/atualizacoes/`. Módulos de rede (DNS, firewall, proxy, hora) não são reinstalados.

### Atualizar manualmente (passo a passo)

Faça primeiro em uma VM de laboratório (ou com snapshot) e mantenha acesso ao console. Os comandos abaixo supõem que o GWOS está em `/opt/gwos`; ajuste se o seu estiver em outro diretório (`readlink -f /usr/local/bin/gwos` mostra o caminho).

1. **Backup** (no servidor, como root):
   ```
   cd /opt/gwos && ./scripts/backup.sh          # ou: gwos backup
   cp -a /opt/gwos /root/gwos-antes-v2.0.0
   ```
   Se for VM, tire também um snapshot.
2. **Enviar o pacote** `GWOS-v2.0.53-dev-paleta.zip` para o servidor (scp, WinSCP ou pen drive) e extrair em uma pasta temporária:
   ```
   apt-get install -y unzip
   mkdir /root/gwos-novo && unzip GWOS-v2.0.53-dev-paleta.zip -d /root/gwos-novo
   ```
3. **Copiar o código novo por cima, preservando a configuração** (`.env` e `storage/` não são sobrescritos):
   ```
   rsync -a --exclude '.env' --exclude 'storage/' /root/gwos-novo/gwos/ /opt/gwos/
   ```
4. **Reaplicar os módulos do banco e do painel.** Isso roda as migrations (inclusive a 009, que mantém a aplicação das expirações pendente até a confirmação), atualiza cron, permissões e sudoers e reinicia o PHP-FPM:
   ```
   cd /opt/gwos/modulos
   bash 10-banco-mariadb/instalar.sh
   bash 60-painel-web/instalar.sh
   ```
   Contas de administrador já personalizadas são preservadas e **nenhuma senha é pedida**. A senha só é pedida se a conta ainda estiver com a senha de fábrica ou não existir (use `GWOS_ADMIN_SENHA` para modo sem terminal).
5. **Conferir:**
   ```
   bash /opt/gwos/modulos/verificar-todos.sh
   ```
   Abra o painel, entre, veja **Diagnóstico** e o **Histórico de tarefas**. Dê 2 a 3 minutos para os coletores (cron) gravarem as primeiras amostras de tráfego.
6. **Teste de fumaça das ações rápidas:** em um PC de teste, use *Liberar temporário* por 5 minutos e confirme que o acesso muda e depois volta. Não teste em equipamentos críticos.

**Voltar atrás:** restaure `/root/gwos-antes-v2.0.0` sobre `/opt/gwos` (ou o snapshot) e rode `bash 60-painel-web/instalar.sh`. Para recuperar também o banco e os pacotes do sistema, use o snapshot da VM.

---

### Situação desta entrega

Esta cópia contém alterações em PHP, shell, JavaScript e schema. A origem ZIP foi preservada. Não execute os instaladores no servidor de produção antes de revisar a cópia em ambiente de laboratório.

### Preparação

1. Criar snapshot/backup do GWOS e do sistema Debian.
2. Guardar cópia de `.env`, `/etc/gwos/`, `/etc/squid/`, `/etc/bind/`, `/etc/nftables.conf`, `/etc/network/interfaces`, banco MariaDB e regras de sudoers, protegendo segredos e chaves.
3. Confirmar versão do PHP-FPM, extensões usadas, módulos GWOS e rotas publicadas.
4. Copiar o código para uma instalação de laboratório; não copiar `.env` para este ZIP.
5. Executar `php -l` nos arquivos PHP alterados e `node --check public/assets/js/app.js` e no script inline do dashboard.

### Banco

Aplicar migrations em ordem, incluindo `003_remover_credencial_padrao.sql`, `004_operacional_v2.sql`, `005_trafego_direcional.sql`, `006_historico_sessoes.sql`, `007_importacao_squid_idempotente.sql`, `008_liberacao_temporaria.sql` e `009_fila_expiracao.sql`. A migration 005 inclui bytes direcionais, metadados de lease/interface e o limite de sessões do portal; o módulo `10-banco-mariadb` registra migrations concluídas e reconcilia as migrations idempotentes na primeira atualização de uma instalação antiga. A migration 003 remove apenas a conta cujo hash é exatamente o legado conhecido. O instalador do painel pede a senha do administrador (digitada por quem instala) ao criar a conta, ou preserva os administradores existentes. Novas instalações não recebem senha fixa no schema.

### Configuração

- Inatividade administrativa padrão: 30 minutos (`session.inatividade`).
- Limite absoluto padrão: 8 horas (`session.duracao_maxima`).
- Cookie de sessão com `HttpOnly`, `SameSite=Lax`; `Secure` depende de `APP_URL` estar em HTTPS.
- O perfil `operador` é somente leitura para rotas mutáveis, exceto logout e troca de senha.
- O worker de operações depende do cron em `/etc/cron.d/gwos`, acesso `www-data` ao diretório `storage/tarefas` e entradas sudoers exatas instaladas pelo módulo web. O diretório `/var/lib/gwos/backups` deve continuar `root:root` e modo `0700`; sessões ficam em `/var/lib/gwos/sessions`.
- A tela Histórico de operações só atualiza os estados enquanto o worker cron estiver ativo. Um estado `não confirmado` precisa de conferência manual no serviço antes de repetir uma ação.
- Backups novos incluem um arquivo lateral `.sha256`; restauração aceita membros nomeados do formato GWOS esperado. Faça um exercício de restauração em laboratório antes de confiar na rotina.
- O CSV de relatórios é limitado a 50.000 linhas por exportação; operador recebe IPs mascarados.

### Homologação em laboratório

Verificar login bom/ruim, conta desativada com sessão ativa, expiração por inatividade, limite absoluto, limite e concorrência de até três sessões finais, GET `/logout` rejeitado, POST logout sem/com CSRF, mutação sem CSRF, restrição de operador, admin e superadmin.

Verificar portal de usuários separado do painel: cadastro, e-mail, senha, sessão, expiração, revogação, IP trocado, limite de três dispositivos simultâneos, falha de serviço e políticas dos grupos. Confirmar que uma credencial final não acessa rotas administrativas. Conferir o redirect HTTP do Squid, helper, autenticação e fail-closed em máquina dedicada.

Verificar que linhas novas no access.log incluem bytes de requisição e resposta; registros legados continuam importáveis e mostram upload sem dados. Conferir ranking e equipamento por período.

Verificar a aba de conexões ativas contra `ss -Htn state established` enquanto clientes abrem conexões ao Squid; sockets não têm dados de destino remoto/volume por fluxo. Simular DNS indisponível, certificado próximo do vencimento, sessão acima do limite e operação falha para conferir alertas e resolução.

Verificar coleta de rede normal, interfaces ausentes, contador reiniciado, falha HTTP e intervalo irregular. Conferir unidade bps, ausência de valores fabricados e que módulos não instalados não aparecem como serviços parados.

Verificar fila com chamadas duplicadas e concorrentes; worker indisponível; comando inválido; timeout; saída não zero; serviço parado após comando; NAT esperado no ruleset; e recuperação de estado `running` órfão. Conferir que usuário web não consegue ler backups e que PHP-FPM consegue ler sessões após reinício.

Criar backup, validar checksum, corromper cópia de teste, tentar membro inesperado/link simbólico e restaurar numa máquina descartável. Confirmar que rede e banco ficam consistentes depois da recuperação.

Revisar visual em 1440, 1024, 768 e 390 px, navegação por teclado, foco, Escape e clique no backdrop.

### Rollback

1. Desabilitar o tráfego administrativo no balanceador/proxy do laboratório.
2. Restaurar snapshot/código anterior e backup de `.env`/arquivos do GWOS.
3. Confirmar login e rotas administrativas somente em laboratório.
4. Não restaure uma credencial fixa. Se voltar a uma versão anterior do código em laboratório, gere uma senha temporária nova pela CLI e obrigue a troca no próximo acesso.
5. Se o teste falhar no host de laboratório, restaurar snapshot antes de testar novamente.

Os scripts de firewall e troca de IP têm snapshot e tentativa de rollback automático no erro. Isso ainda não foi validado em VM; mantenha console/snapshot do hypervisor disponível e exercite cenários de falha numa VM descartável antes de habilitar alterações críticas em produção.


### Migrações do relatório mestre v2.0

Para atualizar uma instalação existente a partir do pacote v2.0-dev, faça backup do banco e execute em ordem as migrations ainda não aplicadas. A migration `006_historico_sessoes.sql` cria o histórico que alimenta a seção “Histórico de sessões encerradas”; ele começa a registrar encerramentos após a atualização e não recupera sessões antigas. A migration `007_importacao_squid_idempotente.sql` adiciona uma chave por linha para impedir duplicação quando o importador reprocessa o log. O código atual também grava o grupo mais específico no momento do login; sessões ativas anteriores à migration não têm esse snapshot. O script `scripts/ativar_acesso_internet.sh` aplica as migrations 002 e 004–009. Não execute novamente migrations antigas que alterem credenciais/configurações sem conferir os avisos de cada arquivo.

<a id="manual"></a>

## Manual de instalação e uso

**Gateway Web OS** — Firewall, DNS, Proxy Squid com controle de acesso por grupos de IPs.

- **IP do gateway:** escolhido no assistente de instalação
- **Painel web:** `http://<IP_DO_GATEWAY>:8080` (porta 8080 por convenção — a 80 fica para o portal de sistemas)
- **Login inicial:** `admin@gwos.local`; a senha é a que você digita durante a instalação do módulo do painel.

---

### 1. Instalação do Zero

Para instalar a cópia recebida como ZIP numa máquina virtual, use o roteiro
[Instalação em VM](#instalacao-vm). Os passos abaixo descrevem a instalação
por clone Git.

#### Pré-requisitos

- Debian 12 ou 13 (instalação mínima)
- Duas interfaces de rede: uma para a LAN, uma para a WAN (internet)
- Acesso root
- Conexão com a internet

#### Passo a Passo

```bash
# 1. Instalar git e clonar o repositório
apt install -y git
git clone https://github.com/jpfagiani/gwos.git /opt/gwos
cd /opt/gwos/install

# 2. Executar o instalador
bash install.sh
```

O `install.sh` é um atalho para `modulos/instalar-todos.sh` — a instalação foi
desmembrada em módulos, um por servidor (DNS, hora, firewall, proxy, banco,
painel). Instalar tudo de uma vez dá exatamente o mesmo resultado de antes;
a diferença é que agora dá para instalar um servidor de cada vez. Veja a
[seção 1.2](#12-instalação-por-módulos) e [Instalação modular](#modulos).

O instalador pergunta:
- Interface WAN (saída para internet)
- Interface LAN (rede interna)
- IP do gateway (ex: 10.14.29.10)
- Rede LAN (ex: 10.14.29.0/24)
- **Rede secundária (opcional):** IP alias na LAN para rotear entre duas sub-redes  
  Exemplo: GWOS em `10.14.29.10` + alias `172.14.29.254` para alcançar uma rede antiga/outra unidade em `172.14.29.0/24`
- Configuração da WAN (DHCP ou IP estático)

Ao final, exibe a URL e o login. A senha do administrador é pedida (oculta, com confirmação) durante a instalação do módulo do painel.

#### Rede secundária — quando usar

Configure quando o GWOS precisa ser gateway para duas redes diferentes conectadas via switches:

```
Internet → Switch 172.x (outra unidade/legado) → cabo → Switch 10.x → GWOS (10.14.29.10)
```

O instalador cria automaticamente:
- Interface alias `LAN:1` com o IP secundário (ex: `172.14.29.254`)
- Regra nftables para não interceptar tráfego entre as redes
- ACL do Squid para a rede secundária

Nos PCs da rede `172.x`, adicionar rota estática (cmd como admin):
```cmd
route add 10.14.29.0 MASK 255.255.255.0 172.14.29.254 -p
```

> Após a instalação, acesse o painel e **troque a senha** no primeiro login.

#### 1.1 Instalação em máquina real (bare metal)

O instalador detecta sozinho quando está numa máquina física
(`systemd-detect-virt`) e, nesse caso, faz automaticamente:

- habilita o componente **non-free-firmware** do Debian e instala o firmware
  das placas de rede (`firmware-linux`, `firmware-realtek`,
  `firmware-misc-nonfree`) — sem isso, placas Realtek/Broadcom comuns em
  mini-PCs podem nem aparecer ou cair sob carga;
- instala o **microcode** da CPU (Intel ou AMD, conforme o processador);
- desativa o **NetworkManager** se existir (ele briga com o ifupdown pelo
  controle das interfaces);
- **fixa o nome de cada interface pelo MAC** (arquivos
  `/etc/systemd/network/70-gwos-*.link`) — sem isso, uma atualização de
  kernel ou uma placa PCI nova pode renomear `enp1s0` → `enp2s0` e derrubar
  rede, firewall e Squid de uma vez.

Checklist antes de instalar:

1. **BIOS/UEFI:** configure **"Restore on AC Power Loss" = Power On** (o
   gateway precisa voltar sozinho após queda de energia) e desative
   suspensão/sleep. Se o boot travar pedindo teclado, desative "halt on
   keyboard error".
2. **Identifique as portas de rede:** com o cabo da internet em uma porta e
   a LAN na outra, use `ip -br link` (quem tem `UP` tem cabo) ou
   `ethtool -p enp1s0 10` (pisca o LED da porta por 10 s). Anote qual nome
   corresponde a qual porta — o instalador vai perguntar.
3. **Se a placa de rede não aparecer nem no instalador do Debian**, use a
   imagem de instalação que já inclui firmware (padrão a partir do
   Debian 12) ou instale com cabo em outra porta e rode o GWOS — ele
   instala os firmwares que faltam.

Migrando da máquina virtual para a física:

```bash
# Na VM (gera /var/lib/gwos/backups/gwos_backup_<data>.tar.gz):
/opt/gwos/scripts/backup.sh

# Na máquina física, após instalar o GWOS do zero:
/opt/gwos/scripts/restaurar_backup.sh /caminho/do/gwos_backup_<data>.tar.gz
```

> Os **nomes das interfaces mudam** entre a VM e a máquina real
> (ex.: `ens18` → `enp1s0`). Instale o GWOS do zero na física respondendo
> as perguntas do instalador — ele gera todas as configurações com os nomes
> certos — e use o backup só para trazer **banco e listas** (grupos, IPs,
> domínios), não os arquivos de rede.

> **Teste com monitor e teclado conectados** antes de colocar a máquina no
> lugar definitivo. Nunca mexa na rede de um gateway remoto sem um console
> de socorro — se algo der errado na troca de IP, é o console físico que
> salva (use `gwos ip`, nunca `systemctl restart networking`).

#### 1.2 Instalação por módulos

Cada servidor tem sua própria pasta em `modulos/`, com `instalar.sh`,
`verificar.sh` e `desinstalar.sh`. Consulte as seções dos módulos neste guia:

| Módulo | Serviço |
|--------|---------|
| `00-base` | Rede, firmware, `ip_forward`, estado compartilhado |
| `10-banco-mariadb` | Banco de dados |
| `20-dns-bind9` | Servidor DNS com RPZ |
| `25-dns-interno-dnsmasq` | Nomes internos da LAN |
| `30-hora-chrony` | Servidor de hora (NTP) |
| `40-firewall-nftables` | Firewall e NAT |
| `50-proxy-squid` | Proxy HTTP/HTTPS com SSL Bump |
| `60-painel-web` | Painel de administração |

```bash
# Escolher módulo a módulo (recomendado na primeira vez)
bash modulos/instalar-todos.sh --escolher

# Só o servidor DNS, nesta máquina
bash modulos/20-dns-bind9/instalar.sh

# Só os módulos listados
bash modulos/instalar-todos.sh 20-dns-bind9 30-hora-chrony

# Tudo menos a reconfiguração de rede
bash modulos/instalar-todos.sh --pular 00-base

# Diagnóstico de tudo que está instalado
bash modulos/verificar-todos.sh

# Remover um servidor sem tocar nos outros
bash modulos/50-proxy-squid/desinstalar.sh
```

**Quantas placas de rede.** Só o `00-base` e o `40-firewall-nftables` precisam
de duas — são os módulos de gateway, que roteiam de uma interface para a outra.
DNS, nomes internos, hora, proxy, banco e painel funcionam com uma placa só.
Numa máquina de uma interface, o instalador avisa antes de começar e pula os
dois módulos de gateway.

**Como eles funcionam isolados.** Nenhum módulo depende do instalador para
descobrir a rede: quem precisa da LAN, da rede ou do domínio interno lê
`/etc/gwos/gwos.conf`; se o arquivo não existir, ele é criado a partir do que
o sistema já tem — sem tocar em `/etc/network/interfaces`. Só o `00-base`
reconfigura a rede de verdade.

**Como eles se encontram.** Ao terminar, todo módulo roda `gwos-integrar`, que
olha o que existe na máquina e reescreve só os pontos de contato: o firewall
só redireciona 80/443 se houver Squid, o Squid só resolve por `127.0.0.1` se
houver BIND9, o BIND9 só encaminha o domínio interno se houver dnsmasq, e o
chrony libera as redes internas atuais. Por isso a ordem não importa —
instalar o Squid depois do firewall reajusta o firewall sozinho, e remover o
Squid tira os redirecionamentos antes que a LAN fique sem internet.

Só há uma dependência obrigatória: o **painel exige o banco**.

Detalhes completos em [Instalação modular](#modulos).

---

#### Convivência com o Samba e o portal de sistemas

Os três projetos da unidade podem dividir a mesma máquina. Cada um atende numa
porta fixa, igual em qualquer unidade:

| Porta | Portal | Repositório | Quem usa |
|---|---|---|---|
| **80** | `portal-sistemas` | `jpfagiani/portal` | todos os usuários — atalhos |
| **8080** | `portal-gateway` | `jpfagiani/gwos` | administração do gateway |
| **8443** | `portal-samba` | `jpfagiani/smb` | administração dos arquivos |

**Instale nesta ordem: GWOS → smb → portal.** O `bootstrap.sh` do Samba lê
`/etc/gwos/modulos.d` para saber o que já existe na máquina. Invertendo a ordem,
ele não encontra nada e o firewall dele bloqueia as portas do GWOS em silêncio.

Quando os dois estão juntos, **o GWOS é o dono** de três recursos, e os
instaladores dos outros projetos recuam sozinhos:

| Recurso | Arquivo | Por quê |
|---|---|---|
| Firewall | `/etc/nftables.conf` | aqui ficam o NAT, o desvio para o Squid e o forçamento do DNS da LAN |
| Hora | `/etc/chrony/conf.d/gwos.conf` | aqui ficam os `allow` que autorizam a LAN a pedir a hora |
| Rede | `/etc/network/interfaces` | dois donos geram duas definições da mesma placa, e o `ifup` falha no boot |

Para mudar qualquer um deles use as ferramentas do GWOS — nunca o instalador do
outro projeto:

```bash
sudo gwos ip <novo-ip>                                    # endereçamento
sudo gwos-definir NTP_SERVIDORES <ip> && sudo gwos-integrar   # fonte de hora
sudo gwos-gerar-nftables                                  # firewall
```

No `bootstrap.sh` do Samba, com o GWOS já instalado: responda **`127.0.0.1`** no
DNS (é o BIND9 local, e sobrevive a uma troca de IP) e **mantenha** o
endereçamento como está. A pergunta do NTP nem aparece — o GWOS já é o dono do
chrony e o valor viria a ser descartado.

---

### 2. Atualizar sem Reinstalar

```bash
gwos update
```

Faz `git pull` e copia os arquivos para o servidor web sem tocar em configurações.

---

### 3. Painel Web

#### Acesso

- **URL:** `http://IP_DO_GATEWAY:8080` (porta 8080 por convenção — veja [Convivência com o Samba e o portal de sistemas](#convivência-com-o-samba-e-o-portal-de-sistemas))
- **E-mail:** `admin@gwos.local`
- **Senha:** definida durante a instalação e mostrada uma única vez no console.

#### Seções do painel

| Seção | Função |
|-------|--------|
| Dashboard | Acessos recentes do Squid, gráfico de banda RX/TX, estado das interfaces/serviços, carga, memória, disco e uptime |
| Grupos | Criar e gerenciar grupos de IPs (Liberados, Parciais, Bloqueados) |
| IPs | Associar endereços IP a grupos |
| Domínios | Blacklist e whitelist de domínios/sites |
| Horários | Regras de liberação por dia/hora (horário livre, almoço, etc.) |
| NAT 1:1 | Redirecionamento de portas externas para IPs internos |
| DNS | Adicionar nomes internos (ex: `samba.cdpni.local → 10.14.29.11`) |
| Relatórios | Tráfego por equipamento, grupo exato e interface disponível; bloqueios, sessões encerradas, alertas e dispositivos novos; CSV e impressão/PDF |
| Histórico de tarefas | Acompanhar aplicação de firewall, DNS, Squid e NAT solicitada pelo painel |
| Configurações | Parâmetros do sistema |

As alterações privilegiadas de firewall, DNS, proxy, horários e NAT são enfileiradas. O worker cron as executa como `www-data` usando comandos allowlisted; consulte **Histórico de tarefas** para ver o estado. `Falha`, `timeout` e `não confirmado` não significam sucesso. Em caso de resultado não confirmado, confira o serviço/regras no servidor antes de repetir a ação.

Relatórios CSV têm limite de 50.000 linhas por exportação. Para o perfil operador, IPs, MACs, nomes de equipamentos/usuários, e-mails e detalhes de eventos ficam mascarados/restritos nos relatórios. O tráfego é medido no proxy Squid; não representa fluxos que desviam do proxy. O histórico de sessões começa após a migration 006.

---

### 4. Grupos de IPs e Política de Acesso

Cada IP da rede deve ser cadastrado em um grupo para ter acesso à internet.

| Grupo | Comportamento |
|-------|---------------|
| **Liberados** | Acesso irrestrito à internet |
| **Parciais** | Acesso com restrições: blacklist de domínios e horários aplicados |
| **Bloqueados** | Apenas whitelist (sites obrigatórios/governo) |
| *(sem grupo)* | Bloqueado — nenhum acesso |

#### Adicionar um IP

1. Painel → **Grupos** → selecione o grupo desejado
2. Clique em **Adicionar IP**
3. Informe o endereço IP e descrição

---

### 4.1 Acesso à Internet com Login (portal cativo)

Quem **não está em nenhum grupo de IP** passa a precisar de e-mail institucional
(`@sap.sp.gov.br`) e senha para navegar. IPs que já estão em grupo continuam
exatamente como antes.

**Como funciona.** O proxy é transparente, então ele não pede senha direto no
navegador. Em vez disso, ao abrir qualquer site sem sessão, o Squid redireciona
para `https://<IP do gateway>:8444/acesso`. Depois do login, o IP daquela máquina
fica liberado até a sessão expirar (padrão: 8 horas). O Squid consulta as sessões
pelo helper `/usr/local/sbin/gwos-squid-sessao`, que lê `/var/lib/gwos/sessions/sessoes.txt`
(o portal grava esse arquivo; o Squid não acessa o banco).

**Ativar num servidor já instalado:**

```bash
sudo bash scripts/ativar_acesso_internet.sh
```

Aplica a migração, instala o helper, troca o `squid.conf` (com backup e
**reversão automática** se o Squid reprovar), gera o site HTTPS do portal e agenda o
importador de logs. Pode rodar de novo sem problema.

**Usuário (primeiro acesso):** informa nome e e-mail → recebe um link no webmail
(`webmail.sap.sp.gov.br`, sempre liberado na whitelist) → no link **cria a senha**
(mín. 8 caracteres, letras e números) → faz login. A senha só nasce depois da
confirmação do e-mail, então digitar o e-mail de outra pessoa não adianta.
**Esqueci minha senha:** mesmo caminho, com link novo (vale 30 min, uso único).
O link do cadastro vale 24 h. Cinco senhas erradas bloqueiam a conta por 15 min.

**Sem depender de e-mail (v2.0.1).** Em *Acesso com login* o administrador pode:
- **Cadastrar usuário** digitando nome, e-mail institucional e a **senha inicial** — o usuário já entra confirmado;
- **Senha** (por usuário): define/redefine a senha digitando; encerra as sessões abertas dele;
- **Link**: gera um link de uso único (24 h para cadastro novo, 30 min para redefinição) para repassar ao usuário criar a própria senha.
Se o SMTP estiver fora do ar, o cadastro/“esqueci a senha” do portal avisa o usuário para procurar o administrador, em vez de fingir que enviou.

**E-mail (SMTP).** Configure em *Acesso com login > Envio de e-mail* (ou *Configurações*) as chaves `smtp_host`, `smtp_porta`,
`smtp_seguranca` (`nenhuma`, `starttls` ou `ssl`), `smtp_usuario`, `smtp_senha` e
`smtp_remetente` (padrão: servidor `10.14.5.16`, porta 25, sem autenticação). Teste em
*Acesso com login > Enviar e-mail de teste*. Sem SMTP funcionando ninguém consegue
concluir o cadastro. Com STARTTLS ou TLS direto, use o nome presente no certificado
e instale a CA institucional no repositório de confiança do Debian, quando aplicável.

**Isentar um computador da senha.** Em *Grupos*, crie um grupo do tipo **Isento de
login** e adicione o IP. Ele navega livremente e **continua registrado** no log.
> O tipo **Liberado** é diferente: desvia do proxy, não pede senha e **não deixa
> registro** de acesso. Para ter log de todos, use *Isento*.

**Registro de acessos.** *Acesso com login > Registro de acessos* mostra data/hora,
IP da máquina, usuário (nome e e-mail) e site, com filtros e exportação em CSV. O
`access.log` do Squid é importado a cada minuto para o banco (retenção de 365 dias;
ajuste com `ACESSOS_RETENCAO_DIAS`). IPs isentos aparecem como "IP isento de login".

**Administração.** *Acesso com login* lista as sessões ativas (botão **Derrubar**) e os
usuários (ativar/desativar/excluir). Desativar um usuário encerra o acesso dele.

**Limitações a conhecer**
- A sessão é **por IP**: num computador compartilhado, quem entrou por último vale
  para todos até sair (botão *Sair* na página de login) ou expirar. Com IP fixo por
  máquina funciona bem; a cada troca de IP (DHCP) é preciso entrar de novo.
- O redirecionamento em HTTPS só abre a página de login sem aviso de certificado nos
  computadores que **confiam na CA do GWOS** (a mesma do SSL Bump). O Windows e o
  Android costumam abrir o login sozinho ao detectar o portal cativo (sonda HTTP).
- A **blacklist de domínios também vale no DNS (RPZ do BIND9)** para todos, inclusive
  usuários logados. Para liberar um site de fato, remova-o da blacklist.
- Porta do portal: `ACESSO_PORTA` (padrão 8444). Se o servidor de arquivos (portal-samba
  usa 8443) rodar na mesma máquina, as portas não conflitam.

### 5. Blacklist e Whitelist de Domínios

#### Blacklist (bloquear sites)

Painel → **Domínios** → **Blacklist** → Adicionar domínio

Depois clique em **Aplicar** para atualizar o Squid e o DNS (BIND9 RPZ).

Exemplos:
```
facebook.com
youtube.com
tiktok.com
```

#### Whitelist (liberar sempre, mesmo para Bloqueados)

Painel → **Domínios** → **Whitelist** → Adicionar domínio

Usado para sites de governo, sistemas obrigatórios, etc. IPs do grupo Bloqueados conseguem acessar apenas esses sites.

#### Aplicar mudanças no Squid

Após adicionar/remover domínios, clique em **Aplicar** no painel.  
Ou via terminal:

```bash
sudo /opt/gwos/scripts/gerar_squid_dominios.sh
```

---

### 6. Horários (Horário Livre)

Permite que IPs do grupo **Parciais** acessem sites da blacklist em horários determinados.

#### Criar uma regra de horário livre

1. Painel → **Horários** → **Nova Regra**
2. Nome: ex. `Livre almoço`
3. Ação: `Permitir`
4. Horário: `11:00` até `13:00`
5. Dias: Seg a Sex
6. Grupo: deixar em branco (aplica a todos os Parciais)
7. Salvar → o Squid é atualizado automaticamente

#### Horários padrão (pré-configurados na instalação)

| Nome | Horário | Dias |
|------|---------|------|
| Livre almoço (seg-sex) | 11:00–13:00 | Seg–Sex |
| Livre sábado | 08:00–17:00 | Sábado |
| Livre domingo | 08:00–17:00 | Domingo |

#### Forçar atualização das regras no Squid

```bash
sudo /opt/gwos/scripts/gerar_squid_acl.sh
```

---

### 7. NAT 1:1 (Redirecionamento de Portas)

Painel → **NAT** → **Adicionar**

Exemplo: redirecionar porta 8080 da internet para o servidor Samba (porta 80):
- IP externo: `0.0.0.0` (qualquer)
- Porta externa: `8080`
- IP interno: `10.14.29.11`
- Porta interna: `80`

Ativar a regra após criar.

---

### 8. DNS Interno

Permite acessar servidores internos por nome em vez de IP.

```bash
# Adicionar
gwos dns add samba 10.14.29.11

# Listar
gwos dns list

# Atualizar IP
gwos dns update samba 10.14.29.12

# Remover
gwos dns del samba
```

Os nomes ficam disponíveis no domínio `.cdpni.local`:
- `samba.cdpni.local → 10.14.29.11`

Propagação em até 60 segundos.

---

### 8.1 Trocar o IP do Gateway

Use **sempre** o comando dedicado — nunca edite `/etc/network/interfaces` na mão:

```bash
# Trocar apenas o IP (mantém a rede atual)
sudo gwos ip 10.14.29.20

# Trocar IP e rede
sudo gwos ip 172.14.29.1 172.14.29.0/24
```

O comando faz, nesta ordem:

1. Valida o IP e confere que ele pertence à rede informada
2. Gera o novo `/etc/network/interfaces` em arquivo temporário e **valida a sintaxe com `ifquery` antes de gravar** (se inválido, nada é alterado)
3. Cria backup do arquivo original (`/etc/network/interfaces.bak.<data>`)
4. **Adiciona** o novo IP na interface antes de remover o antigo — a interface nunca fica sem IP e a sessão não cai
5. Atualiza banco (`ip_gateway`, `rede_lan`), `.env`, BIND9, Squid e regenera o nftables (cada um validado com sua ferramenta antes do reload)
6. Só então remove o IP antigo

O comando **não** executa `systemctl restart networking` — a mudança vale imediatamente via `ip addr` e persiste no reboot pelo arquivo já validado.

Depois da troca, se a **rede** mudou:
- Atualize gateway/DNS nos clientes da LAN
- Atualize hosts do DNS interno: `gwos dns update <host> <novo_ip>`

Se algo der errado, o próprio comando mostra o caminho do backup para restaurar.

---

### 9. Comando `gwos` (CLI)

Ferramenta de administração via terminal. Disponível após a instalação.

```bash
gwos <comando> [opções]
```

#### Referência rápida

| Comando | Descrição |
|---------|-----------|
| `gwos status` | Status de todos os serviços |
| `gwos reload all` | Recarrega todos os serviços |
| `gwos reload squid` | Recarrega só o Squid |
| `gwos reload nginx` | Recarrega só o Nginx |
| `gwos diag` | Diagnóstico completo do sistema |
| `gwos ip <novo_ip> [rede]` | Troca o IP do gateway com validação e backup |
| `gwos update` | Atualiza o código via git |
| `gwos log tail [N]` | Últimas N linhas do log do Squid (padrão: 50) |
| `gwos log live` | Monitorar acessos em tempo real |
| `gwos log top [N]` | Top domínios acessados hoje |
| `gwos log erros` | Acessos negados recentes |
| `gwos nat list` | Listar regras NAT |
| `gwos nat add <ext> <int>` | Adicionar regra NAT |
| `gwos nat ativar <id>` | Ativar regra NAT |
| `gwos nat desativar <id>` | Desativar regra NAT |
| `gwos grupo list` | Listar grupos de IP |
| `gwos grupo ips <id>` | Ver IPs de um grupo |
| `gwos grupo add-ip <id> <ip>` | Adicionar IP ao grupo |
| `gwos dominio list` | Listar domínios |
| `gwos dominio add <dom> blacklist` | Adicionar à blacklist |
| `gwos dominio del <dom>` | Remover domínio |
| `gwos dns list` | Listar hosts DNS internos |
| `gwos dns add <host> <ip>` | Adicionar host DNS |
| `gwos dns del <host>` | Remover host DNS |
| `gwos backup criar` | Criar backup agora |
| `gwos backup listar` | Listar backups disponíveis |
| `gwos backup restaurar <arquivo>` | Restaurar backup |

#### Gerenciar senha do painel

```bash
# Redefinir pedindo a senha no terminal (sem eco, com confirmação)
gwos senha admin@gwos.local

# Resetar para senha personalizada
gwos senha admin@gwos.local minhaSenha123

# Listar admins cadastrados
gwos senha listar

# Desbloquear conta bloqueada por tentativas excessivas
gwos desbloqueio admin@gwos.local
```

---

### 10. Serviços do Sistema

| Serviço | Função |
|---------|--------|
| `nginx` | Servidor web (painel PHP) |
| `php8.4-fpm` | PHP para o painel |
| `squid` | Proxy HTTP/HTTPS com SSL Bump |
| `named` (BIND9) | DNS com RPZ (bloqueio por domínio) |
| `gwos-dnsmasq` | DNS interno para `.cdpni.local` |
| `nftables` | Firewall e NAT |
| `mariadb` | Banco de dados do painel |
| `chrony` | Servidor de hora (NTP) da LAN |

```bash
# Ver status de todos
gwos status

# Diagnóstico módulo a módulo (mais detalhado que o status)
bash /opt/gwos/modulos/verificar-todos.sh

# Reiniciar serviço individualmente
systemctl restart squid
systemctl restart nginx
systemctl restart named
```

#### Arquivos de estado dos módulos

| Caminho | Conteúdo |
|---------|----------|
| `/etc/gwos/gwos.conf` | Interfaces, redes, IP do gateway, domínio interno, portas |
| `/etc/gwos/db.conf` | Credenciais do banco (0600) |
| `/etc/gwos/modulos.d/` | Um arquivo por módulo instalado |
| `/usr/local/sbin/gwos-integrar` | Re-costura as integrações entre os módulos |
| `/usr/local/sbin/gwos-gerar-nftables` | Regera as regras de firewall |
| `/usr/local/sbin/gwos-gerar-dnsmasq` | Regera a configuração do dnsmasq |

---

### 11. SSL Bump (Inspeção HTTPS)

O GWOS inspeciona tráfego HTTPS para aplicar a blacklist em conexões seguras.  
Para evitar alertas de certificado nos navegadores dos clientes:

1. Baixe o certificado CA: `http://IP_GATEWAY:8080/gwos-ca.crt`
2. Instale como "Autoridade Certificadora Confiável" no navegador ou no Windows

---

### 12. Logs e Diagnóstico

```bash
# Diagnóstico completo
gwos diag

# Acessos em tempo real
gwos log live

# Últimos 100 acessos
gwos log tail 100

# Top 20 domínios hoje
gwos log top 20

# Só bloqueados
gwos log erros

# Log bruto do Squid
tail -f /var/log/squid/access.log

# Log do Nginx
tail -50 /var/log/nginx/error.log

# Log do PHP
tail -50 /var/log/php8.4-fpm.log
```

---

### 13. Problemas Comuns

#### Painel não abre / ERR_CONNECTION_REFUSED

```bash
systemctl status nginx
systemctl status php8.4-fpm
gwos status
```

#### "Sem registros recentes" no dashboard

www-data precisa estar no grupo `proxy` para ler o log do Squid:

```bash
usermod -aG proxy www-data
systemctl restart php8.4-fpm
```

#### Site bloqueado fora do horário incorreto

Verificar se as regras de horário foram geradas:

```bash
cat /etc/squid/conf.d/gwos_horarios.conf
```

Se estiver vazio, gerar manualmente:

```bash
sudo /opt/gwos/scripts/gerar_squid_acl.sh
```

#### DNS não resolve domínios externos

```bash
systemctl status named
# Testar
dig google.com @127.0.0.1
```

#### Conta do painel bloqueada

```bash
gwos desbloqueio admin@gwos.local
gwos senha
```

#### Squid não inicia

```bash
squid -k parse          # verifica erros de configuração
journalctl -u squid -n 50
```

<a id="modulos"></a>

## Instalação modular

Cada servidor do GWOS virou um módulo independente. Você pode instalar só o
DNS numa máquina, só o proxy em outra, ou todos no mesmo gateway — o resultado
é o mesmo de antes, mas dá para montar por partes.

```bash
# Escolher módulo a módulo (recomendado na primeira vez)
bash modulos/instalar-todos.sh --escolher

# Tudo, na ordem — gateway completo
bash modulos/instalar-todos.sh

# Só os que você quer
bash modulos/instalar-todos.sh 20-dns-bind9 30-hora-chrony

# Um servidor isolado
bash modulos/20-dns-bind9/instalar.sh

# Conferir o que está instalado
bash modulos/verificar-todos.sh
```

### Convenção de nomes dos portais

Uma unidade costuma ter mais de um portal web. Todos seguem
`portal-<o que administra>`, sem citar a unidade — o mesmo código serve a
qualquer presídio, e o prefixo comum agrupa os três:

| Portal | Nome de sistema | Porta | Repositório |
|--------|-----------------|-------|-------------|
| Sistemas externos | `portal-sistemas` | **80** | `jpfagiani/portal` |
| Gateway | `portal-gateway` | **8080** | este (`modulos/60-painel-web`) |
| Servidor de arquivos | `portal-samba` | **8443** | `jpfagiani/smb` |

As portas são **fixas em todas as unidades**. Padronizar vale mais que ganhar
a porta 80: quem dá suporte a vários presídios encontra cada portal sempre no
mesmo lugar, e a 80 fica para o portal de sistemas — o único que todos os
usuários acessam, e o único que se digita sem porta na barra de endereços.

O instalador só propõe outra porta se a 8080 estiver ocupada por algo que não
dá para mover.

```bash
systemctl status 'portal-*'      # os três de uma vez
```

O nome de **acesso** é outra coisa, e deve ser curto — é o que as pessoas
digitam:

```bash
gwos dns add gateway  10.14.29.15
gwos dns add samba    10.14.29.11
gwos dns add sistemas 10.14.29.8
```

Para `http://gateway` funcionar sem o domínio completo, entregue o sufixo de
busca aos clientes pela opção 15 do DHCP (`domain-name = cdpni.local`).

### Perfis de unidade

O que muda de uma unidade prisional para outra — DNS interno, servidor de hora,
domínios da intranet — não fica no código: fica em `modulos/perfis/`.

```bash
ls modulos/perfis/
# cdpni.conf  exemplo.conf.modelo
```

O módulo `00-base` lista os perfis e pergunta qual usar; escolhido um, ele
preenche os padrões das perguntas seguintes. Para uma unidade nova:

```bash
cp modulos/perfis/exemplo.conf.modelo modulos/perfis/minha-unidade.conf
# edite os valores e rode a instalação — o perfil aparece na lista
```

Um perfil define:

| Chave | O que é |
|-------|---------|
| `DOMINIO_LOCAL` | Domínio dos nomes da LAN |
| `DNS_FORWARDERS` | Resolvers para tudo que não é domínio interno |
| `ZONAS_INTERNAS` | `dominio:ip` dos domínios com DNS próprio |
| `NTP_SERVIDORES` | Servidor de hora da rede |
| `NTP_POOL` | Pool público de reserva |

Sem perfil, o instalador pergunta cada um — com padrões neutros (resolvers
públicos, sem zonas internas, só o pool de hora). Nada é específico de
unidade nenhuma no código.

### Quantas placas de rede você precisa

| Módulos | Placas |
|---------|--------|
| `00-base` e `40-firewall-nftables` | **duas** — são os módulos de gateway, que roteiam de uma para a outra |
| DNS, nomes internos, hora, proxy, banco, painel | **uma** basta |

Numa máquina de uma placa só, o `instalar-todos.sh` avisa antes de começar e
pula os dois módulos de gateway. O `00-base` executado direto também detecta e
sai sem alterar nada, dizendo quais módulos usar no lugar.

---

### Os módulos

| Pasta | Serviço | O que instala |
|-------|---------|---------------|
| `00-base` | — | Firmware, microcode, `/etc/network/interfaces`, `ip_forward`, estado compartilhado |
| `10-banco-mariadb` | `mariadb` | Banco `gwos`, usuário, schema, credenciais em `/etc/gwos/db.conf` |
| `20-dns-bind9` | `named` | DNS recursivo da LAN, RPZ (bloqueio por domínio), forward zones do governo |
| `25-dns-interno-dnsmasq` | `gwos-dnsmasq` | Nomes internos da LAN em `127.0.0.1:5353` |
| `30-hora-chrony` | `chrony` | Servidor de hora (NTP) para o gateway e para a LAN |
| `40-firewall-nftables` | `nftables` | Firewall, NAT/masquerade e os redirecionamentos de proxy e DNS |
| `50-proxy-squid` | `squid` | Proxy 3127/3128/3129, SSL Bump e a CA |
| `60-painel-web` | `nginx`, `php8.4-fpm` | Painel, comando `gwos`, sudoers e cron |

Ordem recomendada: a numérica. Nenhuma dependência é obrigatória: sem o
`10-banco-mariadb` o painel sobe em modo leve, com as telas cujos dados vivem
em arquivo.

### Telas no painel

Com o `60-painel-web` instalado, cada módulo abaixo ganha sua própria tela. A
lista de módulos é lida de `/etc/gwos/modulos.d` a cada carregamento —
instalou pelo terminal, a seção aparece na próxima página.

| Módulo | Tela | O que dá para fazer |
|--------|------|---------------------|
| `20-dns-bind9` | DNS | Editar resolvers, testar cada um, criar e remover zonas, resolver nome ao vivo |
| `25-dns-interno` | Nomes internos | Vincular nome a IP, alterar, remover |
| `30-hora-chrony` | Hora | Trocar servidores NTP, ver sincronização e quem consulta |
| `40-firewall-nftables` | Firewall | Ver regras em vigor e por que cada uma está lá; regerar |
| `50-proxy-squid` | Proxy | Portas, estado do SSL Bump, listas incluídas, últimos acessos |

Nenhuma tela escreve em `/etc` direto. Tudo passa por `gwos-definir`,
`gwos-zona` ou `gwos-servico`, que validam antes de aplicar — e o firewall não
tem edição de regra crua de propósito: as regras são derivadas, e um formulário
criaria uma segunda fonte de verdade que a primeira regeração apagaria.

---

### Como cada módulo funciona sozinho

Nenhum módulo depende do instalador para descobrir a rede. Quem precisa saber
qual é a LAN, a rede ou o domínio interno lê `/etc/gwos/gwos.conf`; se o
arquivo não existir, `modulos/comum/lib.sh` detecta tudo a partir do sistema
(rota padrão, IPs das interfaces) e o cria — **sem tocar em
`/etc/network/interfaces`**. Só o `00-base` reconfigura a rede de verdade.

O que cada um faz quando é o único instalado:

- **20-dns-bind9** — resolver completo para a LAN. Bloqueio por domínio
  editando `/etc/bind/db.rpz.gwos` à mão.
- **25-dns-interno** — responde nomes internos em `127.0.0.1:5353`
  (`dig @127.0.0.1 -p 5353 samba.cdpni.local`). A LAN só alcança esses nomes
  com o BIND9 junto.
- **30-hora-chrony** — servidor NTP funcional para a LAN, inclusive com a
  internet fora (`local stratum 10`).
- **40-firewall-nftables** — gateway com NAT e firewall; a LAN navega direto,
  sem proxy.
- **50-proxy-squid** — proxy explícito na porta 3127. Sem o painel, as listas
  de grupos ficam vazias e a regra `http_access deny all` bloqueia todo mundo;
  o instalador mostra a linha a trocar para liberar a LAN.
- **10-banco** e **60-painel** — precisam um do outro; os demais são opcionais.

---

### Como eles se encontram

Cada módulo, ao terminar, roda `gwos-integrar` (instalado em
`/usr/local/sbin/`). Esse script olha o que existe na máquina naquele momento
e reescreve **só os pontos de contato**:

| Ponto de contato | Arquivo gerado | Condição |
|------------------|----------------|----------|
| BIND9 → upstream | `/etc/bind/named.conf.gwos-forwarders` | lista de `DNS_FORWARDERS` do `gwos.conf` |
| BIND9 → dnsmasq | `/etc/bind/named.conf.gwos-integracao` | domínio interno encaminhado só se o módulo 25 existir |
| Squid → resolver | `/etc/squid/conf.d/gwos_integracao.conf` | `127.0.0.1` com BIND9; resolvers externos sem ele |
| Squid → redes | `/etc/squid/conf.d/gwos_redes.conf` | ACLs vindas de `gwos.conf` (cobre faixas fora do RFC 1918) |
| nftables | `/etc/nftables.conf` | redireciona 80/443 só se houver Squid; DNS só se houver BIND9 |
| chrony | `/etc/chrony/conf.d/gwos.conf` | fontes de `NTP_SERVIDORES`/`NTP_POOL` + libera as redes internas atuais |

Por isso a ordem não trava nada: instale o Squid depois do firewall e o
firewall se reajusta sozinho; remova o Squid e os redirecionamentos somem
antes que a LAN fique sem internet.

Estado e registro:

```
/etc/gwos/gwos.conf        parâmetros de rede compartilhados
/etc/gwos/db.conf          credenciais do banco (0600)
/etc/gwos/modulos.d/<nome> um arquivo por módulo instalado
/etc/gwos/lib.sh           cópia da biblioteca comum
/usr/local/sbin/gwos-integrar        re-costura tudo
/usr/local/sbin/gwos-definir         altera uma chave do gwos.conf, com validação
/usr/local/sbin/gwos-zona            zonas de encaminhamento do BIND9
/usr/local/sbin/gwos-servico         lê e recarrega serviços (par ação/módulo fixo)
/usr/local/sbin/gwos-gerar-nftables  regera o firewall
/usr/local/sbin/gwos-gerar-dnsmasq   regera o dnsmasq
```

O `gwos-definir` é o único caminho de escrita que o painel web tem no
`gwos.conf`: lista fechada de chaves, validador por chave, e `gwos-integrar` no
final. Interfaces, IP do gateway e rede ficam de fora de propósito — trocar IP
é `gwos ip`, que valida com `ifquery` e põe o IP novo antes de tirar o antigo.

```bash
gwos-definir --listar
gwos-definir DNS_FORWARDERS "8.8.8.8 1.1.1.1"
```

---

### Comandos por módulo

Todo módulo tem os mesmos três scripts:

```bash
bash modulos/<modulo>/instalar.sh      # instala e integra
bash modulos/<modulo>/verificar.sh     # diagnostica (sai 1 se houver problema)
bash modulos/<modulo>/desinstalar.sh   # remove e reintegra o que sobrou
```

Alguns aceitam opções:

```bash
bash modulos/10-banco-mariadb/instalar.sh --recriar   # zera o banco
bash modulos/instalar-todos.sh --pular 00-base        # tudo menos a rede
bash modulos/instalar-todos.sh 20-dns-bind9 50-proxy-squid
bash modulos/verificar-todos.sh --todos
```

---

### Copiar um módulo para outra máquina

Leve a pasta do módulo **e a pasta `comum/`** — é lá que está a biblioteca:

```bash
scp -r modulos/comum modulos/20-dns-bind9 root@outra-maquina:/tmp/gwos-dns/
ssh root@outra-maquina 'bash /tmp/gwos-dns/20-dns-bind9/instalar.sh'
```

Dois módulos precisam do repositório completo: o `10-banco-mariadb`
(`database/schema.sql`) e o `60-painel-web` (`app/`, `public/`, `scripts/`).

---

### Desinstalar

```bash
bash modulos/50-proxy-squid/desinstalar.sh   # um servidor
bash modulos/desinstalar-todos.sh            # tudo
```

Pergunta **uma vez** e depois vai até o fim, sem confirmação a cada passo.

**Pacotes compartilhados não são removidos.** Antes de desinstalar qualquer
pacote, o script verifica se outra coisa na máquina depende dele — e, se
depender, nem oferece: mantém e explica na tela.

| Pacote | Mantido quando |
|--------|----------------|
| `nginx` | há outros sites em `/etc/nginx/sites-enabled` |
| `php*` | há outros sites do nginx ou do Apache |
| `mariadb-server` | existe outro banco além do `gwos` |
| `dnsmasq` | o libvirt usa dnsmasq nas redes virtuais |
| `nftables` | Docker ou libvirt estão instalados |
| `chrony` | sempre — é o relógio da máquina |
| qualquer um | a remoção arrastaria outros pacotes junto |

O serviço também é poupado: se o nginx ainda serve outro site, o desinstalador
remove só o vhost do GWOS e **recarrega** em vez de parar.

O que nunca é apagado: os backups em `/var/lib/gwos/backups` e as zonas em
`/etc/bind/named.conf.zonas-locais`. São seus dados, não resíduo — o script
mostra o caminho e o comando para apagar, se você quiser.

### Reinstalar / reaplicar

Os instaladores são reexecutáveis. O que é preservado numa reinstalação:

- banco de dados (a menos de `--recriar`)
- CA do SSL Bump (os clientes não precisam reinstalar o certificado)
- zona RPZ com os bloqueios já aplicados
- senha do painel, se já tiver sido trocada

O que é sempre regravado: `squid.conf`, `named.conf.*`, `/etc/nftables.conf`,
`/etc/dnsmasq.d/gwos.conf` e a configuração do Nginx — com backup `.bak.<data>`
quando o arquivo já existia.

<a id="modulo-00-base"></a>

## 00-base — rede e preparação da máquina

Único módulo que reconfigura a rede. Os outros apenas **leem** os parâmetros
que ele grava.

### O que faz

- Pergunta o nome do servidor (hostname) e acerta o `/etc/hosts` — sem a
  entrada `127.0.1.1` o `sudo` demora segundos a cada comando
- Pergunta o perfil da unidade, o domínio, os resolvers e o servidor de hora
- No modo gateway: WAN, LAN, rede e rede secundária
- Máquina física: firmware de placas de rede, microcode da CPU, desativa o
  NetworkManager e fixa o nome das interfaces pelo MAC
  (`/etc/systemd/network/70-gwos-*.link`)
- Gera `/etc/network/interfaces` (com backup do anterior)
- Aplica os IPs com `ip addr` — **não** reinicia o `networking`, para não
  derrubar a sessão SSH
- Liga o encaminhamento de pacotes em `/etc/sysctl.d/90-gwos-base.conf`
- Grava `/etc/gwos/gwos.conf`

### Dois modos: gateway e servidor

O módulo detecta quantas placas de rede a máquina tem e se ajusta:

| Modo | Quando | O que pergunta |
|---|---|---|
| **gateway** | duas ou mais placas, e você confirma | WAN, LAN, rede interna, rede secundária, `ip_forward` |
| **servidor** | uma placa só, ou você recusa o papel de gateway | interface, endereçamento (manter/fixo/DHCP) — sem roteamento |

Nos dois modos ele pergunta nome do servidor, domínio, perfil da unidade,
resolvers e servidor de hora.

### Instale-o sempre — inclusive num servidor de uma placa

É ele quem grava o `/etc/gwos/gwos.conf`. **Sem esse arquivo, cada módulo
seguinte adivinha a rede sozinho — e adivinha errado.** O sintoma real, numa
máquina de uma placa:

```
[!] Sem /etc/gwos/gwos.conf — parâmetros detectados automaticamente:
    WAN=enp0s3  LAN=enp0s3  rede=10.0.2.0/24  gateway=10.0.2.15
```

WAN e LAN na mesma placa, a rede antiga e o IP da própria máquina como gateway.
O firewall gerado a partir disso descarta o tráfego da LAN e não encaminha nada.

Um servidor só de DNS, hora, proxy ou painel também precisa dele — o modo
`servidor` existe exatamente para isso e não toca no roteamento.

```bash
bash instalar.sh
```

### Cancelar é diferente de errar

No resumo final:

| Resposta | O que acontece |
|---|---|
| `s` | aplica |
| `n` | **refaz as perguntas**, com as respostas anteriores como padrão |
| `c` | cancela e sai com código 3 — o `instalar-todos.sh` interrompe a instalação inteira, em vez de seguir para módulos que dependem deste |

### O que é validado antes de gravar

O `/etc/network/interfaces` é gerado a partir das respostas, e um valor inválido
ali derruba a placa **no boot seguinte** — durante a instalação o `ip addr` ainda
funciona e o erro passa despercebido. Por isso:

- IP e máscara: octetos 0–255, prefixo 0–32, máscara contígua (`255.0.255.0` é recusada)
- gateway: precisa ser um vizinho na mesma rede do IP; loopback, `0.0.0.0` e o
  próprio endereço da máquina são recusados
- gateway vazio é aceito, com aviso, e a linha simplesmente não vai para o
  arquivo — escrever `gateway` sem valor faz o `ifup` abortar a interface inteira
- o IP da LAN precisa pertencer à rede declarada

### Depois

Para trocar o IP use sempre `gwos ip <novo_ip> [rede]` — ele valida, faz
backup e recarrega os serviços. Nunca `systemctl restart networking` num
gateway remoto.

### Verificação

```bash
bash verificar.sh
```

Confere as interfaces, o IP do gateway, o `ip_forward` e a rota padrão.

<a id="modulo-10-banco-mariadb"></a>

## 10-banco-mariadb — banco de dados

Fonte de grupos de IPs, domínios, horários, NAT 1:1 e relatórios. É de onde o
painel lê e é o que alimenta Squid, BIND9 e nftables.

### O que faz

- Instala o MariaDB
- Cria o banco `gwos`, o usuário `gwos` com senha aleatória e carrega
  `database/schema.sql` + as migrações de `database/migrations/`
- Grava as credenciais em `/etc/gwos/db.conf` (0600) e no `.env` do projeto
- Sincroniza a tabela `configuracoes` com os parâmetros de rede atuais

### Instalação

```bash
bash instalar.sh              # preserva o banco se já existir
bash instalar.sh --recriar    # APAGA e recria do zero
```

Precisa do repositório completo (usa `database/schema.sql`).

### Senha do painel

O schema não cria credenciais administrativas. O módulo `60-painel-web`
provisiona o primeiro administrador com uma senha aleatória de uso inicial,
exibida uma única vez no console. Contas já existentes são preservadas; uma
credencial legada de fábrica é rotacionada no primeiro upgrade do painel.

### Verificação

```bash
bash verificar.sh
```

Testa o serviço, a conexão com as credenciais salvas e a contagem de tabelas.

<a id="modulo-20-dns-bind9"></a>

## 20-dns-bind9 — servidor DNS da rede

BIND9 como resolver recursivo da LAN, com bloqueio de domínios por RPZ.

### O que faz

- Instala `bind9`, `bind9-utils` e `dnsutils`
- `named.conf.options`: `allow-query { localhost; localnets; }` (sobrevive a
  trocas de IP) e a diretiva **`response-policy`** que ativa a RPZ
- `named.conf.local`: zona RPZ, forward zones dos DNS internos do governo e o
  `include` do arquivo de integração
- Cria `/var/log/named` e aponta `/etc/resolv.conf` do gateway para `127.0.0.1`

> **Correção em relação ao instalador antigo:** a zona `rpz.gwos` era
> declarada mas nunca ativada — faltava `response-policy` em
> `named.conf.options`, então o bloqueio de domínios por DNS não surtia
> efeito. Agora está ativo.

### Resolvers upstream

Vêm de `DNS_FORWARDERS` em `/etc/gwos/gwos.conf`; o `gwos-integrar` transforma
a lista em `/etc/bind/named.conf.gwos-forwarders`, incluído pelo
`named.conf.options`. Padrão:

```
DNS_FORWARDERS="10.14.8.20 10.14.8.16 10.1.6.222 8.8.8.8 8.8.4.4 1.1.1.1"
```

Para mudar, edite o `gwos.conf` e rode `gwos-integrar` — não mexa no
`named.conf.options`.

#### Duas coisas que valem saber sobre essa lista

**A ordem é uma dica, não uma regra.** O BIND escolhe o forwarder pelo tempo de
resposta medido, não pela posição na lista. Na prática os internos ganham por
serem mais perto, mas não conte com isso.

**Falha para o próximo só em timeout ou SERVFAIL.** `NXDOMAIN` é uma resposta
válida — se um resolver interno disser "esse domínio não existe" para um site
da internet, o BIND aceita e não tenta os públicos. Por isso o `verificar.sh`
testa cada forwarder resolvendo `google.com` e acusa os que falharem.

Se algum dos internos não resolver nomes externos, tire-o da lista global e
deixe só os públicos — os domínios do governo continuam funcionando, porque
estão fixados por zona:

```
DNS_FORWARDERS="8.8.8.8 8.8.4.4 1.1.1.1"
```

#### Domínios internos do governo

Não passam pela lista global: têm encaminhamento fixo por zona em
`config/named.conf.local`, o que é determinístico e não depende de qual
resolver respondeu mais rápido.

| Zona | DNS interno |
|------|-------------|
| `cartoriosap.sp.gov.br` | 10.1.6.222 |
| `policiapenal.sp.gov.br` | 10.14.8.20 |
| `prodesp.sp.gov.br` | 10.1.6.222 |

Para acrescentar outro domínio interno, copie um desses blocos.

### Nome novo na rede: zona ou host?

Na maioria das vezes **não é zona**. Decida assim:

| Você quer | Faça |
|-----------|------|
| Um nome apontando para um IP da LAN (`portal`, `samba`, uma impressora) | `gwos dns add <nome> <ip>` — vira host no domínio interno, servido pelo dnsmasq |
| Mandar um domínio inteiro para outro servidor DNS | zona `type forward` |
| Ser autoridade de um domínio, com vários registros | zona `type master` + arquivo de registros |

#### Criar uma zona

Com o módulo `60-painel-web` instalado, pela tela **DNS** do painel. Ou pelo
terminal:

```bash
gwos-zona listar
gwos-zona adicionar sistema.sp.gov.br "10.1.6.222 10.14.8.16"
gwos-zona remover   sistema.sp.gov.br
```

O `gwos-zona` valida o domínio e os IPs, roda `named-checkconf` **antes** de a
alteração valer e desfaz sozinho se a configuração não passar. É o mesmo
caminho que o painel usa — ele não escreve em `/etc/bind` por conta própria.

> **`ZONAS_INTERNAS` do `gwos.conf` só vale na instalação.** É lida uma vez, por
> este módulo, para criar as zonas iniciais do perfil da unidade. Editar essa
> linha depois **não muda nada** — nem com `gwos-integrar`, que regenera os
> forwarders e o encaminhamento do domínio interno, mas não as zonas (regerá-las
> em bloco apagaria as que você acrescentou à mão). Para mudar uma zona depois da
> instalação, use `gwos-zona`.

Para escrever à mão, use **`/etc/bind/named.conf.zonas-locais`** — o instalador
cria esse arquivo uma vez e nunca mais o toca. O `named.conf.local` **é
sobrescrito** a cada reinstalação do módulo; zona escrita lá se perde.

```bash
cat >> /etc/bind/named.conf.zonas-locais <<'EOF'
zone "exemplo.sp.gov.br" {
    type forward;
    forward only;
    forwarders { 10.1.6.222; };
};
EOF

named-checkconf && rndc reload
dig exemplo.sp.gov.br @127.0.0.1
```

Se a zona for permanente e tiver de valer para toda instalação nova,
acrescente-a a `config/named.conf.local` neste repositório em vez do arquivo
local — assim ela vai junto no git.

### Instalação

```bash
bash instalar.sh
```

#### Antes de instalar em um servidor que já existe

O instalador aborta se a porta 53 estiver ocupada, mas vale conferir antes:

```bash
ss -lnup | grep :53
```

- **Samba como controlador de domínio (AD DC)** tem DNS próprio na 53. Não
  instale o BIND9 nessa máquina — use outra para o DNS. Samba como servidor de
  arquivos (membro ou standalone) não usa a 53 e não dá conflito.
- **systemd-resolved** ocupa a 53 em `127.0.0.53`: `systemctl disable --now systemd-resolved`.

Se o `/etc/resolv.conf` estiver imutável (`chattr +i`, comum em servidor para o
DHCP não sobrescrever), o módulo detecta, não força e imprime os três comandos
para você trocar à mão.

### Sozinho

Resolver completo para a LAN. Os bloqueios podem ser editados à mão em
`/etc/bind/db.rpz.gwos` (duas linhas por domínio: `dominio.` e `*.dominio.`),
seguidos de `rndc reload`.

### Com os outros

- **25-dns-interno**: o domínio interno passa a ser encaminhado ao dnsmasq
- **10 + 60**: a RPZ passa a ser gerada do banco por
  `scripts/aplicar_bind9_rpz.sh`
- **40-firewall**: todo DNS da LAN é forçado para cá, impedindo bypass da RPZ

### Verificação

```bash
bash verificar.sh
```

Confere o serviço, o `named-checkconf`, a presença do `response-policy` e
resolve `google.com` por `127.0.0.1`.

<a id="modulo-25-dns-interno-dnsmasq"></a>

## 25-dns-interno-dnsmasq — nomes internos da LAN

Resolve nomes como `samba.cdpni.local` a partir do `/etc/hosts` do gateway.

### O que faz

- Instala o `dnsmasq` e **desativa o serviço padrão** (ele brigaria pela
  porta 53 com o BIND9)
- Cria a unit própria `gwos-dnsmasq`, escutando em `127.0.0.1:5353`
- Gera `/etc/dnsmasq.d/gwos.conf` a partir de
  `config/dnsmasq-gwos.conf.modelo`, substituindo domínio e porta pelos
  valores de `/etc/gwos/gwos.conf`
- Instala `/usr/local/sbin/gwos-gerar-dnsmasq`, que refaz essa geração sempre
  que o domínio ou a porta mudarem

### Instalação

```bash
bash instalar.sh
```

### Cadastrar nomes

```bash
gwos dns add samba 10.14.29.11      # requer o módulo 60-painel-web
gwos dns list
gwos dns update samba 10.14.29.12
gwos dns del samba
```

Sem o painel, edite `/etc/hosts` e rode `systemctl reload gwos-dnsmasq`.
Propagação em até 60 s (TTL baixo).

### Sozinho

Responde apenas no loopback:

```bash
dig @127.0.0.1 -p 5353 samba.cdpni.local
```

Para a LAN inteira alcançar esses nomes é preciso o módulo **20-dns-bind9** —
é ele que escuta na porta 53 e encaminha o domínio interno para cá.

### Verificação

```bash
bash verificar.sh
```

<a id="modulo-30-hora-chrony"></a>

## 30-hora-chrony — servidor de hora (NTP)

Mantém o relógio do gateway certo **e** serve a hora para as máquinas da LAN.

### O que faz

- Instala o `chrony` e desativa o `systemd-timesyncd`
- Define o fuso `America/Sao_Paulo`
- `gwos-integrar` grava `/etc/chrony/conf.d/gwos.conf` com:
  - `server <NTP_SERVIDORES> iburst prefer` — a fonte interna da rede
  - `pool <NTP_POOL> iburst` — reserva, para o relógio não derivar se a fonte
    interna cair
  - um `allow <rede>` para cada rede interna de `/etc/gwos/gwos.conf`
  - `local stratum 10`

### Fontes de hora

Vêm de `/etc/gwos/gwos.conf`. Padrão:

```
NTP_SERVIDORES="10.14.8.20"
NTP_POOL="pool.ntp.br"
```

`NTP_SERVIDORES` aceita mais de um, separados por espaço. Depois de mudar,
rode `gwos-integrar`.

Apontar para o servidor interno é o certo quando ele é o controlador de
domínio: a latência é menor e o relógio das estações precisa bater com o dele
de qualquer forma. O pool público fica só como rede de segurança.

> **Diferença em relação ao instalador antigo:** ele só ajustava o pool, sem
> `allow` — o chrony ficava só sincronizando o próprio relógio e recusava os
> clientes da LAN. Agora o gateway é de fato o servidor NTP da rede, e o
> `local stratum 10` faz com que continue servindo a hora mesmo com a internet
> fora.

### Instalação

```bash
bash instalar.sh
```

### Nos clientes

Aponte o servidor NTP para o IP do gateway. No Windows:

```cmd
w32tm /config /manualpeerlist:"10.14.29.10" /syncfromflags:manual /update
```

### Operação

```bash
chronyc sources     # fontes de tempo
chronyc clients     # quem está sincronizando com este gateway
chronyc tracking    # desvio atual do relógio
```

As redes liberadas são reescritas automaticamente quando a rede muda — basta
rodar `gwos-integrar` (o `gwos ip` já faz isso).

### Verificação

```bash
bash verificar.sh
```

<a id="modulo-40-firewall-nftables"></a>

## 40-firewall-nftables — firewall e NAT

Filtro de INPUT/FORWARD, masquerade para a WAN e os redirecionamentos que
levam o tráfego da LAN ao proxy e ao DNS local.

### O que faz

- Instala o `nftables` e desativa o `ufw`, se existir
- Instala `/usr/local/sbin/gwos-gerar-nftables`
- Gera e aplica `/etc/nftables.conf`, sempre validando com `nft -c` antes de
  substituir o arquivo em vigor
- Habilita o serviço no boot

### Regras condicionais

O gerador monta as regras de acordo com o que existe na máquina:

| Situação | Efeito |
|----------|--------|
| Squid instalado | `tcp dport 80 → :3128` e, com SSL Bump, `443 → :3129` |
| Squid ausente | HTTP/HTTPS saem direto, sem redirecionamento |
| BIND9 instalado | todo DNS da LAN é redirecionado para o resolver local |
| BIND9 ausente | DNS da LAN sai direto |
| Banco + painel | delega para `scripts/aplicar_nftables.sh`, que acrescenta os grupos de IPs e o NAT 1:1 do banco |

É isso que evita o pior caso da instalação por partes: redirecionar a LAN
inteira para uma porta onde não há serviço nenhum.

### Redes locais

Todas as sub-redes conectadas à interface LAN (IP principal **e** aliases) são
roteadas, nunca interceptadas — inclusive faixas fora do RFC 1918, como
`172.14.29.0/24`. A lista vem de `ip route show dev <LAN> scope link`, então
sobrevive à regeneração das regras sem depender do banco.

### Instalação

```bash
bash instalar.sh
```

### Operação

```bash
nft list ruleset          # regras em vigor
gwos-gerar-nftables       # regerar (usa o banco, se houver)
GWOS_NFT_BASE=1 gwos-gerar-nftables   # regerar ignorando o banco
```

### Verificação

```bash
bash verificar.sh
```

Além das tabelas e do masquerade, checa a coerência com os outros módulos:
acusa redirecionamento para um Squid que não existe, ou Squid instalado sem
redirecionamento.

<a id="modulo-50-proxy-squid"></a>

## 50-proxy-squid — proxy HTTP/HTTPS com SSL Bump

### Portas

| Porta | Uso |
|-------|-----|
| 3127 | forward-proxy explícito (configurado no navegador) |
| 3128 | HTTP transparente — o firewall redireciona para cá |
| 3129 | HTTPS transparente com SSL Bump |

### CONNECT (proxy explícito) e a porta 8443

Um cliente com o proxy configurado explicitamente (GPO, PAC, campo "Servidor
proxy" nas configurações do Windows) abre HTTPS via `CONNECT`, e o Squid só
autoriza `CONNECT` para portas na ACL `SSL_ports` — **antes** de consultar a
whitelist de domínios. `SSL_ports` cobre `443` e `8443` (a porta do
portal-samba, pela convenção do projeto). Sem a 8443 ali, o portal do Samba
fica inacessível para qualquer cliente que use este Squid como proxy explícito
— cadastrar o domínio na whitelist não ajuda, porque a recusa acontece antes.

Se uma unidade colocar outro serviço HTTPS em porta não padrão, acrescente a
porta em `SSL_ports` (e em `Safe_ports`, para o método normal) neste arquivo.

### O que faz

- Instala `squid-openssl` (cai para `squid` se não houver) e o `sarg` opcional
- Instala `config/squid.conf` em `/etc/squid/squid.conf`
- Cria em `/etc/squid/conf.d/` todas as listas que o `squid.conf` inclui — o
  Squid não sobe se qualquer uma faltar
- Gera a CA do SSL Bump e o banco de certificados dinâmicos, e publica a CA em
  `public/gwos-ca.crt` para download
- Se não houver `security_file_certgen`, comenta as diretivas de SSL e segue
  sem interceptação de HTTPS

Uma CA já existente é **preservada** numa reinstalação — os clientes não
precisam reinstalar o certificado.

### Arquivos gerados por outras peças

| Arquivo | Quem gera |
|---------|-----------|
| `gwos_redes.conf` | `gwos-integrar`, a partir de `/etc/gwos/gwos.conf` |
| `gwos_integracao.conf` | `gwos-integrar` (resolver: BIND9 local ou externo) |
| `gwos_ips_*.txt` | `scripts/aplicar_nftables.sh` (painel) |
| `gwos_whitelist.txt`, `gwos_blacklist.txt`, `gwos_sites_livres.txt` | `scripts/gerar_squid_dominios.sh` |
| `gwos_horarios.conf` | `scripts/gerar_squid_acl.sh` |
| `gwos_tcp_outgoing.conf` | painel (NAT 1:1) |

As ACLs de rede vêm do `gwos_redes.conf` em vez de serem enfiadas no
`squid.conf` com `sed`, como no instalador antigo — por isso cobrem faixas
fora do RFC 1918 e a rede secundária sem edição manual.

### Instalação

```bash
bash instalar.sh
```

### Sozinho

O proxy explícito funciona em `IP_DO_GATEWAY:3127`. Mas sem o painel as listas
de grupos ficam vazias e a última regra, `http_access deny all`, bloqueia todo
mundo. Para usar isolado, libere a LAN:

```bash
sed -i 's/^http_access deny all/http_access allow localnet\nhttp_access deny all/' /etc/squid/squid.conf
squid -k reconfigure
```

### Certificado nos clientes

Instale `http://IP_DO_GATEWAY/gwos-ca.crt` como Autoridade Certificadora
Confiável, senão todo HTTPS interceptado dá alerta de certificado.

### Verificação

```bash
bash verificar.sh
```

Confere o `squid -k parse`, as portas, a validade da CA, a existência de todos
os arquivos incluídos e se o resolver bate com o módulo de DNS instalado.

<a id="modulo-60-painel-web"></a>

## 60-painel-web — painel de administração

Nginx + PHP-FPM 8.4 servindo o painel, mais o comando `gwos`, as permissões
sudo e as tarefas de cron.

### Depende de

- repositório GWOS completo (`app/`, `public/`, `routes/`, `scripts/`)
- **10-banco-mariadb** — opcional; sem ele o painel sobe em modo leve

### Modo completo e modo leve

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

### A tela Módulos

Lê `/etc/gwos/modulos.d/` a cada carregamento: instalou o chrony pelo terminal,
a seção aparece na próxima página. Não há cadastro nem script de atualização.
Mostra o estado dos serviços de cada módulo, o `gwos.conf` em vigor e o comando
de instalação dos que ainda faltam.

### PHP: a versão da distribuição

O módulo detecta qual PHP o Debian oferece e usa esse — Debian 12 traz **8.2**,
Debian 13 traz **8.4**, e as duas servem. Só recorre ao repositório sury.org se
a distribuição for antiga demais (abaixo de 8.1), porque é repositório de
terceiros e uma dependência a mais para quebrar numa atualização.

A versão escolhida vai para `PHP_VERSAO` no `gwos.conf`, e o painel usa isso
para saber qual serviço monitorar. Fixar `php8.4-fpm` faria o painel reportar
"parado" num Debian 12, onde o serviço se chama `php8.2-fpm`.

### O que faz

- Instala Nginx e PHP com as extensões usadas pelo painel
- Publica o site em `public/`, com `try_files` para o front controller
- Gera o `.env` a partir de `/etc/gwos/db.conf`
- Cria `/etc/sudoers.d/gwos` — só para os scripts que existem — e **valida com
  `visudo -c` antes de manter o arquivo**
- Liga `/usr/local/bin/gwos` ao `scripts/gwos-cli.sh`
- Instala o cron: backup diário, parser e importação do Squid, e worker de
  tarefas privilegiadas a cada minuto como `www-data`
- Põe o `www-data` no grupo `proxy` (é o que permite o dashboard ler o
  `access.log`)
- Provisiona o primeiro administrador com senha aleatória de uso inicial; contas existentes são preservadas

### Instalação

```bash
bash instalar.sh
```

### Acesso

| | |
|---|---|
| URL | `http://IP_DO_GATEWAY:8080` (porta 8080 por convenção do projeto) |
| Login | `admin@gwos.local` |
| Senha | Aleatória, exibida uma única vez no console do instalador; troca obrigatória no primeiro acesso |

### Como o painel conversa com os outros módulos

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

As ações que alteram firewall, NAT, domínios ou horários são registradas na
fila persistente do painel e aparecem em **Histórico de tarefas**. O resultado
é conferido após o comando; `failed`, `timeout` e `unconfirmed` não devem ser
tratados como sucesso. O worker depende do cron, das permissões em
`storage/tarefas` e das regras sudoers instaladas por este módulo.

### Verificação

```bash
bash verificar.sh
```

Testa os serviços, o `nginx -t`, o `.env` (inclusive as permissões 600), o
sudoers, o cron e faz um `curl` no painel.

<a id="arquitetura"></a>

## Arquitetura

### Visão de componentes

```text
Navegador administrativo ──> Nginx/PHP-FPM ──> Router ──> Auth/CSRF ──> Controllers/Views
                                                   │                  ├─ MariaDB (opcional no modo leve)
                                                   │                  └─ Serviços/sistema por scripts privilegiados
Cliente LAN ──> Firewall/nftables ──> Squid ──> sessão GWOS ──> Portal público PHP
                                      │                         └─ arquivo de sessão consultado por helper
                                      └─ logs de acesso importados para MariaDB

BIND9/RPZ ── dnsmasq para nomes internos ── LAN
Chrony ── fonte NTP ── clientes LAN
```

### Limites de confiança

- O painel administrativo autentica administradores; o portal autentica usuários finais em tabelas/serviços separados.
- O roteador protege as rotas administrativas por padrão. Rotas do portal e recuperação foram explicitamente listadas como públicas.
- CSRF deve acompanhar toda requisição mutável; mudanças não devem usar GET.
- Scripts de infraestrutura são privilegiados e devem continuar em allowlists fixas, com argumentos validados.
- Saídas de serviço e logs podem conter dados controlados por clientes; escapar antes de renderizar e sanitizar ao registrar.
- Métricas de tráfego vêm de contadores do kernel e precisam de amostras válidas, intervalo e detecção de reinício.

### Dados e estado

- Configurações: `.env` e `/etc/gwos/gwos.conf`/arquivos geridos pelos módulos.
- Dados administrativos e de política: schema SQL e migrations em `database/`.
- Estado de instalação: `/etc/gwos/modulos.d/`.
- Acesso de internet: tabelas/migrações de acesso e arquivo de sessões consumido pelo helper Squid.
- Logs: access.log do Squid, logs de serviço e tabela de auditoria.

### Mudanças desta entrega

A camada de roteamento adiciona uma verificação comum de autenticação, CSRF e somente leitura para `operador`. A camada de sessão impõe inatividade e duração máxima. Schema e migration `003_remover_credencial_padrao.sql` removem a conta pré-semeada insegura; o módulo do painel cria ou rotaciona a credencial com senha aleatória de uso inicial.

### Pendências arquiteturais

Fila persistente de tarefas com estados, timeout, código de saída, exclusão mútua e confirmação posterior; versionamento de configurações; rollback temporizado de firewall/rede; inventário de DHCP/dispositivos; alertas e métricas de host confiáveis. Estas etapas dependem de contratos operacionais e homologação em Debian.

<a id="funcionalidades"></a>

## Matriz de funcionalidades

| Área | Situação encontrada | Alteração nesta entrega | Validação pendente |
|---|---|---|---|
| Login administrativo | Hash, bloqueio por tentativas e troca no primeiro acesso | Revalida conta/perfil nas requisições; inatividade 30 min e teto absoluto de 8 h | Login, expiração e revogação contra MariaDB e modo leve |
| Auditoria | Registro de ações existente | Redação de campos com nomes sensíveis antes de persistir os objetos antes/depois | Conferir categorias reais de configuração em ambiente de laboratório |
| Logout administrativo | GET | POST protegido por CSRF | Teste HTTP em Debian e navegadores |
| Autorização | Controladores com verificações distribuídas; sem política comum | Roteador exige login por padrão; `operador` só pode ler, sair e trocar a própria senha | Revisão de permissões por perfil com responsáveis do ambiente |
| CSRF | Presente em boa parte dos fluxos | Verificação central para métodos mutáveis em rotas autenticadas e públicas | Cobertura de todos os formulários e chamadas AJAX no browser |
| Portal de internet | Cadastro, e-mail, login, sessão por IP, recuperação e administração já existem | Mantido separado do painel; redirect HTTP do Squid, sessão por IP, espelho atômico, revogação e limite padrão de 3 dispositivos por conta com serialização de login; precedência de grupos preservada | Integração real em clientes; troca IP/MAC, DHCP renew, sessões simultâneas e indisponibilidade precisam de VM |
| Grupos, domínios, horários, NAT | Funcionalidades existentes no banco e painel | Preservadas; protegidas pelo gate central | Regressão em banco de laboratório e estado aplicado |
| Firewall, DNS, proxy, Chrony e módulos | Configuração baseada em scripts e ferramentas do sistema | Preservados; menu/status do dashboard respeita módulos registrados | Validação e reversão em Debian com snapshots |
| Dashboard | Interface e contadores existentes | Unidades bps corretas; ausência/falha de coleta distinta de zero; evita requisições concorrentes; backoff após erro; serviços dos módulos instalados | Interface real, reinício de contador e falha de coleta |
| Navegação móvel | Controle JavaScript sem botão/layout correspondente | Drawer, backdrop, Escape, inert e foco visível | Larguras 1440, 1024, 768 e 390 px |
| Instalação em VM | Instalador modular para Debian já presente | Guia para usar o ZIP em VM Debian isolada com WAN/LAN separadas | Instalação e smoke test ainda precisam ocorrer na VM do usuário |
| Tarefas e operações seguras | Algumas rotinas rodavam sem confirmação posterior | Fila allowlisted com timeout, deduplicação e pós-checagem; diff validado de firewall antes da aplicação; snapshot versionado e rollback automático em erro; confirmação visual, histórico e reversão versionada de configurações | Cenários de falha e rollback precisam ser exercitados em VM Debian; aplicação de rede não deve ser homologada só por análise estática |
| Relatórios/auditoria | Relatórios existentes; auditoria básica de mudanças | Período validado, CSV limitado, neutralização de fórmula, máscara de IP para operador, filtro de eventos de auditoria e impressão HTML | Testar exportação e permissões com dados reais; salvar PDF depende do navegador |
| Monitoramento/ranking | Acesso bruto disponível via Squid, sem telas de filtros e ranking | Sockets estabelecidos lidos com `ss`; histórico filtrável por janela, IP, grupo com IP exato, domínio/usuário, protocolo e decisão; ranking 10/20/50; log direcional `%<st` resposta / `%>st` requisição compatível com registros antigos | Conferir permissões de `ss` e sockets Squid em Debian; destino IP e interface por fluxo não estão no log padrão; tráfego bypass fica fora |
| Equipamentos | Não havia inventário central | Descoberta por leases DHCP (com expiração), vizinhos ARP/NDP (inclui interface) e IPs vistos no Squid; ficha com MAC/hostname se fornecidos, política, sessão, consumo e histórico | Validar formatos reais de leases e política de retenção dos dispositivos antigos |
| Alertas/eventos | Não havia painel de eventos | Alertas para WAN, teste DNS, serviços, recursos, backup, certificados, bloqueios, consumo, MAC duplicado, login bloqueado, excesso de sessões, falhas operacionais, mudanças auditadas e novo equipamento | Requer cron e testar condições de recuperação em VM |
| Agenda/simulador | CRUD de regras por horário | Grade semanal e simulação por IP/destino/protocolo/porta/data; respeita expiração no instante simulado, escolhe CIDR mais específico e explica regra horária | Sem consulta à ACL carregada, DNS atual ou SNI; validar cruzando com squid.conf em VM |
| Políticas temporárias | IPs sem expiração | Expiração opcional; tarefa automática desativa e reaplica firewall/horários com auditoria | Confirmar coleta do cron e aplicação sem interrupção da rede |
| Controle de acesso | Grupos e sessões em páginas separadas | Visão central de políticas ativas e sessões válidas, com atalhos às ações administrativas existentes | Exercitar liberação e revogação em clientes de laboratório |
| PDF | Não havia exportação PDF nativa | Impressão HTML pronta para salvar como PDF pelo navegador | PDF não é gerado no servidor |
| Gráfico histórico | Só contadores em memória no navegador | Série real RX/TX do kernel coletada a cada minuto e retida por sete dias | Confirmar permissões cron e leitura das interfaces na VM |
| Backup/restauração | Rotinas existentes | Permissões restritas, SHA-256, validação de arquivo e retenção | Exercício de recuperação completo em laboratório ainda necessário |
| 2FA | Fora do escopo na especificação v2.0 | Não implementado | Não aplicável |


### Requisitos do relatório mestre — dados e evidência

| Requisito | Estado nesta cópia | Limite técnico atual |
|---|---|---|
| Tráfego por equipamento e período | Implementado | Baseado em access.log Squid; não mede fluxos que não passam pelo proxy.
| Download/upload | Implementado para novas coletas | Upload histórico é desconhecido; download/upload são bytes HTTP observados pelo Squid, não contadores totais de interface.
| Agrupamento por grupo/interface | Implementado com dados disponíveis | Política é agregada por IP exato; políticas CIDR não são projetadas para o relatório histórico. Interfaces não coletadas pelo Squid são exibidas como indisponíveis.
| Histórico de sessões | Implementado pela migration 006 | Registra início/fim/duração/motivo e grupo mais específico no login; sessões antigas sem snapshot de grupo exibem ausência. Só eventos após atualização podem ser recuperados.
| Eventos e dispositivos novos | Implementado no relatório | Usa alertas e eventos gravados pelo coletor; operador vê detalhes pessoais restritos; depende do cron e não recria ocorrências anteriores à coleta.
| Exportação CSV e PDF | Implementado | CSV para tráfego, sessões, alertas e dispositivos; PDF via impressão do navegador.

| Integridade do access.log | Implementado pela migration 007 | Chave estável por linha evita duplicação em reprocessamento/falha; evento antes da introdução da chave continua sem fingerprint.
| Agregado diário de acesso | Implementado | Recalculado de forma idempotente a partir de `acessos_internet`; não soma janelas sobrepostas do log bruto.

| Layout v2.0 (cabeçalho, menu, dashboard, login) | Implementado conforme as referências do Relatório Mestre | Capturas no pacote anterior (1440/1024/768/390). Valores das imagens são ilustrativos; a tela usa dados reais |
| Ações rápidas por equipamento | Alterar grupo, bloquear, liberar temporário (reversível), revogar, lote com prévia | Aplicação no firewall/Squid depende do worker em Debian |
| Diagnóstico, Ajuda, Busca global, Políticas | Implementados | Checagens dependem de systemctl/cron no servidor real |

<a id="diagnostico"></a>

## Diagnóstico da revisão anterior

Data: 06/11/2026  
Base inspecionada: `gwos-pw-main.zip`  
Estado: implementação local em cópia de entrega, sem instalação no host.

### Arquitetura e funcionalidades existentes

- Aplicação PHP própria com roteador, controladores, views, Bootstrap, Bootstrap Icons e JavaScript local.
- MariaDB opcional para o painel leve; quando presente, guarda administradores, grupos/IPs, domínios, horários, NAT, relatórios, auditoria e dados do portal.
- Módulos de sistema independentes: base/rede, MariaDB, BIND9, dnsmasq, Chrony, nftables, Squid e painel web.
- Login administrativo e portal de internet são fluxos separados. O portal existente usa usuários finais, e-mail de confirmação, sessão associada ao IP e integração do Squid por arquivo de sessões.
- Scripts privilegiados são instalados em Debian pelos instaladores; esta entrega não executa esses scripts.

### Riscos e divergências identificados

1. Logout do administrador era GET e não tinha proteção CSRF.
2. A autenticação era aplicada em muitos controladores, sem uma barreira comum para todas as rotas; perfis não tinham política geral no roteador.
3. Sessões não tinham expiração por inatividade ou limite absoluto no código PHP. Sessões existentes também não eram revalidadas quando uma conta era desativada ou seu perfil alterado.
4. O dashboard tratava interface ausente e erro de leitura de contador como zero; calculava bytes por segundo, embora os rótulos fossem bits por segundo; consultava serviços fixos mesmo se os módulos não estivessem instalados.
5. O layout não continha o controle de menu móvel correspondente ao JavaScript que já existia.
6. Algumas alterações de políticas iniciam scripts privilegiados em segundo plano e respondem antes de confirmar resultado. A auditoria atual não equivale a uma fila de tarefas com timeout, código de saída e verificação posterior.
7. A aplicação do portal cativo, captive detection, reconexão e falha segura só podem ser comprovadas em laboratório Debian com Squid, banco, TLS e clientes reais.

### Fontes do dashboard

| Dado | Fonte atual | Limite |
|---|---|---|
| IP, gateway e WAN padrão | `ip route` | Depende do comando e da configuração local.
| DNS | `/etc/resolv.conf` | Pode refletir stub/local resolver.
| Bytes WAN/LAN | `/sys/class/net/<interface>/statistics/*_bytes` | Contadores cumulativos; ausência/erro agora retorna `null`.
| Serviços | `systemctl is-active` por serviço dos módulos registrados | Não informa ainda estados distintos de não instalado, falha e acesso negado em todas as telas.
| Acessos | `/var/log/squid/access.log` e tabelas do MariaDB | Visibilidade HTTPS se limita ao que o proxy efetivamente registra.
| Métricas de CPU, memória e temperatura | Não havia fonte implementada | Não são apresentadas como se fossem coletadas.

### Limites desta entrega

O ZIP continha uma versão que já implementava parte importante do portal e do sistema modular. A atualização preserva essa base. As alterações incluem migrations 004–006 e schema atualizado. O instalador do módulo MariaDB reaplica as migrations idempotentes em bancos existentes; a migration 006 começa a registrar histórico de sessões após a atualização. As operações privilegiadas, firewall e DNS não foram aplicados neste computador. A validação integrada ainda depende de Debian 13 de laboratório.

<a id="resumo-historico"></a>

## Resumo executivo da versão 2.0.1-dev

### Concluído nesta cópia

- Endurecimento do roteador: autenticação por padrão, CSRF central e perfil `operador` somente leitura.
- Logout administrativo convertido para POST protegido por CSRF.
- Sessões com expiração por inatividade e duração máxima; sessão administrativa revalida conta ativa e perfil.
- Remoção da senha fixa de novas instalações; criação/rotação da conta com a senha digitada por quem instala (sem senha fixa nem aleatória escondida); migration 003 para a credencial legada.
- Auditoria redige campos com nomes sensíveis nos dados antes/depois.
- Dashboard distingue falha/ausência de coleta, calcula taxa em bps, detecta contador reiniciado, impede sobreposição e usa backoff.
- Serviços exibidos no dashboard limitados aos módulos registrados.
- Dashboard com indicadores de carga, memória, disco raiz e uptime.
- Fila de operações privilegiadas allowlisted com histórico, deduplicação, timeout, estados de falha e verificação posterior.
- Backups e restauração com permissões restritas, integridade/checksum, retenção e validação dos membros do arquivo.
- Exportação CSV com período limitado, neutralização de fórmulas e máscara de IP/identificadores para operadores.
- Importação do access.log idempotente por chave de linha, com migration 007, e recálculo diário sem duplicar janelas.
- Diretório de sessões separado do diretório restrito de backups.
- Roteiro específico para extração do ZIP e instalação isolada numa VM Debian, com WAN/LAN em redes de laboratório.
- Drawer móvel, backdrop, Escape, inert e foco visível; paleta alinhada à especificação.
- Relatórios operacionais por equipamento/grupo, com upload/download observado, bloqueios, histórico de sessões com grupo do login, alertas, dispositivos novos e exportação CSV/impressão PDF.
- Documentos de diagnóstico, arquitetura, matriz, changelog, testes e atualização incluídos.

### Fechado na revisão de conclusão (07/11/2026)

- Senha do administrador agora é digitada na instalação (`pedir_senha_admin` em `modulos/comum/lib.sh`; `GWOS_ADMIN_SENHA` para modo automático); `gwos senha <email>` também pergunta no terminal.
- `php -l` em todos os PHP: corrigido erro de sintaxe em `operacional/controle_acesso.php` (faltava `?>`).
- Schema + migrations 001–007 aplicados e reaplicados (idempotência) em MariaDB 10.11: OK. Seed de domínios corrigido (coluna inexistente; agora idempotente).
- Runtime com PHP 8.3 + MariaDB: login, 28 telas, CSRF (403), perfil operador somente leitura, bloqueio por tentativas, logout POST. Bugs corrigidos: `/ranking` dava 500 (variável `$dados` colidia com `extract(EXTR_SKIP)` em `view()`) e warning em `horarios` (`global` dentro de view).

- Layout refeito conforme as imagens do Relatório Mestre v2.0 (cabeçalho, menu, dashboard, login) e funções novas: ações rápidas com prévia, liberação temporária reversível, Políticas, Diagnóstico, Ajuda e Busca. As capturas dessa revisão estão no pacote anterior.

### Pendente antes de considerar pronto

- Testes do portal de internet integrado a Squid/MariaDB/TLS em Debian 13.
- Testes integrados de ID/estado/timeout/concorrência/resultado das tarefas e rollback de firewall/rede.
- Revisão completa de sudoers, telas de configurações, regras por perfil e proteção HTTPS de produção.
- Integração real em Debian 13 com PHP/MariaDB, portal cativo/Squid/TLS, tarefas privilegiadas e rollback.
- Validação visual com capturas em diferentes resoluções.
- Alguns dados previstos no relatório (destino IP por acesso, interface de rede por fluxo, CIDRs no agrupamento histórico e fluxos fora do Squid) não existem nas fontes atuais e são mostrados como indisponíveis, sem inferência.

### Evidência disponível

- Sintaxe dos scripts shell alterados e do JavaScript global/inline verificada localmente; migrations e histórico novo requerem execução na VM.
- Uma varredura confirmou que os formulários POST renderizados incluem CSRF, que `/logout` não está registrado como GET e que o schema novo não semeia administrador.
- PHP CLI/MariaDB, distribuição WSL, navegador conectado ao GWOS e Debian de laboratório não estão disponíveis neste ambiente.

### Risco e implantação

Esta é uma versão de desenvolvimento, não homologada para produção. Não foram executados instaladores nem alterados serviços, firewall, DNS, proxy, NAT ou interfaces no host. A migration 003 elimina uma credencial legada conhecida; faça snapshot/backup antes de qualquer teste e mantenha acesso de console ao gateway. Para instalações existentes, aplique migrations 006–007 após backup; a migration 006 inicia o histórico de sessões e a 007 adiciona idempotência ao importador.

<a id="historico"></a>

## Histórico de implementação até a versão 2.0.1-dev

Data: 06/11/2026

### v2.0.1-dev — portal de senha de internet sem depender de e-mail

- Admin cadastra usuário de internet com senha digitada (entra já confirmado), define/redefine senha (encerra sessões) e gera link de uso único.
- Cadastro/“esqueci a senha” avisa quando o SMTP falha (antes mostrava sucesso sem enviar nada).
- Tela de SMTP em *Acesso com login* (servidor, porta, segurança, usuário, senha, remetente) + e-mail de teste; alterações vão para histórico e auditoria.
- Filtro “Decisão” do Monitoramento não fica mais cortado.

### Segurança e acesso

- Logout administrativo alterado de GET para POST com token CSRF no formulário.
- Router aplica autenticação por padrão; mantém allowlist explícita para login, portal e recuperação de senha.
- Requisições mutáveis exigem CSRF na camada comum, inclusive para rotas públicas de formulário.
- Perfil `operador` fica somente leitura, com exceção de logout e troca da própria senha.
- Sessões expiram após 30 minutos sem atividade ou no teto configurável de 8 horas.
- Cada requisição administrativa revalida se a conta continua ativa e sincroniza o perfil atual da sessão.
- Auditoria redige recursivamente campos com nomes de senha, token, segredo e chave privada antes de gravar `dados_antes/dados_depois`.
- Schema deixa de semear a conta com senha fixa; migration 003 remove apenas a credencial legada conhecida, e o instalador **pede ao operador a senha do administrador** (oculta, confirmada, mín. 8) ao criar a conta ou substituir a senha de fábrica. Instalação automatizada: `GWOS_ADMIN_SENHA`. A senha escolhida não força nova troca.

### Monitoramento e interface

- Contadores ausentes/inválidos do dashboard deixam de virar zero.
- Cálculo de tráfego agora é `(delta_bytes * 8) / delta_segundos`, com detecção de contador reiniciado.
- Coleta evita sobreposição e usa backoff exponencial limitado até 60 segundos quando há erro.
- Serviços do dashboard vêm do catálogo de módulos registrados.
- Dashboard apresenta carga, memória disponível, uso do disco raiz e tempo ligado quando o kernel expõe esses dados.
- Paleta aproximada à especificação v2.0; drawer móvel com backdrop, Escape, suporte a `inert` e foco visível.

### Operações, relatórios e recuperação

- Ações privilegiadas do painel agora entram em fila persistente allowlisted, com identificador, estados, timeout de 60 s, deduplicação, histórico de 90 dias e confirmação posterior do serviço/firewall.
- Worker cron roda como `www-data`; comandos são invocados por caminhos fixos, `sudo -n` e parâmetros NAT validados. A interface não apresenta saída bruta dos comandos.
- Incluída página de histórico de operações com atualização periódica.
- Backup usa `umask 077`, diretório restrito, arquivo temporário, verificação gzip/tar, SHA-256 e retenção dos sidecars.
- Restauração valida checksum quando presente, integridade e nomes/tipos de membros esperados, preserva a rede atual e propaga falhas de aplicação.
- Sessões foram movidas para `/var/lib/gwos/sessions`; backups permanecem inacessíveis ao usuário web.
- Relatório valida período (máximo 367 dias), exporta CSV limitado a 50 mil linhas, protege fórmulas e mascara IPs IPv4/IPv6 para perfil operador.
- Guia de instalação em VM descreve uso direto do ZIP, duas interfaces isoladas, verificação dos módulos e testes iniciais.

### Arquivos alterados

- `app/Core/Router.php`
- `app/Core/Auth.php`
- `app/Core/Session.php`
- `app/Controllers/DashboardController.php`
- `app/Views/layout.php`
- `app/Views/dashboard/index.php`
- `app/Core/Tarefas.php`, `app/Controllers/TarefasController.php`, `app/Views/tarefas/index.php`, `scripts/processar_tarefas.php`
- `app/Controllers/RelatorioController.php`, `scripts/backup.sh`, `scripts/restaurar_backup.sh`
- `config/config.php`
- `public/assets/js/app.js`
- `routes/web.php`

### Banco e infraestrutura

Schema de novas instalações alterado e migration `003_remover_credencial_padrao.sql` adicionada. O rollback não restaura uma credencial fixa: em laboratório, defina uma senha pela CLI `gwos senha <email>` (pergunta no terminal). Instaladores, firewall, DNS, proxy, NAT, interfaces e serviços não foram executados nem alterados no host.

### Pendências

Timeout, confirmação e rollback automático precisam de teste integrado no Debian; testes de browser e homologação integrada do portal cativo permanecem necessários antes de produção.

### Complemento — requisitos operacionais do Relatório Mestre v2.0

- Migration `004_operacional_v2.sql` adiciona campos de protocolo/porta e interface, expiração de IP, inventário observado e alertas deduplicáveis; o instalador do banco aplica as migrations também em bancos existentes.
- Monitoramento e ranking consultam os registros brutos importados do Squid. O log passou a registrar `%<st` (resposta) e `%>st` (requisição); a migration `005_trafego_direcional.sql` adiciona o campo, preservando `NULL` para upload legado não medido.
- Inventário é preenchido por leases DHCP, vizinhos de rede e acessos Squid observados; MAC/hostname ficam vazios quando a fonte não os fornece.
- Alertas de link WAN, serviços registrados, uso de disco/memória, idade/resultado do backup, pico de bloqueios, consumo por IP, MAC duplicado, bloqueio de login e novo equipamento são coletados a cada minuto; o operador pode reconhecer ou resolver eventos. Equipamentos e alertas não são dados fictícios.
- Agenda semanal mostra as regras ativas cadastradas; o simulador aceita IP, destino, protocolo, porta e horário, avalia grupos, whitelist/blacklist, porta segura e horário pela ordem conhecida. Ele é informativo e não consulta uma ACL em memória do Squid.
- Controle de acesso reúne políticas por grupo e sessões válidas do portal em uma página central, com links para as ações administrativas existentes.
- Monitoramento separa sockets estabelecidos do Squid (consulta `ss`) do histórico de access.log; a ficha individual mostra política, sessão, interface/lease quando conhecidos, volumes observados e histórico.
- O portal limita a três dispositivos simultâneos por usuário por padrão, com valor de configuração `acesso_max_sessoes_usuario` e bloqueio serializado por conta.
- Alertas incluem teste DNS limitado a quatro segundos, certificados próximos do vencimento, limite de sessões, operações failed/timeout/unconfirmed e mudanças recentes encontradas na auditoria.
- Regras de IP podem ter expiração. O cron desativa a regra vencida, registra auditoria e enfileira a atualização do firewall e do Squid.
- A página de auditoria e a impressão das páginas de relatório permitem salvar em PDF pelo navegador. O PDF gerado é uma impressão HTML; não há biblioteca de PDF embutida.
- Gráfico LAN/WAN passou a carregar histórico real RX/TX do kernel, coletado a cada minuto e mantido por sete dias.
- Configurações agora validam interface/rede/porta/limites, mostram diff e confirmação antes de gravar, versionam valores sem persistir segredos no histórico e permitem reverter chaves não sensíveis.
- Firewall ganhou prévia read-only com `nft -c` e diff, snapshots do ruleset/config e rollback automático quando a aplicação ou pós-checagem falha. A troca de IP também guarda snapshots, valida serviços e restaura rede, valores DB e configurações diante de falha.
- Limitações restantes: a aba ativa observa sockets TCP estabelecidos nas portas do Squid, mas não determina destino remoto nem bytes por socket; o histórico do proxy não recebe destino IP/interface por fluxo; os bytes de upload são o tamanho HTTP da requisição, não todo o tráfego IP; tráfego que bypassa o proxy fica fora do ranking. O simulador compara configuração cadastrada, não a ACL carregada nem a resolução atual de DNS. Teste real de reachability WAN, 2FA e rollback de rede ainda requerem evolução/homologação de laboratório.

### Relatórios e sessões

- Migration 006 registra encerramentos de sessão por logout, expiração, revogação administrativa, desativação, troca de senha, substituição no mesmo IP e exclusão do usuário.
- Relatórios exibem totais por período e tráfego HTTP agrupado por IP/equipamento/grupo/interface disponível, com exportação CSV de tráfego e sessões e impressão/PDF pelo navegador.
- Interface de rede que não é associada ao log de acesso aparece como “Não coletada”; upload anterior à migration 005 segue sem estimativa.

- Simulador considera expiração de política na data escolhida, seleciona o CIDR mais específico e limita regra global de permissão ao grupo parcial conforme a ACL gerada.
- Ajustados relatórios para agregar múltiplos grupos exatos sem duplicar contagens e para restringir identificadores pessoais de sessões ao perfil operador.
- Relatórios passam a exibir/exportar alertas e novos dispositivos por período; sessões arquivadas preservam grupo no momento do login.

### Integridade da importação do Squid

- Migration 007 adiciona `log_key` único por inode/geração/offset. Reprocessar o mesmo trecho depois de uma falha não duplica acessos. A geração é salva atomicamente antes da importação e a identificação usa `fstat` do arquivo aberto para cobrir rotação.
- `parsear_logs.php` recalcula o agregado diário a partir da tabela canônica, em vez de somar novamente as últimas linhas do access.log. O script shell legado chama o mesmo recálculo e saiu do cron duplicado.
- O relatório diário agora agrega os registros canônicos por data/IP/domínio diretamente.


### v2.0.0-dev — layout e funções do Relatório Mestre v2.0 (07/11/2026)

- **Design system** novo em `public/assets/css/gwos.css`; `layout.php` refeito: cabeçalho navy (marca, busca global, “Servidor Online” com pulso real via `/ping`, data/hora, sino de alertas, menu do usuário, tema escuro opcional), menu lateral com submenus na ordem do relatório (Dashboard, Monitoramento, Controle de Acesso, Ranking, Equipamentos, Políticas e Regras, Agenda, Alertas, Relatórios, Diagnóstico, Configurações, Ajuda) e rodapé.
- **Dashboard** conforme a imagem de referência: Estado Geral, WAN, LAN (sparklines ao vivo), tráfego 24 h (faixas de 30 min a partir de `metricas_rede`; lacunas e contador reiniciado = sem dados), Top 10, alertas, acessos em tempo real, Controle Rápido, Simulador, Agenda, Equipamentos e Serviços (só módulos instalados).
- **Login** do painel e **portal de internet** redesenhados (logins continuam separados).
- **Ações rápidas** (`Politicas`, `PoliticaController`, `POST /politicas/acao`): alterar grupo, bloquear, liberar temporariamente (5 min a 7 dias, retorno automático à política anterior), revogar; prévia + confirmação, lote de até 50 IPs, auditoria, fila allowlisted. Migration `008_liberacao_temporaria.sql`; `expirar_politicas.php` restaura as regras suspensas. Disponível nas telas Dashboard, Equipamentos (lote), Ficha e Políticas; oculto e bloqueado (403) para o perfil operador.
- Novas telas: **Políticas e Regras**, **Diagnóstico** (serviços, interfaces, coleta, recursos, backup), **Ajuda**, **Busca global**. Ranking com gráfico e períodos Hoje/Mês; Monitoramento com abas Bloqueios e Sessões.
- Limite conhecido: a ação rápida atua só em regra de IP exato; a precedência final com redes CIDR é a do squid.conf/nftables e deve ser validada na VM.

<a id="testes"></a>

## Testes, resultados e pendências

Data: 06/11/2026

### Verificações executadas

| Verificação | Resultado | Observação |
|---|---|---|
| Inventário do ZIP, rotas, controllers, views, schema, migrations e scripts | Concluído | Inspeção estática da cópia extraída. |
| Regras centrais de acesso, CSRF, sanitização da auditoria e provisionamento sem senha fixa | Implementadas; validação runtime pendente | Ambiente disponível não inclui PHP CLI nem MariaDB. |
| `php -l` | Não executado | PHP/WSL não estão instalados neste Windows; os novos controllers/serviços precisam ser validados na VM Debian antes da homologação. |
| `bash -n` | Passou nesta revisão | Todos os scripts `.sh` do projeto, inclusive os fluxos novos de rollback. |
| JavaScript `node --check` | Passou nesta revisão | `public/assets/js/app.js` e scripts inline das views sem conteúdo PHP embutido. |
| Fila de operações | Implementada; integração pendente | Não foi possível exercitar cron, sudoers, concorrência, timeouts ou confirmação sem Debian/Squid/nftables. |
| ZIP de instalação | Conferido estruturalmente nesta revisão | O conteúdo do projeto é empacotado na raiz; migrations 006–007 e relatórios estão presentes; `.env` não está incluído. |
| Backup/restauração | Implementadas verificações estáticas | Não foi feito dump, restauração nem teste de checksum em banco real. |
| Teste visual responsivo | Pendente | Requer navegador e revisão visual em 1440, 1024, 768 e 390 px. |
| Teste de portal cativo/Squid e decisões por grupo | Pendente | Requer Debian 13 de laboratório, Squid, TLS, banco e clientes. |
| Timeout, falha e concorrência de tarefas | Pendente em laboratório | Fila e confirmação estão implementadas; comportamento real exige worker, sudoers e serviços Debian. |
| Rollback de firewall/rede | Implementado; validação runtime pendente | Prévia/diff, snapshot e rollback estão no código; falhas reais ainda precisam ser provocadas em VM isolada. |

### Classificação de evidência

- Estático: inventário e leitura de código/documentos.
- Implementado: alterações locais na cópia de entrega.
- Automatizado: `bash -n` e `node --check` nas listas descritas acima.
- Laboratório: não executado.
- Produção: não executado.

Esta versão está preparada para instalação isolada numa VM de laboratório, mas
não foi homologada para produção. Neste ambiente não há PHP CLI, MariaDB,
distribuição WSL ou VM conectada para executar a validação final.

### Funcionalidades v2 adicionadas nesta revisão

- Novas páginas: `/monitoramento`, `/ranking`, `/equipamentos`, `/equipamentos/ficha`, `/controle-acesso`, `/alertas`, `/agenda`, `/agenda/simulador` e `/relatorios/auditoria`.
- Novas coletas agendadas: alertas, inventário DHCP/vizinhos e expiração de políticas.
- Migration `004_operacional_v2.sql` executada pelo instalador também em banco existente; requer validação na versão MariaDB alvo.
- A interface de exportação PDF usa impressão do navegador. O ranking mede bytes de resposta e bytes de requisição HTTP do Squid. Alertas usam limites configuráveis e condições observadas no servidor.
- A migration 005 e o access.log medem requisições via `%>st`, separadas das respostas via `%<st`; registros antigos permanecem com upload `NULL`. Ela também grava expiração de lease/interface do inventário e limita três dispositivos ativos por usuário. Os volumes não representam todo o tráfego IP e excluem fluxos desviados do Squid.
- A aba de conexões consulta sockets estabelecidos nas portas do Squid; não mostra destinos remotos nem volume por socket. Histórico vem do banco alimentado pelo importador cron. O simulador aceita IP, destino, protocolo, porta e data, mas não interroga a ACL carregada nem resolve o domínio no momento do teste.
- A sintaxe PHP e o comportamento das migrations 004, alertas, descoberta de hosts e aplicação/expiração de firewall ainda não foram executados neste ambiente, pois não há PHP CLI, MariaDB ou VM Debian conectada.
- O verificador `php -l` continua indisponível neste Windows: não há PHP CLI nem parser PHP local instalado. A validação PHP e SQL deve ser executada na VM durante a instalação/homologação.


### Alterações desta revisão

- Adicionada a migration `006_historico_sessoes.sql` e tabela correspondente no schema de instalação nova.
- O ciclo do portal arquiva sessões encerradas por logout, expiração, revogação, desativação, troca de senha, substituição e exclusão; a sincronização de expiradas é transacional.
- A tela de relatórios agora agrega bytes Squid por IP/equipamento/grupo/interface observada, bloqueios e histórico de sessões, com exportação CSV separada e impressão/PDF.
- `bash -n` passou para todos os scripts `.sh`; `node --check` passou para o JavaScript global. A validação PHP/SQL e teste de execução continuam pendentes por falta de PHP CLI e MariaDB neste ambiente.
- A revisão estática também corrigiu o simulador para data simulada/CIDR mais específico e ampliou os relatórios com grupo de sessão, alertas e eventos de novos dispositivos. Estas alterações ainda não tiveram lint PHP nem execução MariaDB por indisponibilidade das ferramentas no ambiente.

- Revisão do importador Squid: identificada duplicação potencial após falha parcial e recálculo diário repetitivo; adicionada chave idempotente/migration 007 e agregação diária derivada da tabela canônica. Sintaxe PHP/SQL ainda precisa ser executada em Debian/MariaDB.

### Revisão de conclusão — 07/11/2026 (PHP 8.3.6, MariaDB 10.11, Ubuntu; fora do Debian 13)

| Verificação | Resultado |
|---|---|
| `php -l` em todos os `.php` | Passou (após corrigir `controle_acesso.php`) |
| `bash -n` em todos os `.sh`; `node --check` | Passou |
| `schema.sql` + migrations 001–007, duas rodadas | Passou, idempotente |
| Rotas → controllers/métodos/views | 0 inconsistências |
| Login (banco e modo arquivo), CSRF sem token = 403, `/logout` GET = 404, POST encerra sessão | Passou |
| Perfil operador: leitura 200, escrita 403 | Passou |
| Bloqueio após tentativas erradas | Passou |
| 28 telas com dados de teste | 200 sem warnings (após corrigir ranking e horários) |
| Provisionamento do admin com senha digitada (novo, legado, personalizado) | Passou |
| `gwos senha` com prompt | Passou |

Continuam pendentes (exigem Debian 13 real): Squid/portal cativo/TLS, nftables e rollback de rede, worker de tarefas com sudoers, captura visual responsiva.

### v2.0.0-dev — layout e ações (PHP 8.3, MariaDB 10.11, Chromium)

| Verificação | Resultado |
|---|---|
| `php -l`, `bash -n`, `node --check` | Passou |
| Migration 008 (duas rodadas) | Passou |
| 24 telas autenticadas com dados de teste | 200, sem warnings |
| Ações: prévia, liberar temporário, revogar, expiração via cron, bloquear, alterar grupo, IP inválido, sem CSRF (403) | Passou; regras anteriores restauradas |
| Operador: POST de ação = 403; botões ocultos | Passou |
| Capturas 1440/1024/768/390 px (login, dashboard, equipamentos, monitoramento, diagnóstico) | Geradas e preservadas no pacote anterior; layout sem rolagem horizontal da página no mobile |

Nos testes, os serviços aparecem “Parado” porque o ambiente de teste não tem systemd; em Debian real o estado vem de `systemctl is-active`.

### v2.0.1-dev — portal de senha (PHP 8.3, MariaDB, Chromium)

Fluxo completo testado: cadastro, link, senha fraca/boa, reuso de link (recusado), login, helper Squid (OK/ERR), limite de 3 dispositivos, sair, bloqueio após 5 erros, conta do portal não entra no painel admin.
Novo: admin cria usuário com senha digitada, duplicado/domínio errado/senha fraca recusados, redefinir senha encerra sessão, link gerado funciona de ponta a ponta, SMTP salvo/validado, cadastro público avisa quando o e-mail está indisponível. 24 telas do painel abertas no Chromium: todas HTTP 200, sem aviso de PHP nem erro de JavaScript.
Não validado aqui (só na VM Debian): nftables, Squid real, TLS do portal, systemctl.

### v2.0.2-dev

As correções de configuração, expiração, CSRF e reversão foram revisadas por inspeção estática no Windows. Os resultados de laboratório acima são de versões anteriores. Nesta versão, a homologação ainda precisa cobrir instalação limpa e atualização, ausência de token CSRF em sessão nova, expiração com indisponibilidade temporária da fila, confirmação do acesso real via Squid e nftables e falha induzida após reaplicar o painel.

### v2.0.3-dev — revisão da v2.0.2 e ajustes de layout

- Revisão do pacote do Codex (v2.0.2) em PHP 8.3/MariaDB: migração 009 aplica e é idempotente; `expirar_politicas.php` reativa o IP anterior, enfileira firewall/Squid, não duplica tarefas enquanto estão na fila e só encerra o pendente após `succeeded`; CSRF vazio é recusado (HTTP 403); criar usuário de internet pelo admin e login no portal continuam funcionando.
- Equipamentos: tabela compacta e coluna **Ações** sempre visível (fixa à direita).
- Dashboard no celular: cartões WAN/LAN deixam de esticar com altura vazia.
- 26 telas do painel e 5 do portal abertas no Chromium (desktop e 390 px): HTTP 200, sem erro de PHP/JS e sem rolagem lateral na página.
- Não validado aqui (só no Debian): nftables, Squid real, TLS do portal, systemctl e o novo modo de permissões (`/opt/gwos` do root, `.env` 0640 root:www-data).

### v2.0.4-dev

- `verificar.sh` do painel aceita o `.env` em 640 root:www-data (modo definido na v2.0.2); antes acusava erro falso exigindo 600.

### v2.0.5-dev

- `20-dns-bind9`: o instalador agora grava o `/etc/resolv.conf` do próprio gateway (BIND local `127.0.0.1` + 2 forwarders de reserva) depois de provar que o BIND responde, guarda backup (`/etc/resolv.conf.gwos-bak.*`) e impede o dhcpcd de apagá-lo (`nohook resolv.conf`). Com `systemd-resolved` ativo não altera nada.
- `verificar.sh` do módulo passa a acusar resolv.conf sem `nameserver`.
- Não testado em Debian real (só sintaxe).

### v2.0.6-dev

- `00-base`: com WAN/servidor em IP fixo, o `/etc/network/interfaces` passa a incluir `dns-nameservers` (usa o pacote `resolvconf`, se instalado). Se o `/etc/resolv.conf` terminar sem nenhum `nameserver`, o módulo grava resolvers de reserva e impede o dhcpcd de apagá-los. Com WAN em DHCP o arquivo continua como estava (o DNS vem do DHCP). Sintaxe verificada; não testado em Debian real.

### v2.0.7-dev

- Novo `gwos rede [IP_CLIENTE]` (`scripts/diagnostico_rede.sh`): só leitura. Confere interfaces, rota padrão, `ip_forward`, saída do servidor (ping/DNS), `resolv.conf`, NAT/masquerade, se o cliente está em **Bloqueados** (pinga o gateway, mas não a internet), BIND, Squid e portas de escuta.
- Proxy manual no cliente: usar o IP do gateway na porta **3127** para HTTP **e** HTTPS. A 3128 é de interceptação e não aceita proxy manual. Sem proxy manual também funciona (redirecionamento transparente).

### v2.0.8-dev — login de internet por navegação, firewall obrigando login e monitor ao vivo

**Como cada cliente é tratado**

| Situação do IP | Passa pelo proxy? | Senha? | Aparece no monitor? |
|---|---|---|---|
| Grupo **Liberado** | Não (desvia) | Não | Não |
| Grupo **Isento** | Sim | Não | Sim |
| Grupo **Parcial** | Sim (blacklist/horário) | Não | Sim |
| Grupo **Bloqueado** | só a whitelist institucional | — | Só a whitelist |
| **Sem grupo** (padrão) | Sim | **Sim — login no portal** | Sim, com o e-mail do usuário |

- **Login por navegação.** A sessão do portal dura enquanto houver navegação. Sem navegar por `acesso_inatividade_min` minutos (padrão 10, mínimo 3), a sessão é encerrada (motivo `inatividade` no histórico) e o usuário precisa entrar de novo. Fechar todos os navegadores equivale a parar de navegar. O servidor não enxerga o navegador fechado: ele mede o tráfego pelo proxy. Com SSL Bump ativo só conta tráfego com User-Agent de navegador (atualizações do sistema, curl, apt etc. não mantêm a sessão); sem SSL Bump conta qualquer tráfego (`acesso_atividade_modo`: `auto`, `navegador`, `qualquer`). O limite máximo continua sendo `acesso_sessao_horas`. O corte acontece em até ~1 min depois do prazo (cron do importador).
- **Cadastro:** desde a versão 2.0.12, novas contas são criadas por CPF.
- **Firewall exige login** (`acesso_forcar_firewall=1`, padrão). O nftables passa a ter os sets `ip_acesso_livre` (liberado+isento+parcial) e `ip_autenticados` (sessões de login, atualizado a cada login/logout por `/usr/local/sbin/gwos-sessoes-nft` via sudo). Quem não está em nenhum e não tem sessão não sai por fora do proxy (antes o HTTPS sem SSL Bump e portas diversas saíam livres, sem senha). O QUIC (UDP 443) é recusado para quem passa pelo proxy, para o navegador voltar ao HTTPS normal, que é monitorado.
- **Página de login em HTTPS** só aparece sem aviso de certificado se o computador confiar na CA do GWOS (SSL Bump). Sem isso, o HTTP abre a tela de login normalmente e os sistemas operacionais costumam abrir sozinhos o aviso de "entrar na rede".
- **Monitoramento > Ao vivo.** Lê o `access.log` direto (não depende do importador), atualiza a cada 4 s e explica por que está vazio (Squid parado, log ilegível ou vazio, importador sem rodar, grupo Liberado que não passa pelo proxy).
- **`logformat` do Squid** agora termina com o User-Agent entre aspas. O `atualizar.sh` reaplica `squid.conf` (com backup e reversão se o Squid recusar) e o firewall.
- `gwos rede <IP>` informa em qual regra o cliente cai (liberado, isento/parcial, logado, sem grupo, bloqueado).
- Correção: `aplicar_nftables.sh` chamava `erro` sem defini-la.
- Testado aqui: sessão por inatividade (navegador mantém, atualizador/negado não), cadastro direto, regras salvas, monitor ao vivo, regras nftables carregadas num namespace de rede real e `gwos-sessoes-nft`. Não testado: Squid real com SSL Bump, portal HTTPS e aplicação no Debian.

### v2.0.10-dev — revisão para teste em VM

- Firewall: arquivo de prévia privado, serialização com a sincronização de sessões e permissão para respostas DHCP na WAN. A passagem entre duas sub-redes na mesma interface LAN continua disponível. Novas conexões WAN para LAN precisam de DNAT configurado ou regra explícita. O SSH do próprio GWOS continua com sua regra de entrada.
- Atualização: a busca lista candidatos. Indique explicitamente a origem confiável antes de executar o atualizador. A simulação lê todo o resultado do rsync e exibe as primeiras 60 linhas.
- Painel: da LAN da VM, use o IP e a porta configurados no Debian. Para separar falha de proxy de falha do servidor, execute `ip -br -4 addr` e `sudo ss -ltnp` no Debian e teste `curl.exe --noproxy "*" http://IP_LAN:PORTA/login` no Windows.
- A aplicação de nftables, Squid, migrations e atualização ainda precisa de teste integrado na VM Debian.

### Reaplicação do painel na VM

O atualizador mantém a porta existente do painel sem pedir confirmação de porta. A verificação mostra a saída completa de cada módulo. Mensagens AF_VSOCK do systemd na VM são distintas dos resultados de DNS, firewall e painel.

### Política do grupo Bloqueado

O grupo Bloqueado restringe novas conexões diretas da LAN para a WAN. Serviços do gateway (incluindo painel, DNS e Squid) e roteamento LAN para LAN seguem as regras da LAN. Para navegação, o Squid avalia a whitelist antes do bloqueio. Sites autorizados precisam passar pelo Squid, por proxy explícito na porta 3127 ou interceptação quando disponível. Conexões já estabelecidas seguem a regra de conntrack até encerrarem.

### Aviso e entrada no portal de internet

Abra `https://IP_DA_LAN:8444/acesso` com a porta efetiva do portal e o IP da LAN nas exceções do proxy do cliente. Use um cliente sem grupo e sem sessão para testar o redirecionamento de um site HTTP fora da whitelist. O grupo Bloqueado é uma restrição administrativa e o login não libera sua navegação. O navegador pode exibir erro de túnel quando nega um CONNECT HTTPS, mesmo com o portal funcionando.

### v2.0.11-dev — testar o login da internet no Edge

- Na VM, atualize pelo console com `sudo bash atualizar.sh` a partir da pasta extraída. Se o portal nunca foi ativado, rode na instalação `sudo bash scripts/ativar_acesso_internet.sh`.
- Na LAN da VM, abra `https://192.168.0.1:8444/acesso`, ajustando IP e porta para sua instalação. Configure o certificado do portal como confiável pela autoridade da rede. Use esse endereço como página inicial do Edge para apresentar a tela também quando a primeira navegação seria HTTPS.
- Para testar o redirecionamento automático, use cliente sem grupo e sem sessão, com proxy explícito na porta 3127 ou interceptação HTTP ativa. Abra uma URL HTTP fora da whitelist. O Edge pode exibir erro de túnel se a primeira URL for HTTPS. Um cliente no grupo Bloqueado continua sob restrição administrativa.
- A atualização retorna código 2 quando o código foi aplicado e uma verificação ficou pendente. O log permanece em `/var/log/gwos-atualizacao.log`.

### v2.0.12-dev — cadastro por CPF

O portal cadastra nome completo, CPF e senha de 8 a 72 caracteres alfanuméricos, com pelo menos uma letra e um número. O cadastro é imediato. O CPF informado passa pela validação de dígitos, que não comprova a identidade. Contas antigas mantêm o login por e-mail. No painel, **Acesso à internet com login → Resetar senha** invalida a senha e encerra as sessões da conta. Entregue o código temporário em particular ao titular para usar em **Esqueci minha senha**. O Squid recebe um identificador interno aleatório para contas novas. Proteja o banco e os backups, que contêm o CPF. Distribua um certificado confiável antes de usar dados reais.

### v2.0.14-dev — inatividade

As sondagens NCSI do Windows continuam no log, mas não renovam a sessão em nenhum modo. O servidor encerra por inatividade, não pelo evento de fechamento de janela.

### v2.0.49-dev — rede interna 10/8

O Squid permite HTTP de clientes da LAN para destinos em `10.0.0.0/8`,
inclusive na porta 81, antes da validação de portas e do login. Túneis CONNECT
e destinos externos seguem as regras existentes.

### v2.0.48-dev — aviso de porta bloqueada

Com o portal HTTPS ativado, o Squid encaminha requisições HTTP recusadas pela
regra de portas permitidas para a página **Acesso restrito**. A página orienta
a procurar o Administrador do Sistema e oferece um link para o login. A regra
de portas continua valendo após o login.

### v2.0.47-dev — aviso de acesso à internet

Quando o navegador segue o redirecionamento do Squid, o portal mostra o botão
**Ir para o login** e orienta a procurar o Administrador do Sistema em caso de
dificuldade. Em caso de erro no túnel HTTPS, abra o atalho **Entrar na Internet**
no Windows ou acesse diretamente o endereço HTTPS do portal, terminado em
`/acesso`. A página de orientação também pode ser aberta pelo endereço do
portal com `?aviso=1`.

### v2.0.15-dev — atalho Windows para abrir e encerrar o acesso

Atualize o Debian primeiro. No Windows, confie no certificado HTTPS do portal e mantenha o IP do gateway nas exceções de proxy. Na pasta `gwos/windows`, execute no PowerShell do usuário:

```powershell
.\Instalar-Atalho.ps1 -Portal https://192.168.0.1:8444/acesso
```

Para distribuição por GPO, publique os dois scripts assinados e execute o instalador no contexto do usuário. Defina Chrome, Edge ou Firefox como navegador padrão. Clique em **Entrar na Internet** para abrir o portal e autentique-se pela página aberta pelo atalho. O agente monitora janelas desses três navegadores na sessão Windows atual. Fechar o último solicita a revogação. Se o agente perder contato, a autorização vence após 45 segundos, com remoção no próximo ciclo do importador. As conexões TCP já abertas podem demorar a encerrar. Sessões iniciadas diretamente pelo endereço do portal seguem o prazo de inatividade.


### v2.0.16-dev — revisão do agente

- O login informa falha se o helper instalado não conseguir sincronizar o firewall. A recuperação remove apenas a sessão criada pela tentativa que falhou.
- A consulta de sessão do Squid mantém resultados positivos em cache por até dois segundos. A revogação afeta novas conexões. Túneis já estabelecidos podem durar até fechar.
- O agente mostra uma mensagem se o GWOS não confirmar o encerramento após as tentativas. Na perda de contato, o prazo de 45 segundos é verificado pelo importador no próximo ciclo.
- Foram removidas rotinas de cadastro e recuperação por e-mail sem chamadas. Contas antigas continuam aceitando e-mail no login. As migrations e os registros existentes foram preservados.


### v2.0.18-dev — monitor em segundo plano

Atualize o Debian e reserve um IP para a estação. No diretório instalado,
credencie a estação com `sudo php scripts/credenciar_monitor.php 192.168.0.12`.
O comando encerra a sessão atual e emite uma chave individual. No Windows,
na pasta `gwos/windows`, execute o instalador:

```powershell
.\Instalar-Monitor.ps1 -Portal https://192.168.0.1:8444/acesso
```

Informe a chave. Use HTTPS confiável e mantenha o IP do portal na exceção
central do proxy. Saia da sessão do Windows e entre novamente para iniciar
o monitor. O ícone do Portal Sistemas continua apontando para a URL normal.

O monitor acompanha Chrome, Edge e Firefox e pede a revogação ao detectar
o fechamento da última janela. Na perda de contato, a sessão vence após
45 segundos e é removida no próximo ciclo do importador. A revogação
bloqueia novas conexões. Túneis estabelecidos podem durar até fechar.
O credenciamento depende de IP fixo ou reserva DHCP. Instale o monitor
no perfil Windows utilizado para a navegação. Use uma sessão interativa
por estação. Após atualização, execute o teste em um IP sem grupo.


### v2.0.20-dev — credenciar pelo painel

No painel administrativo, abra **Acesso à internet com login → Monitor Windows**.
Informe o IPv4 reservado da estação e clique em **Gerar chave**. Escolha
**Baixar chave** ou copie o comando para o PowerShell e informe o código.
Ambas as opções usam o mesmo convite, que vale dez minutos e é consumido
no primeiro download. O download usa HTTPS com certificado confiável.
A emissão não substitui a chave atual; o resgate a substitui.
Use o conteúdo do arquivo baixado em **Instalar-Monitor.ps1** e depois
remova a cópia do arquivo da pasta Downloads.


### v2.0.22-dev — reinstalação do DNS

O módulo base deixa a integração do BIND9 para quando o módulo DNS estiver
registrado e os arquivos principais existirem. A instalação guarda os arquivos
originais do BIND9. A desinstalação restaura esses originais ou repõe arquivos
básicos em instalações legadas, preservando `named.conf.zonas-locais`.
Para recuperar uma instalação já incompleta, reaplique o módulo
`20-dns-bind9/instalar.sh` e confirme `named-checkconf` e `systemctl is-active named`.

### v2.0.25-dev — ativação automática do portal

A instalação completa, com banco MariaDB e Squid instalados antes do painel, ativa o portal HTTPS ao instalar ou reaplicar o módulo 60. O instalador exibe a URL do portal. O script de ativação manual continua disponível para diagnóstico ou ativação em instalações parciais.

### v2.0.27-dev — leitura da chave no Windows

O instalador do monitor procura primeiro na pasta do instalador e depois em Downloads um arquivo gwos-chave-IP.txt cujo IP corresponda ao computador. Se o arquivo estiver em outra pasta ou tiver sido renomeado, use o parâmetro `-ArquivoChave` com o caminho completo. A instalação deste script não exige atualizar o Debian que já fornece as chaves.

### v2.0.29-dev — diagnóstico do monitor

O monitor grava o último estado em `%LOCALAPPDATA%/GWOS/monitor-status.log`, sem gravar a chave. Presença HTTP 204 indica que o servidor aceitou o sinal.
