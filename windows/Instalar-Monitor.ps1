param(
    [Parameter(Mandatory=$true)][uri]$Portal,
    [string]$ArquivoChave
)
$ErrorActionPreference = 'Stop'
if ($Portal.Scheme -ne 'https' -or $Portal.AbsolutePath -ne '/acesso' -or $Portal.Query -or $Portal.Fragment -or $Portal.UserInfo) {
    throw 'Informe a URL HTTPS do portal terminada em /acesso.'
}
if (!$ArquivoChave) {
    $ips = @(Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred |
        Select-Object -ExpandProperty IPAddress -Unique)
    foreach ($pasta in @($PSScriptRoot, (Join-Path $env:USERPROFILE 'Downloads'))) {
        $candidatos = @($ips |
            ForEach-Object { Join-Path $pasta "gwos-chave-$_.txt" } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
        if ($candidatos.Count -gt 1) {
            throw 'Mais de uma chave corresponde aos IPs deste PC. Indique o arquivo com -ArquivoChave.'
        }
        if ($candidatos.Count -eq 1) {
            $ArquivoChave = $candidatos[0]
            break
        }
    }
}
if ($ArquivoChave) {
    $texto = (Get-Content -LiteralPath $ArquivoChave -Raw).Trim()
    if ($texto -cnotmatch '^[a-f0-9]{64}$') { throw 'Arquivo de chave invalido.' }
    $chave = ConvertTo-SecureString $texto -AsPlainText -Force
    Remove-Variable texto
    Write-Output 'Chave lida do arquivo.'
} else {
    $chave = Read-Host 'Chave fornecida pelo administrador do GWOS' -AsSecureString
}
$credencial = New-Object Management.Automation.PSCredential('gwos', $chave)
if ($credencial.GetNetworkCredential().Password -cnotmatch '^[a-f0-9]{64}$') { throw 'Chave invalida.' }
$destino = Join-Path $env:LOCALAPPDATA 'GWOS'
New-Item -ItemType Directory -Path $destino -Force | Out-Null
$script = Join-Path $destino 'GWOS-Monitor.ps1'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'GWOS-Monitor.ps1') -Destination $script -Force
$credencial | Export-Clixml -LiteralPath (Join-Path $destino 'monitor.xml') -Force
$exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$argumentos = '-NoProfile -WindowStyle Hidden -File "' + $script + '" -Portal "' + $Portal.AbsoluteUri + '"'
$shell = New-Object -ComObject WScript.Shell
$inicio = [Environment]::GetFolderPath('Startup')
$atalho = $shell.CreateShortcut((Join-Path $inicio 'GWOS Monitor.lnk'))
$atalho.TargetPath = $exe
$atalho.Arguments = $argumentos
$atalho.WorkingDirectory = $destino
$atalho.Save()
Write-Output 'Monitor configurado. Saia da sessao do Windows e entre novamente para inicia-lo.'
