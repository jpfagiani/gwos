<?php

namespace App\Controllers;

use App\Core\{AcessoInternet, Session, Controller, CredenciamentoMonitor};

/**
 * Portal do usuário (público): é para cá que o Squid redireciona quem tenta
 * navegar sem sessão. Não exige login de administrador.
 */
class AcessoController extends Controller
{
    // GET /acesso
    public function formulario(): void
    {
        $ip     = AcessoInternet::ipCliente();
        $sessao = isset($_GET['agente']) ? null : AcessoInternet::sessaoDoIp($ip);
        $destino = $_GET['url'] ?? '';
        $url = $this->urlDestino(is_string($destino) ? $destino : '');

        $aviso = $_GET['aviso'] ?? '';
        if ($aviso === 'porta' || ($aviso === '1' && $sessao === null && !isset($_GET['agente']))) {
            $bloqueioPorta = $aviso === 'porta';
            view('acesso/aviso', [
                'bloqueioPorta' => $bloqueioPorta,
                'linkLogin' => '/acesso' . ($bloqueioPorta ? '' : $this->qs($url)),
            ]);
            return;
        }

        view('acesso/login', [
            'sessao'  => $sessao,
            'agente' => isset($_GET['agente']),
            'ip'      => $ip,
            'url'     => $url,
            'erro'    => Session::flash('erro_acesso'),
            'sucesso' => Session::flash('sucesso_acesso'),
        ]);
    }

    // POST /acesso
    public function entrar(): void
    {
        $url = $this->urlDestino($_POST['url'] ?? '');
        if (!csrf_verificar()) {
            Session::flash('erro_acesso', 'Sessão expirada. Tente de novo.');
            $this->redirect('/acesso' . $this->qs($url));
        }

        [$ok, $msg, $usuario] = AcessoInternet::entrar(
            (string) ($_POST['login'] ?? ''),
            (string) ($_POST['senha'] ?? ''),
            AcessoInternet::ipCliente(),
            isset($_POST['agente']) ? (string) ($_POST['agente_token'] ?? '') : null
        );

        if (!$ok) {
            Session::flash('erro_acesso', $msg);
            $this->redirect(isset($_POST['agente']) ? '/acesso?agente=1' : '/acesso' . $this->qs($url));
        }

        session_regenerate_id(true);
        Session::flash('sucesso_acesso', 'Acesso liberado. Bom trabalho, ' . explode(' ', $usuario['nome'])[0] . '!');
        $this->redirect('/acesso' . $this->qs($url));
    }

    // Requisição sem cookie, autenticada pelo segredo da sessão do atalho.
    public function agente(): void
    {
        $token = $_POST['token'] ?? null;
        $acao = $_POST['acao'] ?? null;
        if (!is_string($token) || !preg_match('/^[a-f0-9]{64}$/D', $token)
            || !in_array($acao, ['presenca', 'sair'], true)) {
            http_response_code(400);
            return;
        }
        try {
            AcessoInternet::atualizarAgente(AcessoInternet::ipCliente(), $token, $acao);
            http_response_code(204);
        } catch (\Throwable $e) {
            error_log('[GWOS agente] ' . $e->getMessage());
            http_response_code(503);
        }
    }

    public function monitor(): void
    {
        $chave = $_POST['chave'] ?? null;
        $ciclo = $_POST['ciclo'] ?? null;
        $acao = $_POST['acao'] ?? null;
        if (!is_string($chave) || !preg_match('/^[a-f0-9]{64}$/D', $chave)
            || !is_string($ciclo) || !preg_match('/^[a-f0-9]{64}$/D', $ciclo)
            || !in_array($acao, ['presenca', 'sair'], true)) {
            http_response_code(400);
            return;
        }
        try {
            http_response_code(AcessoInternet::atualizarMonitor(AcessoInternet::ipCliente(), $chave, $ciclo, $acao) ? 204 : 403);
        } catch (\Throwable $e) {
            error_log('[GWOS monitor] ' . $e->getMessage());
            http_response_code(503);
        }
    }

    public function baixarChaveMonitor(): void
    {
        header('Cache-Control: no-store');
        header('Content-Type: text/plain; charset=UTF-8');
        if (!in_array($_SERVER['HTTPS'] ?? '', ['on', '1'], true)) {
            http_response_code(403);
            return;
        }
        $codigo = $_POST['codigo'] ?? null;
        $chave = is_string($codigo) ? CredenciamentoMonitor::resgatar(trim($codigo)) : null;
        if (!$chave) {
            http_response_code(404);
            echo 'Código inválido, expirado ou já utilizado.';
            return;
        }
        header('Content-Disposition: attachment; filename="gwos-chave-' . $chave['ip'] . '.txt"');
        echo $chave['chave'] . "\n";
    }

    // POST /acesso/sair
    public function sair(): void
    {
        if (csrf_verificar()) {
            AcessoInternet::sair(AcessoInternet::ipCliente());
            Session::flash('sucesso_acesso', 'Você saiu. A internet deste computador foi bloqueada novamente.');
        }
        $this->redirect('/acesso');
    }

    public function formularioCadastro(): void
    {
        view('acesso/cadastro', ['erro' => Session::flash('erro_acesso')]);
    }

    public function cadastrar(): void
    {
        if (!csrf_verificar()) $this->redirect('/acesso/cadastro');
        $senha = (string) ($_POST['senha'] ?? '');
        if ($senha !== (string) ($_POST['confirmar'] ?? '')) {
            Session::flash('erro_acesso', 'As senhas não coincidem.');
            $this->redirect('/acesso/cadastro');
        }
        [$ok, $msg] = AcessoInternet::cadastrarCpf(
            (string) ($_POST['nome'] ?? ''), (string) ($_POST['cpf'] ?? ''), $senha, AcessoInternet::ipCliente()
        );
        Session::flash($ok ? 'sucesso_acesso' : 'erro_acesso', $ok ? 'Conta criada. Entre com seu CPF e sua senha.' : $msg);
        $this->redirect($ok ? '/acesso' : '/acesso/cadastro');
    }

    public function formularioSenha(): void
    {
        $token = (string) ($_GET['t'] ?? '');
        view('acesso/senha', [
            'token' => preg_match('/^[a-f0-9]{64}$/D', $token) ? $token : '',
            'erro' => Session::flash('erro_acesso'),
        ]);
    }

    public function definirSenha(): void
    {
        if (!csrf_verificar()) $this->redirect('/acesso/senha');
        [$ok, $msg] = AcessoInternet::definirSenha(
            strtolower(trim((string) ($_POST['t'] ?? ''))),
            (string) ($_POST['senha'] ?? ''),
            (string) ($_POST['confirmar'] ?? '')
        );
        Session::flash($ok ? 'sucesso_acesso' : 'erro_acesso', $msg);
        $this->redirect($ok ? '/acesso' : '/acesso/senha');
    }

    /** Só http(s) — o destino original que o Squid mandou junto no redirecionamento. */
    private function urlDestino(string $url): string
    {
        $url = trim($url);
        if ($url === '' || strlen($url) > 1500 || !preg_match('#^https?://#i', $url)) {
            return '';
        }
        return $url;
    }

    private function qs(string $url): string
    {
        return $url === '' ? '' : '?url=' . rawurlencode($url);
    }
}
