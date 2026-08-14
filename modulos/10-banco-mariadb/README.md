# 10-banco-mariadb — banco de dados

Fonte de grupos de IPs, domínios, horários, NAT 1:1 e relatórios. É de onde o
painel lê e é o que alimenta Squid, BIND9 e nftables.

## O que faz

- Instala o MariaDB
- Cria o banco `gwos`, o usuário `gwos` com senha aleatória e carrega
  `database/schema.sql` + as migrações de `database/migrations/`
- Grava as credenciais em `/etc/gwos/db.conf` (0600) e no `.env` do projeto
- Sincroniza a tabela `configuracoes` com os parâmetros de rede atuais
- Instala `/usr/local/sbin/gwos-senha-padrao`

## Instalação

```bash
bash instalar.sh              # preserva o banco se já existir
bash instalar.sh --recriar    # APAGA e recria do zero
```

Precisa do repositório completo (usa `database/schema.sql`).

## Senha do painel

O `schema.sql` traz um hash de exemplo. O `gwos-senha-padrao` o substitui pelo
hash de `gwos@2025` gerado nesta máquina — **só** enquanto ainda for o hash de
exemplo, para não derrubar a senha já trocada pelo administrador. Ele precisa
do PHP CLI; sem PHP, o módulo `60-painel-web` faz isso na sequência.

## Verificação

```bash
bash verificar.sh
```

Testa o serviço, a conexão com as credenciais salvas e a contagem de tabelas.
