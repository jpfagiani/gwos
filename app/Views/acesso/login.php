<?php $titulo = 'Entrar'; require __DIR__ . '/_topo.php'; ?>

<?php if (!empty($sessao)): ?>
    <script src="/assets/js/agente-portal.js" defer></script>
    <p class="mb-1">Conectado como <strong><?= h($sessao['nome']) ?></strong></p>
    <p class="text-muted small">
       <?php $idle = \App\Core\AcessoInternet::inatividadeMin(); ?>
       Sessão válida até <?= h(date('d/m H:i', strtotime($sessao['expira_em']))) ?>
       <?php if ($idle > 0): ?><br>Se você ficar <?= (int) $idle ?> min sem atividade de navegação registrada, o acesso é encerrado e será preciso entrar de novo.<?php endif; ?></p>
    <?php if (!empty($url)): ?>
        <a class="btn btn-primary w-100 mb-2" href="<?= h($url) ?>" rel="noopener noreferrer">
            Continuar para <?= h(parse_url($url, PHP_URL_HOST) ?: 'o site') ?>
        </a>
    <?php endif; ?>
    <form method="POST" action="/acesso/sair">
        <?= csrf_field() ?>
        <button class="btn btn-outline-secondary w-100">Sair e bloquear este computador</button>
    </form>
<?php else: ?>
    <section class="alert alert-info py-2 small" aria-labelledby="aviso-acesso">
        <h2 id="aviso-acesso" class="h6">Entre para navegar</h2>
        <p class="mb-0">Se este é seu primeiro acesso, cadastre uma conta com seu CPF. Se já tem conta, entre com seu CPF e sua senha.</p>
    </section>
    <form method="POST" action="/acesso" autocomplete="on">
        <?= csrf_field() ?>
        <?php if (!empty($agente)): ?>
            <input type="hidden" name="agente" value="1">
            <input type="hidden" id="gwos-agente-token" name="agente_token">
            <script src="/assets/js/agente-portal.js" defer></script>
        <?php endif; ?>
        <input type="hidden" name="url" value="<?= h($url) ?>">
        <div class="mb-3">
            <label class="form-label small fw-semibold">CPF</label>
            <input type="text" name="login" class="form-control" placeholder="000.000.000-00" required autofocus autocomplete="username">
        </div>
        <div class="mb-3">
            <label class="form-label small fw-semibold">Senha</label>
            <input type="password" name="senha" class="form-control" required autocomplete="current-password">
        </div>
        <button class="btn btn-primary w-100">Entrar</button>
    </form>
    <div class="d-flex justify-content-between small mt-3">
        <a href="/acesso/cadastro">Cadastrar conta</a>
        <a href="/acesso/senha">Esqueci minha senha</a>
    </div>
    <p class="text-muted small mt-3 mb-0">Cada conta pode manter até <?= h(\App\Core\AcessoInternet::cfg('acesso_max_sessoes_usuario', '3')) ?> dispositivos conectados ao mesmo tempo. Ao atingir o limite, encerre uma sessão ativa antes de entrar em outro dispositivo.</p>
<?php endif; ?>

<section class="alert alert-warning py-2 small mt-3 mb-0" aria-labelledby="aviso-uso">
    <h2 id="aviso-uso" class="h6">Uso responsável da internet</h2>
    <p class="mb-0">Use a conexão para atividades autorizadas pela instituição. Mantenha sua senha em sigilo, encerre a sessão ao sair de um computador compartilhado e comunique suspeitas de uso indevido à equipe responsável pela rede.</p>
</section>

<?php require __DIR__ . '/_fim.php'; ?>
