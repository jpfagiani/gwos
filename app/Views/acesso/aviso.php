<?php $titulo = $bloqueioPorta ? 'Acesso restrito' : 'Entre para navegar'; require __DIR__ . '/_topo.php'; ?>

<main class="portal-aviso" aria-labelledby="titulo-aviso">
    <div class="portal-aviso-icone" aria-hidden="true"><i class="bi bi-wifi"></i></div>
    <h2 id="titulo-aviso"><?= h($titulo) ?></h2>
    <?php if ($bloqueioPorta): ?>
        <p class="text-muted">A porta usada por esse endereço está bloqueada pela política da rede. Entrar no portal não libera essa porta.</p>
    <?php else: ?>
        <p class="text-muted">Abra o portal e entre com seu CPF e sua senha para usar a internet da instituição.</p>
    <?php endif; ?>

    <a class="btn btn-primary portal-aviso-botao w-100" href="<?= h($linkLogin) ?>">
        Ir para o login <i class="bi bi-arrow-right" aria-hidden="true"></i>
    </a>

    <section class="portal-aviso-ajuda" aria-labelledby="titulo-ajuda">
        <i class="bi bi-headset" aria-hidden="true"></i>
        <div>
            <h3 id="titulo-ajuda">Precisa de ajuda?</h3>
            <?php if ($bloqueioPorta): ?>
                <p>Se você precisa acessar esse sistema, procure o Administrador do Sistema e informe o endereço que tentou abrir.</p>
            <?php else: ?>
                <p>Se você não conseguir entrar ou o problema continuar depois do login, procure o Administrador do Sistema.</p>
            <?php endif; ?>
        </div>
    </section>
</main>

<?php require __DIR__ . '/_fim.php'; ?>
