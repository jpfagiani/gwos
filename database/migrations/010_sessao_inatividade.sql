-- Sessão do portal por navegação: expira quando o computador para de navegar
-- (ex.: todos os navegadores fechados). Idempotente.
ALTER TABLE sessoes_internet ADD COLUMN IF NOT EXISTS ultimo_acesso DATETIME NULL AFTER criado_em;

ALTER TABLE sessoes_internet_historico
    MODIFY COLUMN motivo ENUM('logout_usuario','expirada','inatividade','revogada_admin','conta_desativada','senha_alterada','substituida','usuario_excluido') NOT NULL;

INSERT IGNORE INTO configuracoes (chave, valor, descricao) VALUES
('acesso_inatividade_min', '10',   'Minutos sem navegar para encerrar a sessão de login (mín. 3; 0 = só pelo limite de horas)'),
('acesso_atividade_modo',  'auto', 'O que conta como navegação: auto, navegador (só User-Agent de navegador) ou qualquer'),
('acesso_cadastro_direto', '0',    '1 = o usuário cria login e senha na hora, sem confirmar por e-mail (domínio institucional continua exigido)'),
('acesso_forcar_firewall', '1',    '1 = o firewall bloqueia a internet de IP sem grupo e sem sessão (inclui HTTPS fora do proxy e QUIC)');
