# GWOS — Manual de Instalação e Uso

**Gateway Web OS** — Firewall DNS + Proxy com controle de acesso por grupos de IPs.

---

## Índice

1. [Requisitos](#1-requisitos)
2. [Instalação](#2-instalação)
3. [Acesso ao Painel](#3-acesso-ao-painel)
4. [Configuração Inicial](#4-configuração-inicial)
5. [Configurar Clientes](#5-configurar-clientes)
6. [Uso Diário — Painel Web](#6-uso-diário--painel-web)
7. [Uso Diário — CLI](#7-uso-diário--cli)
8. [Grupos de Acesso](#8-grupos-de-acesso)
9. [Horários Liberados](#9-horários-liberados)
10. [DNS Interno](#10-dns-interno)
11. [NAT 1:1](#11-nat-11)
12. [Manutenção](#12-manutenção)
13. [Solução de Problemas](#13-solução-de-problemas)

---

## 1. Requisitos

### Hardware mínimo
| Recurso | Mínimo |
|---------|--------|
| CPU | 2 cores |
| RAM | 2 GB |
| Disco | 20 GB |
| Interfaces de rede | 2 (LAN + WAN) |

### Sistema operacional
- **Debian 13** (Trixie) — recomendado
- Debian 12 (Bookworm) — compatível

### Pré-requisitos
- Acesso root ao servidor
- Interfaces de rede identificadas (ex: `eth0` = WAN, `eth1` = LAN)
- IP fixo na interface LAN (ex: `192.168.0.1/24`)
- Conexão com a internet na WAN

---

## 2. Instalação

### 2.1 Clone o repositório

```bash
apt update && apt install -y git
git clone https://github.com/jpfagiani/gwos /opt/gwos
cd /opt/gwos
```

### 2.2 Execute o instalador

```bash
bash install/install.sh
```

O instalador irá perguntar:

| Pergunta | Exemplo |
|----------|---------|
| Interface WAN | `eth0` |
| Interface LAN | `eth1` |
| Rede LAN (CIDR) | `192.168.0.0/24` |
| IP do gateway (LAN) | `192.168.0.1` |
| Senha do banco de dados | (escolha uma senha forte) |
| Senha do admin do painel | (escolha uma senha forte) |

### 2.3 O que o instalador faz automaticamente

- Instala: Squid 6, BIND9, nginx, PHP 8.4-FPM, MariaDB, nftables
- Configura o banco de dados `gwos` com schema e dados iniciais
- Gera o certificado CA do GWOS para SSL Bump
- Configura o proxy transparente (portas 3128/3129) e explícito (porta 3127)
- Ativa o firewall nftables com NAT e redirecionamento de tráfego
- Cria o comando `gwos` disponível globalmente
- Exibe ao final o endereço para baixar o certificado CA

### 2.4 Ao final da instalação

O instalador exibe um resumo como:

```
========================================
  GWOS instalado com sucesso!
========================================
  Painel:     http://192.168.0.1
  Login:      admin@gwos.local
  Senha:      (a senha que você definiu)
  CA cert:    http://192.168.0.1/gwos-ca.crt
========================================
```

---

## 3. Acesso ao Painel

Abra o browser em qualquer máquina da LAN e acesse:

```
http://192.168.0.1
```

Use as credenciais definidas durante a instalação.

---

## 4. Configuração Inicial

### 4.1 Gerar listas de domínios

Após a instalação, gere as listas de domínios bloqueados/whitelist:

```bash
sudo bash /opt/gwos/scripts/gerar_squid_dominios.sh
```

### 4.2 Gerar ACLs de horários

```bash
sudo bash /opt/gwos/scripts/gerar_squid_acl.sh
```

### 4.3 Aplicar regras

```bash
sudo bash /opt/gwos/scripts/aplicar_nftables.sh
```

Ou use o comando `gwos`:

```bash
gwos reload
```

---

## 5. Configurar Clientes

### 5.1 Instalar o Certificado CA (obrigatório para HTTPS)

O certificado é necessário para que o Squid possa inspecionar tráfego HTTPS sem erros no browser.

**Windows:**
1. Acesse `http://192.168.0.1/gwos-ca.crt` no browser do cliente
2. Clique em "Abrir" no arquivo baixado
3. Clique em "Instalar Certificado"
4. Selecione "Computador Local" → Avançar
5. Selecione "Colocar todos os certificados no repositório a seguir"
6. Clique em "Procurar" → selecione **"Autoridades de Certificação Raiz Confiáveis"**
7. OK → Avançar → Concluir
8. Reinicie o browser

**Linux:**
```bash
wget http://192.168.0.1/gwos-ca.crt -O /usr/local/share/ca-certificates/gwos-ca.crt
update-ca-certificates
```

### 5.2 Configurar DNS

Configure os clientes para usar o gateway como DNS:
- **DNS primário:** `192.168.0.1`
- **DNS secundário:** `8.8.8.8` (fallback)

### 5.3 Proxy (opcional — modo explícito)

Se precisar de NAT 1:1 ou preferir proxy explícito:
- **Servidor proxy:** `192.168.0.1`
- **Porta:** `3127`

Se não configurar proxy no cliente, o tráfego é interceptado automaticamente (proxy transparente) via nftables — portas 80 e 443.

---

## 6. Uso Diário — Painel Web

### 6.1 Dashboard

Exibe resumo do sistema:
- Grupos ativos, IPs gerenciados, domínios, regras NAT
- Últimos acessos registrados (IP, domínio, requisições, tráfego)
- Status dos serviços (Squid, BIND9, nftables, nginx, MariaDB)

### 6.2 Grupos & IPs

Gerencia quem pode acessar o quê.

**Criar um grupo:**
1. Clique em **+ Novo Grupo**
2. Defina nome e tipo:
   - `bloqueado` — só acessa whitelist e sites do governo
   - `parcial` — acessa internet, exceto streaming/redes sociais (liberados nos horários)
   - `liberado` — acesso total à internet

**Adicionar IPs ao grupo:**
1. Clique no botão de IPs do grupo (ícone com número)
2. Digite o IP ou faixa CIDR (ex: `192.168.0.20` ou `192.168.0.0/24`)
3. Clique **+ Adicionar**

**Aplicar as regras após modificar IPs:**
1. Clique em **▶ Aplicar nftables** na página de Grupos

> Isso atualiza automaticamente os arquivos do Squid e as regras do nftables.

### 6.3 Domínios

Gerencia listas de domínios:
- **whitelist** — sempre acessível para todos
- **blacklist** — bloqueado para parciais (exceto nos horários liberados)
- **sites_livres** — acessível para todos sem restrição

**Adicionar domínio:**
1. Acesse **Domínios** no menu
2. Clique em **+ Novo Domínio**
3. Informe o domínio e categoria
4. Clique em **Salvar**

Após adicionar domínios, regenere as listas:
```bash
gwos reload
```

### 6.4 Horários

Define períodos em que a blacklist é ignorada para o grupo `parcial`.

**Horários padrão (seg-sex):**
| Período | Horário |
|---------|---------|
| Manhã cedo | 07:00 – 08:00 |
| Almoço | 11:00 – 13:00 |
| Fim de expediente | 17:00 – 18:00 |
| Noite | 19:00 – 23:00 |

Sábado e domingo: dia inteiro liberado.

### 6.5 NAT 1:1

Associa um IP externo fixo a um IP interno (útil para sistemas que exigem IP de saída específico).

1. Acesse **NAT 1:1** no menu
2. Clique em **+ Nova Regra**
3. Informe IP interno (cliente) e IP externo (saída)
4. Aplique via **▶ Aplicar nftables**

### 6.6 Relatórios

Exibe histórico de acessos filtrado por data, com paginação.

### 6.7 Configurações

Permite alterar parâmetros gerais como nome do sistema, interfaces de rede, portas, etc.

---

## 7. Uso Diário — CLI

O comando `gwos` está disponível para o usuário root:

```bash
gwos <comando>
```

| Comando | Descrição |
|---------|-----------|
| `gwos status` | Exibe status de todos os serviços |
| `gwos reload` | Regenera ACLs, domínios e aplica nftables |
| `gwos nat` | Reaplica apenas as regras NAT/nftables |
| `gwos grupo list` | Lista grupos e IPs |
| `gwos dominio list` | Lista domínios cadastrados |
| `gwos log` | Exibe últimas linhas do log do Squid |
| `gwos backup` | Gera backup do banco de dados |
| `gwos diag` | Diagnóstico completo do sistema |

**Exemplos:**

```bash
# Ver status dos serviços
gwos status

# Após qualquer mudança no painel, aplique:
gwos reload

# Ver últimos acessos
gwos log

# Criar backup
gwos backup
```

---

## 8. Grupos de Acesso

### Como funciona

O GWOS classifica cada IP em um grupo e aplica políticas diferentes:

| Grupo | YouTube/Redes Sociais | Sites Gov | Whitelist | Internet Geral |
|-------|----------------------|-----------|-----------|----------------|
| **bloqueado** | ❌ | ✅ | ✅ | ❌ |
| **parcial** | ✅ só nos horários | ✅ | ✅ | ✅ (exceto blacklist) |
| **liberado** | ✅ | ✅ | ✅ | ✅ |
| **sem grupo** | ❌ | ✅ | ✅ | ❌ |

> IPs sem grupo recebem o mesmo tratamento que o grupo `bloqueado`.

### Fluxo de aplicação

```
Adicionar IP no painel
        ↓
Clicar "Aplicar nftables"  (ou: gwos reload)
        ↓
Script atualiza arquivos Squid + regras nftables
        ↓
Squid recarregado automaticamente
```

---

## 9. Horários Liberados

Os horários são gerados automaticamente a partir do banco de dados.

**Para adicionar ou modificar horários:**
1. Acesse **Horários** no painel
2. Crie ou edite os períodos
3. Execute no servidor:
```bash
sudo bash /opt/gwos/scripts/gerar_squid_acl.sh
squid -k reconfigure
```

Ou simplesmente:
```bash
gwos reload
```

---

## 10. DNS Interno

O GWOS usa BIND9 como resolvedor DNS local com:
- **RPZ (Response Policy Zone)** para bloquear domínios da blacklist no nível DNS
- **Forward zones** para domínios internos do governo

### Domínios internos pré-configurados

| Domínio | DNS interno |
|---------|-------------|
| `cartoriosap.sp.gov.br` | `10.1.6.222` |
| `prodesp.sp.gov.br` | `10.1.6.222` |
| `policiapenal.sp.gov.br` | `10.14.8.20` |

Para adicionar novos domínios internos, edite `/etc/bind/named.conf.local`:

```bind
zone "exemplo.sp.gov.br" {
    type forward;
    forward only;
    forwarders { 10.x.x.x; };
};
```

Depois recarregue:
```bash
rndc reload
rndc flush
```

---

## 11. NAT 1:1

Permite que um cliente interno saia sempre com um IP externo específico.

**Pré-requisito:** o IP externo deve estar configurado na interface WAN do servidor.

**Adicionar via painel:**
1. Menu **NAT 1:1** → **+ Nova Regra**
2. IP Interno: `192.168.0.50`
3. IP Externo: `203.0.113.10`
4. Salvar → **▶ Aplicar nftables**

---

## 12. Manutenção

### Atualizar o GWOS

```bash
cd /opt/gwos
git pull
# Atualizar squid.conf se necessário:
cp config/squid.conf /etc/squid/squid.conf
squid -k parse && systemctl restart squid
gwos reload
```

### Backup manual

```bash
gwos backup
# Arquivo salvo em /opt/gwos/backups/
```

### Restaurar backup

```bash
sudo bash /opt/gwos/scripts/restaurar_backup.sh /opt/gwos/backups/gwos_YYYYMMDD.sql.gz
```

### Verificar logs

```bash
# Log do Squid (acessos)
tail -f /var/log/squid/access.log

# Log do nginx (erros do painel)
tail -f /var/log/nginx/error.log

# Log do BIND9
journalctl -u named --no-pager -n 50
```

### Reiniciar serviços

```bash
systemctl restart squid
systemctl restart named
systemctl restart nginx
systemctl restart php8.4-fpm
nft -f /etc/nftables.conf   # reaplicar regras nftables
```

---

## 13. Solução de Problemas

### Painel não abre (ERR_CONNECTION_REFUSED)

```bash
systemctl status nginx
systemctl status php8.4-fpm
# Verifique se nftables está redirecionando a porta 80 para o Squid
nft list ruleset | grep "dport 80"
```

### Painel abre mas dá erro 500

```bash
tail -20 /var/log/nginx/error.log
```

### Clientes sem internet

```bash
# 1. Verificar se Squid está rodando
systemctl status squid
ss -tlnp | grep squid   # deve mostrar 3127, 3128, 3129

# 2. Verificar nftables
systemctl status nftables
nft list ruleset

# 3. Reaplicar tudo
gwos reload
```

### Squid não inicia

```bash
squid -k parse   # mostra erros de configuração
journalctl -u squid --no-pager -n 30
```

### DNS não resolve domínios do governo

```bash
# Testar resolução local
dig @127.0.0.1 new.cartoriosap.sp.gov.br

# Se NXDOMAIN, limpar cache do BIND
rndc flush
dig @127.0.0.1 new.cartoriosap.sp.gov.br

# Verificar se forward zones estão carregadas
named-checkconf -z
```

### Site bloqueado que deveria estar liberado

```bash
# Ver o que o Squid está fazendo
tail -f /var/log/squid/access.log | grep <ip-cliente>

# Verificar horários ativos
cat /etc/squid/conf.d/gwos_horarios.conf

# Verificar se IP está no grupo correto
gwos grupo list

# Regenerar ACLs
gwos reload
```

### Certificado CA não confiado no cliente

Reinstale o certificado seguindo a seção [5.1](#51-instalar-o-certificado-ca-obrigatório-para-https).

---

## Portas utilizadas

| Porta | Protocolo | Serviço | Descrição |
|-------|-----------|---------|-----------|
| 53 | UDP/TCP | BIND9 | DNS |
| 80 | TCP | nginx | Painel web |
| 3127 | TCP | Squid | Proxy explícito (configurar nos clientes) |
| 3128 | TCP | Squid | Proxy transparente HTTP |
| 3129 | TCP | Squid | Proxy transparente HTTPS (SSL Bump) |

---

## Arquivos importantes

| Arquivo | Descrição |
|---------|-----------|
| `/opt/gwos/.env` | Configurações do sistema (banco, interfaces) |
| `/etc/squid/squid.conf` | Configuração do Squid |
| `/etc/squid/conf.d/gwos_horarios.conf` | ACLs de horários (gerado automaticamente) |
| `/etc/squid/conf.d/gwos_ips_parciais.txt` | IPs do grupo parcial |
| `/etc/squid/conf.d/gwos_ips_bloqueados.txt` | IPs do grupo bloqueado |
| `/etc/squid/conf.d/gwos_ips_liberados.txt` | IPs do grupo liberado |
| `/etc/bind/named.conf.local` | Zonas DNS (forward zones) |
| `/etc/nftables.conf` | Regras de firewall/NAT |
| `/var/log/squid/access.log` | Log de acessos |
| `/opt/gwos/backups/` | Backups do banco de dados |

---

*GWOS — Gateway Web OS | github.com/jpfagiani/gwos*
