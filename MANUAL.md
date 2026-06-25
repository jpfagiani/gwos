# GWOS — Manual de Instalação e Uso

**Gateway Web OS** — Firewall, DNS, Proxy Squid com controle de acesso por grupos de IPs.

- **IP padrão:** 172.14.29.1
- **Painel web:** `http://172.14.29.1` (redireciona para HTTPS)
- **Login padrão:** `admin@gwos.local` / `gwos@2025`

---

## 1. Instalação do Zero

### Pré-requisitos

- Debian 12 ou 13 (instalação mínima)
- Duas interfaces de rede: uma para a LAN, uma para a WAN (internet)
- Acesso root
- Conexão com a internet

### Passo a Passo

```bash
# 1. Instalar git e clonar o repositório
apt install -y git
git clone https://github.com/jpfagiani/gwos.git /opt/gwos
cd /opt/gwos/install

# 2. Executar o instalador
bash install.sh
```

O instalador pergunta:
- Interface WAN (saída para internet)
- Interface LAN (rede interna)
- IP do gateway (ex: 172.14.29.1)
- Rede LAN (ex: 172.14.29.0/24)
- Senha do banco de dados

Ao final, exibe a URL de acesso, login e senha padrão.

> Após a instalação, acesse o painel e **troque a senha** no primeiro login.

---

## 2. Atualizar sem Reinstalar

```bash
gwos update
```

Faz `git pull` e copia os arquivos para o servidor web sem tocar em configurações.

---

## 3. Painel Web

### Acesso

- **URL:** `http://IP_DO_GATEWAY`
- **E-mail:** `admin@gwos.local`
- **Senha padrão:** `gwos@2025`

### Seções do painel

| Seção | Função |
|-------|--------|
| Dashboard | Acessos em tempo real, últimos 25 acessos, gráfico de banda, status dos serviços |
| Grupos | Criar e gerenciar grupos de IPs (Liberados, Parciais, Bloqueados) |
| IPs | Associar endereços IP a grupos |
| Domínios | Blacklist e whitelist de domínios/sites |
| Horários | Regras de liberação por dia/hora (horário livre, almoço, etc.) |
| NAT 1:1 | Redirecionamento de portas externas para IPs internos |
| DNS | Adicionar nomes internos (ex: `samba.cdpni.local → 172.14.29.11`) |
| Relatórios | Histórico de acessos por IP/domínio |
| Configurações | Parâmetros do sistema |

---

## 4. Grupos de IPs e Política de Acesso

Cada IP da rede deve ser cadastrado em um grupo para ter acesso à internet.

| Grupo | Comportamento |
|-------|---------------|
| **Liberados** | Acesso irrestrito à internet |
| **Parciais** | Acesso com restrições: blacklist de domínios e horários aplicados |
| **Bloqueados** | Apenas whitelist (sites obrigatórios/governo) |
| *(sem grupo)* | Bloqueado — nenhum acesso |

### Adicionar um IP

1. Painel → **Grupos** → selecione o grupo desejado
2. Clique em **Adicionar IP**
3. Informe o endereço IP e descrição

---

## 5. Blacklist e Whitelist de Domínios

### Blacklist (bloquear sites)

Painel → **Domínios** → **Blacklist** → Adicionar domínio

Depois clique em **Aplicar** para atualizar o Squid e o DNS (BIND9 RPZ).

Exemplos:
```
facebook.com
youtube.com
tiktok.com
```

### Whitelist (liberar sempre, mesmo para Bloqueados)

Painel → **Domínios** → **Whitelist** → Adicionar domínio

Usado para sites de governo, sistemas obrigatórios, etc. IPs do grupo Bloqueados conseguem acessar apenas esses sites.

### Aplicar mudanças no Squid

Após adicionar/remover domínios, clique em **Aplicar** no painel.  
Ou via terminal:

```bash
sudo /opt/gwos/scripts/gerar_squid_dominios.sh
```

---

## 6. Horários (Horário Livre)

Permite que IPs do grupo **Parciais** acessem sites da blacklist em horários determinados.

### Criar uma regra de horário livre

1. Painel → **Horários** → **Nova Regra**
2. Nome: ex. `Livre almoço`
3. Ação: `Permitir`
4. Horário: `11:00` até `13:00`
5. Dias: Seg a Sex
6. Grupo: deixar em branco (aplica a todos os Parciais)
7. Salvar → o Squid é atualizado automaticamente

### Horários padrão (pré-configurados na instalação)

| Nome | Horário | Dias |
|------|---------|------|
| Livre almoço (seg-sex) | 11:00–13:00 | Seg–Sex |
| Livre sábado | 08:00–17:00 | Sábado |
| Livre domingo | 08:00–17:00 | Domingo |

### Forçar atualização das regras no Squid

```bash
sudo /opt/gwos/scripts/gerar_squid_acl.sh
```

---

## 7. NAT 1:1 (Redirecionamento de Portas)

Painel → **NAT** → **Adicionar**

Exemplo: redirecionar porta 8080 da internet para o servidor Samba (porta 80):
- IP externo: `0.0.0.0` (qualquer)
- Porta externa: `8080`
- IP interno: `172.14.29.11`
- Porta interna: `80`

Ativar a regra após criar.

---

## 8. DNS Interno

Permite acessar servidores internos por nome em vez de IP.

```bash
# Adicionar
gwos dns add samba 172.14.29.11

# Listar
gwos dns list

# Atualizar IP
gwos dns update samba 172.14.29.12

# Remover
gwos dns del samba
```

Os nomes ficam disponíveis no domínio `.cdpni.local`:
- `samba.cdpni.local → 172.14.29.11`

Propagação em até 60 segundos.

---

## 9. Comando `gwos` (CLI)

Ferramenta de administração via terminal. Disponível após a instalação.

```bash
gwos <comando> [opções]
```

### Referência rápida

| Comando | Descrição |
|---------|-----------|
| `gwos status` | Status de todos os serviços |
| `gwos reload all` | Recarrega todos os serviços |
| `gwos reload squid` | Recarrega só o Squid |
| `gwos reload nginx` | Recarrega só o Nginx |
| `gwos diag` | Diagnóstico completo do sistema |
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

### Gerenciar senha do painel

```bash
# Resetar para gwos@2025 (padrão)
gwos senha

# Resetar para senha personalizada
gwos senha admin@gwos.local minhaSenha123

# Listar admins cadastrados
gwos senha listar

# Desbloquear conta bloqueada por tentativas excessivas
gwos desbloqueio admin@gwos.local
```

---

## 10. Serviços do Sistema

| Serviço | Função |
|---------|--------|
| `nginx` | Servidor web (painel PHP) |
| `php8.4-fpm` | PHP para o painel |
| `squid` | Proxy HTTP/HTTPS com SSL Bump |
| `named` (BIND9) | DNS com RPZ (bloqueio por domínio) |
| `gwos-dnsmasq` | DNS interno para `.cdpni.local` |
| `nftables` | Firewall e NAT |
| `mariadb` | Banco de dados do painel |

```bash
# Ver status de todos
gwos status

# Reiniciar serviço individualmente
systemctl restart squid
systemctl restart nginx
systemctl restart named
```

---

## 11. SSL Bump (Inspeção HTTPS)

O GWOS inspeciona tráfego HTTPS para aplicar a blacklist em conexões seguras.  
Para evitar alertas de certificado nos navegadores dos clientes:

1. Baixe o certificado CA: `http://IP_GATEWAY/gwos-ca.crt`
2. Instale como "Autoridade Certificadora Confiável" no navegador ou no Windows

---

## 12. Logs e Diagnóstico

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

## 13. Problemas Comuns

### Painel não abre / ERR_CONNECTION_REFUSED

```bash
systemctl status nginx
systemctl status php8.4-fpm
gwos status
```

### "Sem registros recentes" no dashboard

www-data precisa estar no grupo `proxy` para ler o log do Squid:

```bash
usermod -aG proxy www-data
systemctl restart php8.4-fpm
```

### Site bloqueado fora do horário incorreto

Verificar se as regras de horário foram geradas:

```bash
cat /etc/squid/conf.d/gwos_horarios.conf
```

Se estiver vazio, gerar manualmente:

```bash
sudo /opt/gwos/scripts/gerar_squid_acl.sh
```

### DNS não resolve domínios externos

```bash
systemctl status named
# Testar
dig google.com @127.0.0.1
```

### Conta do painel bloqueada

```bash
gwos desbloqueio admin@gwos.local
gwos senha
```

### Squid não inicia

```bash
squid -k parse          # verifica erros de configuração
journalctl -u squid -n 50
```
