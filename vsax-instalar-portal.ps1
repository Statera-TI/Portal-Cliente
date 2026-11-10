<#
.SYNOPSIS
    Instala ou atualiza o Portal do Cliente StateraTI a partir do VSA X rodando como
    SYSTEM/administrador.

.DESCRIPTION
    O instalador do portal e por usuario (%LocalAppData% e HKCU), entao nao pode ser
    executado direto como SYSTEM. Este script cria, para cada usuario com sessao
    aberta na maquina, uma tarefa agendada temporaria que roda o instalar-portal.ps1
    no contexto desse usuario, espera terminar, mostra o log e remove a tarefa.

    Codigos de saida:
      0 = instalado para todos os usuarios logados
      1 = falha em pelo menos um usuario (o log de cada um aparece na saida)
      3 = nenhum usuario logado; rode de novo quando houver alguem na maquina
      4 = o script nao esta rodando como administrador/SYSTEM

.EXAMPLE
    .\vsax-instalar-portal.ps1
    .\vsax-instalar-portal.ps1 -Versao 2.1.3
#>
param(
    # Tag da release (ex.: 2.1.3). Vazio usa a ultima publicada.
    [string]$Versao = '',

    # Tempo maximo de espera por usuario, em minutos.
    [int]$TimeoutMinutos = 10
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$scriptUrl = 'https://raw.githubusercontent.com/Statera-TI/Portal-Cliente/main/instalar-portal.ps1'
$baseDir = Join-Path $env:ProgramData 'StateraTI\PortalDeploy'

function Write-Step([string]$message) {
    Write-Output ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $message)
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Step 'ERRO: rode como SYSTEM ou administrador (necessario para criar a tarefa de outro usuario).'
    exit 4
}

# Usuarios com sessao interativa = donos de um explorer.exe (cobre tambem servidor de terminal).
$users = Get-CimInstance Win32_Process -Filter "Name = 'explorer.exe'" |
    ForEach-Object {
        $owner = Invoke-CimMethod -InputObject $_ -MethodName GetOwner
        if ($owner.ReturnValue -eq 0 -and $owner.User) { "$($owner.Domain)\$($owner.User)" }
    } |
    Sort-Object -Unique

if (-not $users) {
    Write-Step 'Nenhum usuario logado. O portal e instalado no perfil do usuario; rode quando houver alguem na maquina.'
    exit 3
}

New-Item -ItemType Directory -Path $baseDir -Force | Out-Null
$installerScript = Join-Path $baseDir 'instalar-portal.ps1'
Write-Step "Baixando $scriptUrl"
Invoke-WebRequest -Uri $scriptUrl -OutFile $installerScript -UseBasicParsing

$failures = 0
foreach ($user in $users) {
    $safeName = ($user -replace '[\\/:*?"<>|]', '_')
    $taskName = "StateraTI-InstalarPortal-$safeName"
    $logFile = Join-Path $baseDir "instalacao-$safeName.log"
    Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue

    $arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"& '$installerScript'"
    if ($Versao) { $arguments += " -Versao '$Versao'" }
    $arguments += " *> '$logFile'; exit `$LASTEXITCODE`""

    Write-Step "Instalando para $user..."
    try {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
        $taskPrincipal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit (New-TimeSpan -Minutes $TimeoutMinutos)
        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $taskPrincipal -Settings $settings -Force | Out-Null
        Start-ScheduledTask -TaskName $taskName

        $deadline = (Get-Date).AddMinutes($TimeoutMinutos + 1)
        do {
            Start-Sleep -Seconds 3
            $state = (Get-ScheduledTask -TaskName $taskName).State
        } while ($state -eq 'Running' -and (Get-Date) -lt $deadline)

        $result = (Get-ScheduledTaskInfo -TaskName $taskName).LastTaskResult
        if (Test-Path -LiteralPath $logFile) { Get-Content -LiteralPath $logFile | ForEach-Object { "    $_" } }

        if ($state -eq 'Running') {
            Write-Step "ERRO: tempo esgotado para $user."
            $failures++
        } elseif ($result -ne 0) {
            Write-Step "ERRO: instalacao para $user terminou com codigo $result."
            $failures++
        } else {
            Write-Step "OK: $user"
        }
    }
    catch {
        Write-Step "ERRO ao instalar para ${user}: $($_.Exception.Message)"
        $failures++
    }
    finally {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }
}

Remove-Item -LiteralPath $installerScript -Force -ErrorAction SilentlyContinue
if ($failures -gt 0) { exit 1 }
Write-Step 'Concluido.'
exit 0
