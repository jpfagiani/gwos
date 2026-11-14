<?php

namespace App\Core;

/**
 * Acesso à internet com login (portal cativo).
 *
 * O portal cadastra usuários por CPF e autoriza o endereço IP do cliente.
 * O Squid lê o espelho de sessões, incluindo a identidade interna da conta.
 */
class AcessoInternet
{
    public const SESSOES_ARQ = '/var/lib/gwos/sessions/sessoes.txt';

    private const MAX_TENTATIVAS   = 5;
    private const BLOQUEIO_MIN     = 15;
    private const TOKEN_REDEFINIR  = 30;    // minutos
    private const MAX_TOKENS_IP    = 10;    // por hora, por IP de origem

    // ── configuração ─────────────────────────────────────────────────────────
    public static function cfg(string $chave, string $padrao = ''): string
    {
        try {
            $v = Database::valor('SELECT valor FROM configuracoes WHERE chave = ?', [$chave]);
            return ($v === false || $v === null || $v === '') ? $padrao : (string) $v;
        } catch (\Throwable) {
            return $padrao;
        }
    }

    public static function dominioPermitido(): string
    {
        return strtolower(ltrim(self::cfg('acesso_dominio_email', 'sap.sp.gov.br'), '@'));
    }

    private static function tamanho(string $s): int
    {
        return function_exists('mb_strlen') ? mb_strlen($s) : strlen($s);
    }

    public static function normalizarEmail(string $email): string
    {
        return strtolower(trim($email));
    }

    public static function ipCliente(): string
    {
        return $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    }

    private static function excedeuLimiteIp(string $ip): bool
    {
        $desde = date('Y-m-d H:i:s', time() - 3600);
        return (int) Database::valor(
            'SELECT COUNT(*) FROM tokens_internet WHERE ip = ? AND criado_em > ?', [$ip, $desde]
        ) >= self::MAX_TOKENS_IP;
    }

    public static function tokenValido(string $token): ?array
    {
        if (!preg_match('/^[a-f0-9]{64}$/', $token)) {
            return null;
        }
        $linha = Database::fetch(
            'SELECT t.id AS token_id, t.tipo, u.*
               FROM tokens_internet t JOIN usuarios_internet u ON u.id = t.usuario_id
              WHERE t.token_hash = ? AND t.usado_em IS NULL AND t.expira_em > ? AND u.ativo = 1',
            [hash('sha256', $token), date('Y-m-d H:i:s')]
        );
        return $linha ?: null;
    }

    /** Define a senha a partir do link (cadastro novo ou redefinição). */
    public static function definirSenha(string $token, string $senha, string $confirmar): array
    {
        $erro = self::validarSenha($senha);
        if ($erro) {
            return [false, $erro];
        }
        if ($senha !== $confirmar) {
            return [false, 'As senhas não coincidem.'];
        }

        $t = self::tokenValido($token);
        if (!$t) {
            return [false, 'Link inválido ou expirado. Peça um novo.'];
        }

        $pdo = Database::conectar();
        $pdo->beginTransaction();
        try {
            $u = Database::fetch('SELECT ativo FROM usuarios_internet WHERE id=? FOR UPDATE', [$t['id']]);
            if (!$u || !$u['ativo']) {
                $pdo->rollBack();
                return [false, 'Código inválido ou expirado.'];
            }
            // "usado_em IS NULL" no UPDATE garante uso único mesmo com duas abas
            $usou = Database::execute(
                'UPDATE tokens_internet SET usado_em = ? WHERE id = ? AND usado_em IS NULL AND expira_em > NOW()',
                [date('Y-m-d H:i:s'), $t['token_id']]
            );
            if ($usou !== 1) {
                $pdo->rollBack();
                return [false, 'Link inválido ou expirado. Peça um novo.'];
            }
            Database::execute(
                'UPDATE usuarios_internet
                    SET senha = ?, confirmado_em = COALESCE(confirmado_em, ?), tentativas = 0, bloqueado_ate = NULL
                  WHERE id = ?',
                [password_hash($senha, PASSWORD_BCRYPT, ['cost' => 12]), date('Y-m-d H:i:s'), $t['id']]
            );
            // Preserva o histórico antes de encerrar sessões por troca de senha.
            foreach (Database::fetchAll('SELECT s.*,u.nome,u.email FROM sessoes_internet s JOIN usuarios_internet u ON u.id=s.usuario_id WHERE s.usuario_id=? FOR UPDATE', [$t['id']]) as $sessao) self::arquivarSessao($sessao, 'senha_alterada');
            Database::execute('DELETE FROM sessoes_internet WHERE usuario_id = ?', [$t['id']]);
            $pdo->commit();
        } catch (\Throwable $e) {
            $pdo->rollBack();
            error_log('[GWOS acesso] definirSenha: ' . $e->getMessage());
            return [false, 'Erro interno ao gravar a senha.'];
        }

        self::sincronizar();
        return [true, 'Senha criada! Faça o login para liberar a internet.'];
    }

    // ── gestão pelo administrador ───────────────────────────────────────────
    public static function normalizarCpf(string $valor): ?string
    {
        $cpf = preg_replace('/[.\- ]/', '', trim($valor));
        if (!preg_match('/^[0-9]{11}$/D', $cpf) || preg_match('/^(.)\1{10}$/D', $cpf)) {
            return null;
        }
        for ($tamanho = 9; $tamanho <= 10; $tamanho++) {
            $soma = 0;
            for ($i = 0; $i < $tamanho; $i++) {
                $soma += (int) $cpf[$i] * ($tamanho + 1 - $i);
            }
            if ((int) $cpf[$tamanho] !== ((10 * $soma) % 11) % 10) return null;
        }
        return $cpf;
    }

    public static function cadastrarCpf(string $nome, string $valorCpf, string $senha, ?string $ip = null): array
    {
        $nome = trim(preg_replace('/\s+/', ' ', $nome));
        if (self::tamanho($nome) > 100 || !preg_match('/\p{L}+.*\s+.*\p{L}+/u', $nome)) {
            return [false, 'Informe o nome completo.'];
        }
        $cpf = self::normalizarCpf($valorCpf);
        if ($cpf === null) return [false, 'Informe um CPF válido.'];
        if ($erro = self::validarSenha($senha)) return [false, $erro];
        if ($ip !== null && self::excedeuLimiteIp($ip)) {
            return [false, 'Muitos cadastros deste computador. Tente novamente mais tarde.'];
        }

        $pdo = Database::conectar();
        $pdo->beginTransaction();
        try {
            // Preserva a identidade histórica dos logs sem enviar CPF ao Squid.
            $identidade = 'conta-' . bin2hex(random_bytes(16)) . '@gwos.invalid';
            $agora = date('Y-m-d H:i:s');
            $id = (int) Database::insert(
                'INSERT INTO usuarios_internet (nome, email, cpf, senha, confirmado_em) VALUES (?, ?, ?, ?, ?)',
                [$nome, $identidade, $cpf, password_hash($senha, PASSWORD_BCRYPT, ['cost' => 12]), $agora]
            );
            if ($ip !== null) {
                Database::insert(
                    "INSERT INTO tokens_internet (usuario_id,tipo,token_hash,expira_em,usado_em,ip) VALUES (?, 'confirmar', ?, ?, ?, ?)",
                    [$id, hash('sha256', random_bytes(32)), $agora, $agora, $ip]
                );
            }
            $pdo->commit();
            return [true, $id];
        } catch (\PDOException $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            if ((int) ($e->errorInfo[1] ?? 0) === 1062) {
                return [false, 'Não foi possível cadastrar esse CPF. Se já tem conta, entre ou procure o administrador.'];
            }
            throw $e;
        }
    }

    /** Define/redefine a senha de um usuário (admin digita). Encerra as sessões dele. */
    public static function definirSenhaAdmin(int $id, string $senha): array
    {
        if ($erro = self::validarSenha($senha)) {
            return [false, $erro];
        }
        $u = Database::fetch('SELECT id FROM usuarios_internet WHERE id = ?', [$id]);
        if (!$u) {
            return [false, 'Usuário não encontrado.'];
        }
        Database::execute(
            'UPDATE usuarios_internet SET senha = ?, confirmado_em = COALESCE(confirmado_em, ?), tentativas = 0, bloqueado_ate = NULL WHERE id = ?',
            [password_hash($senha, PASSWORD_BCRYPT, ['cost' => 12]), date('Y-m-d H:i:s'), $id]
        );
        Database::execute('UPDATE tokens_internet SET usado_em = ? WHERE usuario_id = ? AND usado_em IS NULL', [date('Y-m-d H:i:s'), $id]);
        foreach (Database::fetchAll('SELECT s.*,u.nome,u.email FROM sessoes_internet s JOIN usuarios_internet u ON u.id=s.usuario_id WHERE s.usuario_id=?', [$id]) as $sessao) {
            self::arquivarSessao($sessao, 'senha_alterada');
        }
        Database::execute('DELETE FROM sessoes_internet WHERE usuario_id = ?', [$id]);
        self::sincronizar();
        return [true, 'Senha definida.'];
    }

    /** Invalida a senha anterior e emite um código de uso único. */
    public static function gerarLinkAdmin(int $id): ?array
    {
        $pdo = Database::conectar();
        $token = bin2hex(random_bytes(32));
        $pdo->beginTransaction();
        try {
            $u = Database::fetch('SELECT nome FROM usuarios_internet WHERE id=? AND ativo=1 FOR UPDATE', [$id]);
            if (!$u) {
                $pdo->rollBack();
                return null;
            }
            $agora = date('Y-m-d H:i:s');
            Database::execute(
                'UPDATE usuarios_internet SET senha=?, tentativas=0, bloqueado_ate=NULL WHERE id=?',
                [password_hash(bin2hex(random_bytes(32)), PASSWORD_BCRYPT, ['cost' => 12]), $id]
            );
            Database::execute('UPDATE tokens_internet SET usado_em=? WHERE usuario_id=? AND usado_em IS NULL', [$agora, $id]);
            Database::insert(
                "INSERT INTO tokens_internet (usuario_id,tipo,token_hash,expira_em,ip) VALUES (?, 'redefinir', ?, ?, 'admin')",
                [$id, hash('sha256', $token), date('Y-m-d H:i:s', time() + self::TOKEN_REDEFINIR * 60)]
            );
            foreach (Database::fetchAll(
                'SELECT s.*,u.nome,u.email FROM sessoes_internet s JOIN usuarios_internet u ON u.id=s.usuario_id WHERE s.usuario_id=? FOR UPDATE',
                [$id]
            ) as $sessao) {
                self::arquivarSessao($sessao, 'senha_alterada');
            }
            Database::execute('DELETE FROM sessoes_internet WHERE usuario_id=?', [$id]);
            $pdo->commit();
        } catch (\Throwable $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            throw $e;
        }
        return ['codigo' => $token, 'minutos' => self::TOKEN_REDEFINIR, 'nome' => $u['nome'], 'sincronizado' => self::sincronizar()];
    }

    public static function validarSenha(string $senha): ?string
    {
        if (!preg_match('/^(?=.*[A-Za-z])(?=.*[0-9])[A-Za-z0-9]{8,72}$/D', $senha)) {
            return 'Use de 8 a 72 caracteres, com pelo menos uma letra e um número.';
        }
        return null;
    }

    // ── login / sessão ──────────────────────────────────────────────────────
    /** @return array{0:bool,1:string,2:?array} [ok, mensagem, usuário] */
    public static function entrar(string $login, string $senha, string $ip, ?string $agente = null): array
    {
        if ($agente !== null && !preg_match('/^[a-f0-9]{64}$/D', $agente)) {
            return [false, 'Reabra o portal pelo atalho para iniciar a sessão.', null];
        }
        $falha = 'CPF ou senha incorretos, ou cadastro indisponível.';
        $cpf = self::normalizarCpf($login);
        $usuario = $cpf !== null
            ? Database::fetch('SELECT * FROM usuarios_internet WHERE cpf=?', [$cpf])
            : Database::fetch('SELECT * FROM usuarios_internet WHERE cpf IS NULL AND email=?', [self::normalizarEmail($login)]);

        if (!$usuario) {
            // Gasta o mesmo tempo de um login real (não revela se o e-mail existe)
            password_verify($senha, '$2y$12$LRGqTqHtKpZxFDfRVh237eTgCb4m2VvkDVum2cTnjQwXQlljO/94G');
            return [false, $falha, null];
        }

        if ($usuario['bloqueado_ate'] && time() < strtotime($usuario['bloqueado_ate'])) {
            return [false, 'Muitas tentativas. Tente novamente em alguns minutos ou use "Esqueci minha senha".', null];
        }

        if (!password_verify($senha, $usuario['senha']) || !(int) $usuario['ativo'] || !$usuario['confirmado_em']) {
            $tent = (int) $usuario['tentativas'] + 1;
            $bloq = null;
            if ($tent >= self::MAX_TENTATIVAS) {
                $bloq = date('Y-m-d H:i:s', time() + self::BLOQUEIO_MIN * 60);
                $tent = 0;
            }
            Database::execute('UPDATE usuarios_internet SET tentativas = ?, bloqueado_ate = ? WHERE id = ?',
                [$tent, $bloq, $usuario['id']]);
            return [false, $falha, null];
        }

        $maxSessoes = max(1, min(20, (int) self::cfg('acesso_max_sessoes_usuario', '3')));
        $horas  = max(1, (int) self::cfg('acesso_sessao_horas', '8'));
        $expira = date('Y-m-d H:i:s', time() + $horas * 3600);
        $pdo = Database::conectar();
        $pdo->beginTransaction();
        try {
            // Serializa logins da mesma conta para impedir que duas requisições
            // concorrentes ultrapassem o limite de dispositivos ativos.
            $atual = Database::fetch('SELECT senha, ativo FROM usuarios_internet WHERE id=? FOR UPDATE', [$usuario['id']]);
            if (!$atual || !$atual['ativo'] || !hash_equals($usuario['senha'], $atual['senha'])) {
                $pdo->rollBack();
                return [false, $falha, null];
            }
            $monitor = Database::fetch(
                'SELECT ciclo_hash, presente_ate>NOW() AS presente FROM monitores_internet WHERE ip=? FOR UPDATE',
                [$ip]
            );
            if ($monitor && (!$monitor['presente'] || !$monitor['ciclo_hash'])) {
                $pdo->rollBack();
                return [false, 'Monitor GWOS indisponível. Abra um navegador monitorado e tente novamente.', null];
            }
            $agenteHash = $monitor ? $monitor['ciclo_hash'] : ($agente === null ? null : hash('sha256', $agente));
            $sessoesEmOutrosIps = (int) Database::valor(
                'SELECT COUNT(*) FROM sessoes_internet WHERE usuario_id=? AND ip<>? AND expira_em>NOW()',
                [$usuario['id'], $ip]
            );
            if ($sessoesEmOutrosIps >= $maxSessoes) {
                $pdo->rollBack();
                return [false, 'Limite de dispositivos simultâneos atingido. Encerre uma sessão ativa ou contate o administrador.', null];
            }
            // Um IP tem no máximo uma sessão; arquiva a anterior antes de assumir a máquina.
            $anterior=Database::fetch('SELECT s.*,u.nome,u.email FROM sessoes_internet s JOIN usuarios_internet u ON u.id=s.usuario_id WHERE s.ip=? FOR UPDATE', [$ip]);
            if ($anterior) self::arquivarSessao($anterior, 'substituida');
            $grupos=implode(' / ', Monitoramento::gruposParaIp($ip));
            Database::execute(
                'REPLACE INTO sessoes_internet (usuario_id, ip, expira_em, ultimo_acesso, grupo_snapshot, agente_hash, agente_expira_em) VALUES (?, ?, ?, ?, ?, ?, ?)',
                [$usuario['id'], $ip, $expira, date('Y-m-d H:i:s'), $grupos ?: null,
                 $agenteHash,
                 $agenteHash === null ? null : date('Y-m-d H:i:s', time() + 45)]
            );
            $sessaoId = (int) $pdo->lastInsertId();
            Database::execute(
                'UPDATE usuarios_internet SET tentativas = 0, bloqueado_ate = NULL, ultimo_login = ? WHERE id = ?',
                [date('Y-m-d H:i:s'), $usuario['id']]
            );
            $pdo->commit();
        } catch (\Throwable $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            error_log('[GWOS acesso] criar sessão: ' . $e->getMessage());
            return [false, 'Não foi possível liberar o acesso (erro interno). Avise o administrador.', null];
        }

        if (!self::sincronizar()) {
            Database::execute('DELETE FROM sessoes_internet WHERE id = ?', [$sessaoId]);
            self::sincronizar();
            return [false, 'Não foi possível liberar o acesso. Avise o administrador.', null];
        }

        $usuario['expira_em'] = $expira;
        return [true, 'Acesso liberado.', $usuario];
    }

    public static function atualizarMonitor(string $ip, string $chave, string $ciclo, string $acao): bool
    {
        $chaveHash = hash('sha256', $chave);
        $monitor = Database::fetch('SELECT chave_hash FROM monitores_internet WHERE ip=?', [$ip]);
        if (!$monitor || !hash_equals($monitor['chave_hash'], $chaveHash)) return false;

        $cicloHash = hash('sha256', $ciclo);
        if ($acao === 'presenca') {
            Database::execute(
                'UPDATE monitores_internet SET ciclo_hash=?, presente_ate=DATE_ADD(NOW(), INTERVAL 20 SECOND)
                  WHERE ip=? AND chave_hash=?',
                [$cicloHash, $ip, $chaveHash]
            );
        } else {
            Database::execute(
                'UPDATE monitores_internet SET ciclo_hash=NULL, presente_ate=NULL
                  WHERE ip=? AND chave_hash=? AND ciclo_hash=?',
                [$ip, $chaveHash, $cicloHash]
            );
        }
        self::atualizarAgente($ip, $ciclo, $acao);
        return true;
    }

    public static function atualizarAgente(string $ip, string $token, string $acao): void
    {
        $hash = hash('sha256', $token);
        if ($acao === 'presenca') {
            Database::execute(
                'UPDATE sessoes_internet SET agente_expira_em=DATE_ADD(NOW(), INTERVAL 45 SECOND)
                  WHERE ip=? AND agente_hash=? AND agente_expira_em>NOW() AND expira_em>NOW()',
                [$ip, $hash]
            );
            return;
        }
        $pdo = Database::conectar();
        $pdo->beginTransaction();
        try {
            $sessao = Database::fetch(
                'SELECT s.*,u.nome,u.email FROM sessoes_internet s JOIN usuarios_internet u ON u.id=s.usuario_id
                  WHERE s.ip=? AND s.agente_hash=? FOR UPDATE',
                [$ip, $hash]
            );
            if ($sessao) {
                self::arquivarSessao($sessao, 'logout_usuario');
                Database::execute('DELETE FROM sessoes_internet WHERE id=?', [$sessao['id']]);
            }
            $pdo->commit();
        } catch (\Throwable $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            throw $e;
        }
        if ($sessao && !self::sincronizar()) {
            throw new \RuntimeException('Falha ao publicar encerramento da sessão.');
        }
    }

    public static function sessaoDoIp(string $ip): ?array
    {
        $s = Database::fetch(
            'SELECT s.*, u.nome, u.email FROM sessoes_internet s JOIN usuarios_internet u ON u.id = s.usuario_id
              WHERE s.ip = ? AND s.expira_em > ? AND (s.agente_expira_em IS NULL OR s.agente_expira_em > NOW()) AND u.ativo = 1',
            [$ip, date('Y-m-d H:i:s')]
        );
        return $s ?: null;
    }

    public static function sair(string $ip): void
    {
        $s=Database::fetch('SELECT s.*,u.nome,u.email FROM sessoes_internet s JOIN usuarios_internet u ON u.id=s.usuario_id WHERE s.ip=?',[$ip]); if($s) self::arquivarSessao($s,'logout_usuario');
        Database::execute('DELETE FROM sessoes_internet WHERE ip = ?', [$ip]);
        self::sincronizar();
    }

    // ── administração ───────────────────────────────────────────────────────
    public static function sessoesAtivas(): array
    {
        return Database::fetchAll(
            'SELECT s.id, s.ip, s.criado_em, s.ultimo_acesso, s.expira_em, u.nome, u.email
               FROM sessoes_internet s JOIN usuarios_internet u ON u.id = s.usuario_id
              WHERE s.expira_em > ? ORDER BY s.criado_em DESC',
            [date('Y-m-d H:i:s')]
        );
    }

    public static function usuarios(): array
    {
        return Database::fetchAll(
            'SELECT id, nome, email, RIGHT(cpf, 4) AS cpf_final, ativo, confirmado_em, ultimo_login, criado_em, bloqueado_ate
               FROM usuarios_internet ORDER BY nome'
        );
    }

    public static function derrubarSessao(int $id): void
    {
        $s=Database::fetch('SELECT s.*,u.nome,u.email FROM sessoes_internet s JOIN usuarios_internet u ON u.id=s.usuario_id WHERE s.id=?',[$id]); if($s) self::arquivarSessao($s,'revogada_admin');
        Database::execute('DELETE FROM sessoes_internet WHERE id = ?', [$id]);
        self::sincronizar();
    }

    public static function alternarAtivo(int $id): void
    {
        $u=Database::fetch('SELECT ativo FROM usuarios_internet WHERE id=?',[$id]); if($u && (int)$u['ativo']===1){ foreach(Database::fetchAll('SELECT s.*,u.nome,u.email FROM sessoes_internet s JOIN usuarios_internet u ON u.id=s.usuario_id WHERE s.usuario_id=?',[$id]) as $s) self::arquivarSessao($s,'conta_desativada'); Database::execute('DELETE FROM sessoes_internet WHERE usuario_id=?',[$id]); }
        Database::execute('UPDATE usuarios_internet SET ativo = 1 - ativo WHERE id = ?', [$id]);
        // Desativar derruba as sessões; sincronizar() já ignora quem está inativo
        self::sincronizar();
    }

    public static function excluirUsuario(int $id): void
    {
        foreach(Database::fetchAll('SELECT s.*,u.nome,u.email FROM sessoes_internet s JOIN usuarios_internet u ON u.id=s.usuario_id WHERE s.usuario_id=?',[$id]) as $s) self::arquivarSessao($s,'usuario_excluido');
        Database::execute('DELETE FROM usuarios_internet WHERE id = ?', [$id]);  // cascata: sessões e tokens
        self::sincronizar();
    }

    // ── ponte com o Squid ───────────────────────────────────────────────────
    /** Persiste o encerramento sem depender da existência futura da conta. */
    private static function arquivarSessao(array $s, string $motivo): void
    {
        $fim=date('Y-m-d H:i:s'); $inicio=(string)($s['criado_em']??$fim);
        $duracao=max(0,strtotime($fim)-(strtotime($inicio)?:strtotime($fim)));
        Database::execute('INSERT INTO sessoes_internet_historico (usuario_id,nome_usuario,email,ip,mac,hostname,grupo_snapshot,iniciou_em,expira_previsto_em,encerrou_em,duracao_segundos,motivo) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',[$s['usuario_id']??null,(string)($s['nome']??''),(string)($s['email']??''),(string)$s['ip'],$s['mac']??null,$s['hostname']??null,$s['grupo_snapshot']??null,$inicio,$s['expira_em'],$fim,$duracao,$motivo]);
    }

    /**
     * Regrava SESSOES_ARQ com as sessões válidas: "ip<TAB>expira_epoch<TAB>e-mail".
     * Escrita atômica (arquivo temporário + rename) para o helper nunca ler
     * um arquivo pela metade.
     */
    public static function sincronizar(): bool
    {
        $pdo=Database::conectar();
        if ((int) Database::valor("SELECT GET_LOCK('gwos_publicar_sessoes', 10)") !== 1) {
            error_log('[GWOS acesso] tempo esgotado ao aguardar a publicação das sessões.');
            return false;
        }
        try {
            try {
                $pdo->beginTransaction();
                // Sem navegar há mais que o limite (navegadores fechados): encerra a sessão.
                $idle = self::inatividadeMin();
                if ($idle > 0) {
                    $limite = date('Y-m-d H:i:s', time() - $idle * 60);
                    foreach(Database::fetchAll('SELECT s.*,u.nome,u.email FROM sessoes_internet s JOIN usuarios_internet u ON u.id=s.usuario_id WHERE COALESCE(s.ultimo_acesso,s.criado_em)<? AND s.expira_em>? FOR UPDATE',[$limite,date('Y-m-d H:i:s')]) as $s) {
                        self::arquivarSessao($s,'inatividade');
                        Database::execute('DELETE FROM sessoes_internet WHERE id = ?', [$s['id']]);
                    }
                }
                foreach(Database::fetchAll('SELECT s.*,u.nome,u.email FROM sessoes_internet s JOIN usuarios_internet u ON u.id=s.usuario_id WHERE (s.expira_em<=? OR s.agente_expira_em<=NOW()) FOR UPDATE',[date('Y-m-d H:i:s')]) as $s) self::arquivarSessao($s,'expirada');
                Database::execute('DELETE FROM sessoes_internet WHERE expira_em <= ? OR agente_expira_em <= NOW()', [date('Y-m-d H:i:s')]);
                $linhas = Database::fetchAll(
                    'SELECT s.ip, s.expira_em, u.email
                       FROM sessoes_internet s JOIN usuarios_internet u ON u.id = s.usuario_id
                      WHERE u.ativo = 1 AND s.expira_em > ?',
                    [date('Y-m-d H:i:s')]
                );
                $pdo->commit();
            } catch (\Throwable $e) {
                if($pdo->inTransaction()) $pdo->rollBack();
                error_log('[GWOS acesso] sincronizar (banco): ' . $e->getMessage());
                return false;
            }

            $texto = '';
            foreach ($linhas as $l) {
                // e-mail já é validado no cadastro; remove qualquer separador por segurança
                $email = preg_replace('/[\s]+/', '', $l['email']);
                $texto .= $l['ip'] . "\t" . strtotime($l['expira_em']) . "\t" . $email . "\n";
            }

            $dir = dirname(self::SESSOES_ARQ);
            if (!is_dir($dir) || !is_writable($dir)) {
                error_log("[GWOS acesso] {$dir} inexistente ou sem escrita para o PHP.");
                return false;
            }
            $tmp = self::SESSOES_ARQ . '.' . bin2hex(random_bytes(16)) . '.tmp';
            $arquivo = @fopen($tmp, 'xb');
            if ($arquivo === false) return false;
            $gravado = fwrite($arquivo, $texto) === strlen($texto);
            $fechado = fclose($arquivo);
            if (!$gravado || !$fechado || !chmod($tmp, 0640) || !rename($tmp, self::SESSOES_ARQ)) {
                @unlink($tmp);
                return false;
            }
            return self::sincronizarFirewall();
        } finally {
            Database::valor("SELECT RELEASE_LOCK('gwos_publicar_sessoes')");
        }
    }

    /** Minutos sem navegar para encerrar a sessão (0 = desligado). Mínimo 3. */
    public static function inatividadeMin(): int
    {
        $m = (int) self::cfg('acesso_inatividade_min', '10');
        return $m <= 0 ? 0 : max(3, min(1440, $m));
    }

    /**
     * O que conta como "navegando": 'navegador' (só User-Agent de navegador, para que
     * atualizações do sistema não mantenham a sessão viva) ou 'qualquer'. Em 'auto',
     * usa 'navegador' quando o SSL Bump está ativo (o User-Agent do HTTPS é visível).
     */
    public static function modoAtividade(): string
    {
        $m = self::cfg('acesso_atividade_modo', 'auto');
        if ($m === 'navegador' || $m === 'qualquer') return $m;
        return is_file('/etc/squid/ssl_cert/gwos-ca.crt') ? 'navegador' : 'qualquer';
    }

    /** UA de navegador de verdade (e não de atualizador/serviço do sistema). */
    public static function ehNavegador(string $ua): bool
    {
        if ($ua === '' || $ua === '-') return false;
        if (preg_match('/(Update|Updater|Delivery-Optimization|WinHttp|NCSI|CryptoAPI|Telemetry|curl|Wget|apt|okhttp|Dalvik)/i', $ua)) return false;
        return (bool) preg_match('/^(Mozilla|Opera)\//', $ua);
    }

    /** @param array<string,int> $ultimoPorIp ip => epoch da última requisição de navegação */
    public static function registrarAtividade(array $ultimoPorIp): void
    {
        foreach ($ultimoPorIp as $ip => $ts) {
            Database::execute(
                'UPDATE sessoes_internet SET ultimo_acesso = ? WHERE ip = ? AND (ultimo_acesso IS NULL OR ultimo_acesso < ?)',
                [date('Y-m-d H:i:s', (int) $ts), $ip, date('Y-m-d H:i:s', (int) $ts)]
            );
        }
    }

    /** Atualiza o conjunto de IPs autenticados do firewall (sem falhar o login se não houver nft). */
    private static function sincronizarFirewall(): bool
    {
        $bin = '/usr/local/sbin/gwos-sessoes-nft';
        if (!is_executable($bin)) return true;
        if (!function_exists('exec')) return false;
        $cmd = (function_exists('posix_geteuid') && posix_geteuid() === 0) ? $bin : 'sudo -n ' . $bin;
        $saida = []; $rc = 0;
        @exec($cmd . ' 2>&1', $saida, $rc);
        if ($rc !== 0) error_log('[GWOS acesso] sincronizar firewall: ' . implode(' ', $saida));
        return $rc === 0;
    }

}
