CREATE TABLE IF NOT EXISTS monitores_internet (
    ip VARCHAR(45) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    chave_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    ciclo_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    presente_ate DATETIME NULL
) ENGINE=InnoDB;
