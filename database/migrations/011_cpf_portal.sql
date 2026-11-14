ALTER TABLE usuarios_internet
    ADD COLUMN IF NOT EXISTS cpf CHAR(11) CHARACTER SET ascii COLLATE ascii_bin NULL,
    ADD UNIQUE INDEX IF NOT EXISTS uk_usuarios_internet_cpf (cpf);
