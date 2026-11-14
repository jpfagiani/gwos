CREATE TABLE IF NOT EXISTS convites_monitor (
    ip VARCHAR(45) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    codigo_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL UNIQUE,
    expira_em DATETIME NOT NULL
) ENGINE=InnoDB;
