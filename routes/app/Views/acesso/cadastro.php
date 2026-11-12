<?php $titulo = 'Cadastrar conta'; require __DIR__ . '/_topo.php'; ?>
<form method="POST" action="/acesso/cadastro">
    <?= csrf_field() ?>
    <label class="form-label" for="nome">Nome completo</label>
    <input id="nome" name="nome" class="form-control mb-3" required maxlength="100" autocomplete="name">
    <label class="form-label" for="cpf">CPF</label>
    <input id="cpf" name="cpf" class="form-control mb-3" required maxlength="14" inputmode="numeric" autocomplete="username">
    <label class="form-label" for="senha">Senha</label>
    <input id="senha" name="senha" type="password" class="form-control" required minlength="8" maxlength="72" autocomplete="new-password">
    <div class="form-text mb-3">Use de 8 a 72 caracteres, com letras e números.</div>
    <label class="form-label" for="confirmar">Confirme a senha</label>
    <input id="confirmar" name="confirmar" type="password" class="form-control mb-3" required minlength="8" maxlength="72" autocomplete="new-password">
    <button class="btn btn-primary w-100">Cadastrar conta</button>
</form>
<a class="small d-block mt-3" href="/acesso">Voltar para o login</a>
<?php require __DIR__ . '/_fim.php'; ?>
