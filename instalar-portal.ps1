<#
.SYNOPSIS
    Baixa a ultima versao do Portal do Cliente StateraTI publicada neste repositorio
    e instala em modo silencioso.

.DESCRIPTION
    O instalador e por usuario (%LocalAppData%), entao o script precisa rodar como o
    USUARIO LOGADO, nunca como SYSTEM. O instalador e o SHA-256 vem dos anexos da
    release; o arquivo so e executado se o hash conferir.

    Codigos de saida:
      0 = instalado e versao conferida
      1 = falha no download, no hash, no instalador ou na conferencia da versao
      2 = executado como SYSTEM (rode como usuario logado)

.EXAMPLE
    irm https://raw.githubusercontent.com/Statera-TI/Portal-Cliente/main/instalar-portal.ps1 | iex

.EXAMPLE
    .\instalar-portal.ps1 -Versao 2.1.3 -AbrirDepois
#>
param(
    # Tag da release (ex.: 2.1.3). Vazio usa a ultima publicada.
    [string]$Versao = '',

    # Abre o portal ao final (por padrao nao abre, para nao interromper o usuario).
    [switch]$AbrirDepois
)

$ErrorActionPreference = 'Stop'
$runFromFile = [bool]$PSCommandPath
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repo = 'Statera-TI/Portal-Cliente'
$appName = 'Portal do Cliente StateraTI'
$workDir = Join-Path $env:TEMP 'StateraTI-Deploy'
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
$installLog = Join-Path $workDir ("instalacao-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

function Write-Step([string]$message) {
    Write-Output ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $message)
}

function Exit-Script([int]$code) {
    # Quando rodado via "irm | iex", exit fecharia a janela do PowerShell.
    if ($runFromFile) { exit $code }
    $global:LASTEXITCODE = $code
}

try {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.IsSystem) {
        Write-Step 'ERRO: o script esta rodando como SYSTEM. Execute como o usuario logado.'
        Exit-Script 2
        return
    }

    $releaseUrl = if ($Versao) {
        "https://api.github.com/repos/$repo/releases/tags/$Versao"
    } else {
        "https://api.github.com/repos/$repo/releases/latest"
    }
    $release = Invoke-RestMethod -Uri $releaseUrl -Headers @{ 'User-Agent' = 'StateraTI-Portal-Installer' }
    $exeAsset = $release.assets | Where-Object { $_.name -like '*win-x64.exe' } | Select-Object -First 1
    $hashAsset = $release.assets | Where-Object { $_.name -eq "$($exeAsset.name).sha256" } | Select-Object -First 1
    if (-not $exeAsset -or -not $hashAsset) {
        throw "A release $($release.tag_name) nao tem o instalador x64 e o arquivo .sha256."
    }
    Write-Step "Versao publicada: $($release.tag_name)"

    $installerPath = Join-Path $workDir $exeAsset.name
    Write-Step "Baixando $($exeAsset.name)..."
    Invoke-WebRequest -Uri $exeAsset.browser_download_url -OutFile $installerPath -UseBasicParsing

    $expectedHash = ((Invoke-WebRequest -Uri $hashAsset.browser_download_url -UseBasicParsing).Content -split '\s+')[0].Trim().ToUpperInvariant()
    $hash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash
    if ($hash -ne $expectedHash) {
        Remove-Item -LiteralPath $installerPath -Force
        throw "SHA-256 nao confere. Esperado $expectedHash, obtido $hash."
    }
    Write-Step 'SHA-256 conferido.'

    # /CLOSEAPPLICATIONS fecha o portal aberto para trocar os arquivos.
    Write-Step 'Instalando em modo silencioso...'
    $process = Start-Process -FilePath $installerPath `
        -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', "/LOG=`"$installLog`"") `
        -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "O instalador terminou com codigo $($process.ExitCode). Log: $installLog"
    }

    $uninstallEntry = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq $appName } |
        Select-Object -First 1
    if (-not $uninstallEntry) {
        throw "Instalacao nao encontrada no registro do usuario. Log: $installLog"
    }

    $expectedVersion = $release.tag_name.TrimStart('v')
    Write-Step "Instalado: versao $($uninstallEntry.DisplayVersion) em $($uninstallEntry.InstallLocation)"
    if ($uninstallEntry.DisplayVersion -ne $expectedVersion) {
        throw "Versao instalada diferente da esperada ($expectedVersion)."
    }

    $exePath = Join-Path $uninstallEntry.InstallLocation "$appName.exe"
    if ($AbrirDepois -and (Test-Path -LiteralPath $exePath)) {
        Start-Process -FilePath $exePath
        Write-Step 'Portal aberto.'
    }

    Write-Step 'Concluido.'
    Exit-Script 0
}
catch {
    Write-Step "ERRO: $($_.Exception.Message)"
    Exit-Script 1
}
