<?php

namespace App\Core;

class Auth
{
    private const CHAVE_SESSAO = '_gwos_admin';

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

        if (!$admin || !password_verify($senha, $admin['senha'])) {
            return false;
        }

        Session::definir(self::CHAVE_SESSAO, [
            'id'     => $admin['id'],
            'nome'   => $admin['nome'],
            'email'  => $admin['email'],
            'perfil' => $admin['perfil'],
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
}
