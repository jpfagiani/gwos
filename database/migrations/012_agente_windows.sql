ALTER TABLE sessoes_internet
    ADD COLUMN IF NOT EXISTS agente_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    ADD COLUMN IF NOT EXISTS agente_expira_em DATETIME NULL;
