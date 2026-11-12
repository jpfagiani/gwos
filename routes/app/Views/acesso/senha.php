<?php $titulo = 'Redefinir senha'; require __DIR__ . '/_topo.php'; ?>
<p class="small">Peça um código temporário ao administrador da rede e informe o código abaixo para criar uma nova senha.</p>
<form method="POST" action="/acesso/senha">
    <?= csrf_field() ?>
    <label class="form-label" for="codigo">Código de redefinição</label>
    <input id="codigo" name="t" class="form-control mb-3" required maxlength="64" value="<?= h($token) ?>" autocomplete="off">
    <label class="form-label" for="senha">Nova senha</label>
    <input id="senha" name="senha" type="password" class="form-control" required minlength="8" maxlength="72" autocomplete="new-password">
    <div class="form-text mb-3">Use de 8 a 72 caracteres, com letras e números.</div>
    <label class="form-label" for="confirmar">Confirme a nova senha</label>
    <input id="confirmar" name="confirmar" type="password" class="form-control mb-3" required minlength="8" maxlength="72" autocomplete="new-password">
    <button class="btn btn-primary w-100">Salvar nova senha</button>
</form>
<a class="small d-block mt-3" href="/acesso">Voltar para o login</a>
<?php require __DIR__ . '/_fim.php'; ?>
