param([Parameter(Mandatory=$true)][uri]$Portal)
$ErrorActionPreference = 'Stop'
if ($Portal.Scheme -ne 'https' -or $Portal.AbsolutePath -ne '/acesso' -or
    $Portal.Query -or $Portal.Fragment -or $Portal.UserInfo) {
    throw 'Informe a URL HTTPS do portal terminada em /acesso.'
}

$mutex = New-Object Threading.Mutex($false, 'Local\GWOSInternetAtalho')
$temMutex = $false
$http = $null
try {
    try { $temMutex = $mutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $temMutex = $true }
    if (!$temMutex) { return }

    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object Net.Http.HttpClientHandler
    $handler.UseProxy = $false
    $handler.UseCookies = $false
    $handler.AllowAutoRedirect = $false
    $http = New-Object Net.Http.HttpClient($handler)
    $http.Timeout = [TimeSpan]::FromSeconds(3)
    $api = [uri]::new($Portal, '/acesso/agente')

    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $token = [BitConverter]::ToString($bytes).Replace('-', '').ToLowerInvariant()

    function Enviar([string]$Acao) {
        $codigo = 0
        $content = New-Object Net.Http.StringContent("acao=$Acao&token=$token", [Text.Encoding]::UTF8, 'application/x-www-form-urlencoded')
        try {
            $response = $http.PostAsync($api, $content).GetAwaiter().GetResult()
            try { $codigo = [int]$response.StatusCode } finally { $response.Dispose() }
        } catch {
            return $false
        } finally { $content.Dispose() }
        if ($Acao -eq 'sair' -and $codigo -eq 503) {
            throw 'O GWOS informou falha ao confirmar a revogação. Verifique as sessões ativas no painel.'
        }
        return $codigo -eq 204
    }

    function NavegadorAberto {
        $sessao = (Get-Process -Id $PID).SessionId
        foreach ($processo in Get-Process -Name chrome,msedge,firefox -ErrorAction SilentlyContinue) {
            if ($processo.SessionId -eq $sessao -and $processo.MainWindowHandle -ne [IntPtr]::Zero) {
                return $true
            }
        }
        return $false
    }

    if (!(Enviar 'presenca')) {
        throw 'O agente não alcançou o GWOS por HTTPS. Verifique a atualização do servidor e a confiança no certificado.'
    }
    Start-Process ($Portal.AbsoluteUri + '?agente=1#' + $token)
    $prazo = [DateTime]::UtcNow.AddSeconds(30)
    while (!(NavegadorAberto) -and [DateTime]::UtcNow -lt $prazo) { Start-Sleep -Seconds 1 }
    if (!(NavegadorAberto)) { return }

    $proximo = [DateTime]::MinValue
    $semJanelas = 0
    while ($semJanelas -lt 2) {
        if (NavegadorAberto) {
            $semJanelas = 0
            if ([DateTime]::UtcNow -ge $proximo) {
                [void](Enviar 'presenca')
                $proximo = [DateTime]::UtcNow.AddSeconds(10)
            }
        } else { $semJanelas++ }
        if ($semJanelas -lt 2) { Start-Sleep -Seconds 2 }
    }
    for ($i = 0; $i -lt 3; $i++) {
        if (Enviar 'sair') { return }
        if ($i -lt 2) { Start-Sleep -Seconds 1 }
    }
    throw 'O GWOS não confirmou o encerramento. A sessão expira após a perda do sinal. Em computador compartilhado, bloqueie a sessão do Windows antes de sair.'
} catch {
    Add-Type -AssemblyName PresentationFramework
    [void][Windows.MessageBox]::Show($_.Exception.Message, 'GWOS - Entrar na Internet')
} finally {
    if ($http) { $http.Dispose() }
    if ($temMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
