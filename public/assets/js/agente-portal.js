(() => {
    const campo = document.getElementById('gwos-agente-token');
    if (!campo) {
        sessionStorage.removeItem('gwos-agente-token');
        return;
    }

    const token = location.hash.slice(1);
    if (/^[a-f0-9]{64}$/.test(token)) {
        sessionStorage.setItem('gwos-agente-token', token);
        history.replaceState(null, '', location.pathname + location.search);
    }
    campo.value = sessionStorage.getItem('gwos-agente-token') || '';
})();
