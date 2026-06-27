<?php

namespace App\Core;

class Auth
{
    private const CHAVE_SESSAO   = '_gwos_admin';
    private const MAX_TENTATIVAS = 5;
    private const BLOQUEIO_MIN   = 30;

    public static function iniciar(): void
    {
        Session::iniciar();
    }

    public static function login(string $email, string $senha): bool
    {
        $admin = Database::fetch(
            'SELECT * FROM admins WHERE email = ? AND ativo = 1',
            [trim($email)]
        );

        if (!$admin) {
            return false;
        }

        // Verifica bloqueio por tentativas excessivas
        if ($admin['bloqueado_ate'] && new \DateTime() < new \DateTime($admin['bloqueado_ate'])) {
            return false;
        }

        if (!password_verify($senha, $admin['senha'])) {
            $tentativas = (int)($admin['tentativas'] ?? 0) + 1;
            $bloqueado  = null;
            if ($tentativas >= self::MAX_TENTATIVAS) {
                $bloqueado  = (new \DateTime('+' . self::BLOQUEIO_MIN . ' minutes'))->format('Y-m-d H:i:s');
                $tentativas = 0;
            }
            Database::execute(
                'UPDATE admins SET tentativas = ?, bloqueado_ate = ? WHERE id = ?',
                [$tentativas, $bloqueado, $admin['id']]
            );
            return false;
        }

        // Sucesso — zera contadores e atualiza ultimo login
        Database::execute(
            'UPDATE admins SET tentativas = 0, bloqueado_ate = NULL, ultimo_login = NOW() WHERE id = ?',
            [$admin['id']]
        );

        Session::definir(self::CHAVE_SESSAO, [
            'id'             => $admin['id'],
            'nome'           => $admin['nome'],
            'email'          => $admin['email'],
            'perfil'         => $admin['perfil'],
            'primeiro_login' => (bool)($admin['primeiro_login'] ?? false),
        ]);

        session_regenerate_id(true);

        return true;
    }

    public static function logout(): never
    {
        Session::destruir();
        redirect('/login');
    }

    public static function verificar(): bool
    {
        return Session::obter(self::CHAVE_SESSAO) !== null;
    }

    public static function exigir(): void
    {
        if (!self::verificar()) {
            redirect('/login');
        }

        // Forca troca de senha no primeiro acesso
        $admin = self::admin();
        if (!empty($admin['primeiro_login'])) {
            $uri = $_SERVER['REQUEST_URI'] ?? '';
            if (!str_starts_with($uri, '/senha')) {
                redirect('/senha/trocar');
            }
        }
    }

    public static function admin(): array|null
    {
        return Session::obter(self::CHAVE_SESSAO);
    }

    public static function id(): int|null
    {
        $admin = self::admin();
        return $admin ? (int) $admin['id'] : null;
    }

    // Gerenciamento de senha

    public static function trocarSenha(int $id, string $senhaAtual, string $novaSenha): bool
    {
        $admin = Database::fetch(
            'SELECT senha, primeiro_login FROM admins WHERE id = ?',
            [$id]
        );
        if (!$admin) return false;

        // No primeiro login não exige a senha atual (ela é a padrão e será descartada)
        // Nos acessos seguintes, exige verificação da senha atual
        if (!$admin['primeiro_login'] && !password_verify($senhaAtual, $admin['senha'])) {
            return false;
        }

        $hash = password_hash($novaSenha, PASSWORD_BCRYPT, ['cost' => 12]);
        Database::execute(
            'UPDATE admins SET senha = ?, primeiro_login = 0 WHERE id = ?',
            [$hash, $id]
        );

        $dados = Session::obter(self::CHAVE_SESSAO);
        if ($dados) {
            $dados['primeiro_login'] = false;
            Session::definir(self::CHAVE_SESSAO, $dados);
        }

        return true;
    }

    public static function gerarTokenReset(string $email): string|null
    {
        $admin = Database::fetch(
            'SELECT id FROM admins WHERE email = ? AND ativo = 1',
            [trim($email)]
        );
        if (!$admin) return null;

        $token  = strtoupper(bin2hex(random_bytes(16)));
        $expira = (new \DateTime('+24 hours'))->format('Y-m-d H:i:s');

        Database::execute(
            'UPDATE admins SET reset_token = ?, reset_expira = ? WHERE id = ?',
            [$token, $expira, $admin['id']]
        );

        return $token;
    }

    public static function resetarSenhaPorToken(string $email, string $token, string $novaSenha): bool
    {
        $admin = Database::fetch(
            'SELECT id, reset_token, reset_expira FROM admins WHERE email = ? AND ativo = 1',
            [trim($email)]
        );

        if (!$admin || !$admin['reset_token']) return false;
        if (strtoupper(trim($token)) !== $admin['reset_token']) return false;
        if (new \DateTime() > new \DateTime($admin['reset_expira'])) return false;

        $hash = password_hash($novaSenha, PASSWORD_BCRYPT, ['cost' => 12]);
        Database::execute(
            'UPDATE admins SET senha = ?, reset_token = NULL, reset_expira = NULL, primeiro_login = 0 WHERE id = ?',
            [$hash, $admin['id']]
        );

        return true;
    }

    public static function mensagemBloqueio(string $email): string|null
    {
        $admin = Database::fetch(
            'SELECT bloqueado_ate FROM admins WHERE email = ?',
            [trim($email)]
        );
        if (!$admin || !$admin['bloqueado_ate']) return null;
        if (new \DateTime() < new \DateTime($admin['bloqueado_ate'])) {
            $ate = (new \DateTime($admin['bloqueado_ate']))->format('H:i');
            return "Conta bloqueada por excesso de tentativas. Tente novamente apos as {$ate}.";
        }
        return null;
    }
}
