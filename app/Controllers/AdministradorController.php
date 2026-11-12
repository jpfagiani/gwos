<?php

namespace App\Controllers;

use App\Core\{Auditoria, Auth, Controller, Session, Usuarios};

class AdministradorController extends Controller
{
    private function exigirSuperadmin(): void
    {
        Auth::exigir();
        if ((Auth::admin()['perfil'] ?? '') !== 'superadmin') {
            $this->redirect('/');
        }
    }

    public function index(): void
    {
        $this->exigirSuperadmin();
        $this->view('administradores/index', [
            'titulo' => 'Administradores do painel',
            'modulo' => 'administradores',
            'administradores' => Usuarios::listar(),
        ]);
    }

    public function criar(): void
    {
        $this->exigirSuperadmin();
        $nome = trim(is_string($_POST['nome'] ?? null) ? $_POST['nome'] : '');
        $email = strtolower(trim(is_string($_POST['email'] ?? null) ? $_POST['email'] : ''));
        $perfil = $_POST['perfil'] ?? '';
        $senha = $_POST['senha'] ?? '';
        $confirmacao = $_POST['confirmacao'] ?? '';

        if ($nome === '' || !mb_check_encoding($nome, 'UTF-8') || mb_strlen($nome) > 100
            || strlen($email) > 150 || !filter_var($email, FILTER_VALIDATE_EMAIL)
            || !in_array($perfil, ['admin', 'operador'], true)) {
            $this->falhar('Informe um nome, um e-mail válido e um perfil disponível.');
        }
        if (!is_string($senha) || strlen($senha) < 12 || strlen($senha) > 72 || str_contains($senha, "\0")) {
            $this->falhar('A senha temporária deve ter de 12 a 72 bytes.');
        }
        if ($senha !== $confirmacao) {
            $this->falhar('As senhas não coincidem.');
        }

        try {
            $id = Usuarios::criar($nome, $email, $perfil, $senha);
        } catch (\Throwable $e) {
            error_log('GWOS: falha ao criar conta do painel (' . get_class($e) . ').');
            $this->falhar('Não foi possível gravar a conta. Verifique o armazenamento do painel.');
        }
        if ($id === null) {
            $this->falhar('Já existe uma conta com esse e-mail.');
        }
        if (Usuarios::usandoBanco()) {
            Auditoria::registrar('criar', 'admins', $id, null, [
                'nome' => $nome, 'email' => $email, 'perfil' => $perfil,
            ]);
        }

        Session::flash('sucesso', 'Conta criada. O usuário deverá trocar a senha temporária no primeiro acesso.');
        $this->redirect('/administradores');
    }

    private function falhar(string $mensagem): never
    {
        Session::flash('erro', $mensagem);
        $this->redirect('/administradores');
    }
}
