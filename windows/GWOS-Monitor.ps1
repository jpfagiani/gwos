param([Parameter(Mandatory=$true)][uri]$Portal)
$ErrorActionPreference = 'Stop'
$log = Join-Path $PSScriptRoot 'monitor-status.log'
$script:ultimoEstado = ''
function Registrar([string]$Estado) {
    if ($script:ultimoEstado -eq $Estado) { return }
    $script:ultimoEstado = $Estado
    Set-Content -LiteralPath $log -Encoding UTF8 -Value ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Estado) -ErrorAction SilentlyContinue
    Write-Output $Estado
}
if ($Portal.Scheme -ne 'https' -or $Portal.AbsolutePath -ne '/acesso' -or $Portal.Query -or $Portal.Fragment -or $Portal.UserInfo) {
    throw 'Informe a URL HTTPS do portal terminada em /acesso.'
}
$mutex = New-Object Threading.Mutex($false, 'Local\GWOSMonitorInternet')
$possuiMutex = $false
$http = $null
try {
    try { $possuiMutex = $mutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $possuiMutex = $true }
    if (!$possuiMutex) { return }
    $credencial = Import-Clixml -LiteralPath (Join-Path $PSScriptRoot 'monitor.xml')
    $chave = $credencial.GetNetworkCredential().Password
    Add-Type -AssemblyName System.Net.Http
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $handler = New-Object Net.Http.HttpClientHandler
    $handler.UseProxy = $false
    $handler.UseCookies = $false
    $handler.AllowAutoRedirect = $false
    $http = New-Object Net.Http.HttpClient($handler)
    $http.Timeout = [TimeSpan]::FromSeconds(2)
    $api = [uri]::new($Portal, '/acesso/monitor')
    $sessaoWindows = (Get-Process -Id $PID).SessionId

    function Enviar([string]$Acao, [string]$Ciclo) {
        $content = New-Object Net.Http.StringContent("acao=$Acao&chave=$chave&ciclo=$Ciclo", [Text.Encoding]::UTF8, 'application/x-www-form-urlencoded')
        try {
            $r = $http.PostAsync($api, $content).GetAwaiter().GetResult()
            try {
                $codigo = [int]$r.StatusCode
                Registrar ("$Acao HTTP $codigo") | Out-Host
                return $codigo -eq 204
            } finally { $r.Dispose() }
        } catch {
            Registrar ("$Acao falhou: " + $_.Exception.GetBaseException().Message) | Out-Host
            return $false
        } finally { $content.Dispose() }
    }

    $ciclo = $null
    $pendente = $null
    $proximo = [DateTime]::MinValue
    while ($true) {
        $aberto = $false
        foreach ($proc in Get-Process -Name chrome,msedge,firefox -ErrorAction SilentlyContinue) {
            if ($proc.SessionId -eq $sessaoWindows -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
                $aberto = $true
                break
            }
        }
        if (!$aberto -and $ciclo) {
            $pendente = $ciclo
            $ciclo = $null
            $proximo = [DateTime]::MinValue
        }
        if ($pendente -and [DateTime]::UtcNow -ge $proximo) {
            if (Enviar 'sair' $pendente) { $pendente = $null }
            else { $proximo = [DateTime]::UtcNow.AddSeconds(5) }
        }
        if ($aberto -and !$pendente) {
            if (!$ciclo) {
                $bytes = New-Object byte[] 32
                $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
                try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
                $ciclo = [BitConverter]::ToString($bytes).Replace('-', '').ToLowerInvariant()
                $proximo = [DateTime]::MinValue
            }
            if ([DateTime]::UtcNow -ge $proximo) {
                [void](Enviar 'presenca' $ciclo)
                $proximo = [DateTime]::UtcNow.AddSeconds(5)
            }
        }
        if (!$aberto -and !$pendente) {
            Registrar 'Aguardando janela de Chrome, Edge ou Firefox.' | Out-Host
        }
        Start-Sleep -Milliseconds 500
    }
} catch {
    Registrar ('Falha ao iniciar: ' + $_.Exception.GetBaseException().Message) | Out-Host
    exit 1
} finally {
    if ($http) { $http.Dispose() }
    if ($possuiMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
