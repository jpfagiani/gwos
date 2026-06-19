<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="icon" type="image/svg+xml" href="/favicon.svg">
    <title>Login — GWOS</title>
    <link rel="stylesheet" href="/assets/css/bootstrap.min.css">
    <link rel="stylesheet" href="/assets/css/bootstrap-icons.min.css">
    <style>
        body {
            background: #1a2332;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .login-card {
            width: 100%;
            max-width: 380px;
        }
    </style>
</head>
<body>
<div class="login-card">
    <div class="text-center mb-4">
        <i class="bi bi-shield-lock-fill text-primary" style="font-size: 3rem;"></i>
        <h3 class="text-white mt-2 fw-bold">GWOS</h3>
        <p class="text-secondary small">Gateway Web OS</p>
    </div>

    <div class="card shadow-lg border-0">
        <div class="card-body p-4">
            <?php
            $flash_reset = \App\Core\Session::flash('sucesso_login');
            if ($flash_reset): ?>
                <div class="alert alert-success py-2 small"><?= h($flash_reset) ?></div>
            <?php endif; ?>
            <?php if (!empty($erro)): ?>
                <div class="alert alert-danger py-2 small"><?= h($erro) ?></div>
            <?php endif; ?>

            <form method="POST" action="/login">
                <?= csrf_field() ?>

                <div class="mb-3">
                    <label class="form-label fw-semibold">E-mail</label>
                    <div class="input-group">
                        <span class="input-group-text"><i class="bi bi-envelope"></i></span>
                        <input type="email" name="email" class="form-control" placeholder="admin@exemplo.com"
                               required autofocus value="<?= h($_POST['email'] ?? '') ?>">
                    </div>
                </div>

                <div class="mb-4">
                    <label class="form-label fw-semibold">Senha</label>
                    <div class="input-group">
                        <span class="input-group-text"><i class="bi bi-lock"></i></span>
                        <input type="password" name="senha" class="form-control" placeholder="••••••••" required>
                    </div>
                </div>

                <button type="submit" class="btn btn-primary w-100 fw-semibold">
                    <i class="bi bi-box-arrow-in-right me-1"></i> Entrar
                </button>
            </form>

            <div class="text-center mt-3">
                <a href="/senha/reset" class="text-secondary small">
                    <i class="bi bi-question-circle me-1"></i>Esqueci minha senha
                </a>
            </div>
        </div>
    </div>
</div>
<script src="/assets/js/bootstrap.bundle.min.js"></script>
</body>
</html>
