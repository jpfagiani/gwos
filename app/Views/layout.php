<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="csrf-token" content="<?= h(csrf_token()) ?>">
    <link rel="icon" type="image/svg+xml" href="/favicon.svg">
    <title><?= h($titulo ?? 'GWOS') ?> — <?= h(config('app.nome', 'GWOS')) ?></title>
    <link rel="stylesheet" href="/assets/css/bootstrap.min.css">
    <link rel="stylesheet" href="/assets/css/bootstrap-icons.min.css">
    <style>
        body { background: #f4f6f9; }
        #sidebar {
            min-height: 100vh;
            width: 240px;
            background: #1a2332;
            color: #c8d0dc;
            position: fixed;
            top: 0; left: 0;
            display: flex;
            flex-direction: column;
            z-index: 100;
        }
        #sidebar .logo {
            padding: 1.25rem 1.5rem;
            font-size: 1.3rem;
            font-weight: 700;
            color: #fff;
            border-bottom: 1px solid #2d3f55;
            letter-spacing: 1px;
        }
        #sidebar .nav-link {
            color: #c8d0dc;
            padding: .55rem 1.5rem;
            display: flex;
            align-items: center;
            gap: .6rem;
            border-radius: 0;
            font-size: .92rem;
        }
        #sidebar .nav-link:hover,
        #sidebar .nav-link.active {
            background: #2d3f55;
            color: #fff;
        }
        #sidebar .nav-section {
            font-size: .72rem;
            text-transform: uppercase;
            letter-spacing: .08em;
            color: #6b7f96;
            padding: 1rem 1.5rem .3rem;
        }
        #content {
            margin-left: 240px;
            min-height: 100vh;
        }
        #topbar {
            background: #fff;
            border-bottom: 1px solid #e3e8ef;
            padding: .75rem 1.5rem;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }
    </style>
</head>
<body>

<div id="sidebar">
    <div class="logo"><i class="bi bi-shield-lock-fill me-2"></i>GWOS</div>
    <nav class="nav flex-column pt-2">
        <span class="nav-section">Principal</span>
        <a class="nav-link <?= ($modulo ?? '') === 'dashboard' ? 'active' : '' ?>" href="/">
            <i class="bi bi-speedometer2"></i> Dashboard
        </a>

        <span class="nav-section">Controle de Acesso</span>
        <a class="nav-link <?= ($modulo ?? '') === 'grupos' ? 'active' : '' ?>" href="/grupos">
            <i class="bi bi-people-fill"></i> Grupos & IPs
        </a>
        <a class="nav-link <?= ($modulo ?? '') === 'dominios' ? 'active' : '' ?>" href="/dominios">
            <i class="bi bi-globe2"></i> Domínios
        </a>
        <a class="nav-link <?= ($modulo ?? '') === 'horarios' ? 'active' : '' ?>" href="/horarios">
            <i class="bi bi-clock-fill"></i> Horários
        </a>

        <span class="nav-section">Rede</span>
        <a class="nav-link <?= ($modulo ?? '') === 'nat' ? 'active' : '' ?>" href="/nat">
            <i class="bi bi-arrow-left-right"></i> NAT 1:1
        </a>

        <span class="nav-section">Relatórios</span>
        <a class="nav-link <?= ($modulo ?? '') === 'relatorios' ? 'active' : '' ?>" href="/relatorios">
            <i class="bi bi-bar-chart-fill"></i> Relatórios
        </a>

        <span class="nav-section">Sistema</span>
        <a class="nav-link <?= ($modulo ?? '') === 'configuracoes' ? 'active' : '' ?>" href="/configuracoes">
            <i class="bi bi-gear-fill"></i> Configurações
        </a>
        <a class="nav-link <?= ($modulo ?? '') === 'senha' ? 'active' : '' ?>" href="/senha/trocar">
            <i class="bi bi-key-fill"></i> Alterar Senha
        </a>
        <?php if ((\App\Core\Auth::admin()['perfil'] ?? '') === 'superadmin'): ?>
        <a class="nav-link" href="/senha/gerar">
            <i class="bi bi-person-lock"></i> Reset de Senha
        </a>
        <?php endif; ?>
        <a class="nav-link" href="/logout">
            <i class="bi bi-box-arrow-left"></i> Sair
        </a>
    </nav>
</div>

<div id="content">
    <div id="topbar">
        <span class="fw-semibold text-secondary"><?= h($titulo ?? '') ?></span>
        <div class="d-flex align-items-center gap-2 text-secondary small">
            <i class="bi bi-person-circle"></i>
            <?= h(\App\Core\Auth::admin()['nome'] ?? '') ?>
            <span class="badge bg-secondary"><?= h(\App\Core\Auth::admin()['perfil'] ?? '') ?></span>
        </div>
    </div>

    <div class="container-fluid p-4">
        <?php
        $flash_sucesso = \App\Core\Session::flash('sucesso');
        $flash_erro    = \App\Core\Session::flash('erro');
        if ($flash_sucesso): ?>
            <div class="alert alert-success alert-dismissible fade show" role="alert">
                <?= h($flash_sucesso) ?>
                <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
            </div>
        <?php endif; ?>
        <?php if ($flash_erro): ?>
            <div class="alert alert-danger alert-dismissible fade show" role="alert">
                <?= h($flash_erro) ?>
                <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
            </div>
        <?php endif; ?>

        <?= $conteudo ?? '' ?>
    </div>
</div>

<script src="/assets/js/bootstrap.bundle.min.js"></script>
<script src="/assets/js/app.js"></script>
</body>
</html>
