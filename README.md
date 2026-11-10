# Portal do Cliente StateraTI

Instalador do Portal do Cliente StateraTI para Windows 10 (1809+) e 11, 64 bits.

Os instaladores ficam em [Releases](https://github.com/Statera-TI/Portal-Cliente/releases),
cada um acompanhado do arquivo `.sha256`.

## Instalar pelo PowerShell

Abra o PowerShell **como o usuário que vai usar o portal** (não como administrador
nem como SYSTEM) e rode:

```powershell
irm https://raw.githubusercontent.com/Statera-TI/Portal-Cliente/main/instalar-portal.ps1 | iex
```

O script baixa a última versão publicada, confere o SHA-256, instala em modo
silencioso e confere a versão instalada. Se o portal estiver aberto, ele é fechado
para a atualização.

Para uma versão específica ou abrir o portal ao final:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Statera-TI/Portal-Cliente/main/instalar-portal.ps1))) -Versao 2.1.3 -AbrirDepois
```

## Baixar só o instalador

```powershell
$url = 'https://github.com/Statera-TI/Portal-Cliente/releases/latest/download/Portal-do-Cliente-StateraTI-Setup-win-x64.exe'
Invoke-WebRequest $url -OutFile "$env:TEMP\Portal-do-Cliente-StateraTI-Setup.exe" -UseBasicParsing
(Get-FileHash "$env:TEMP\Portal-do-Cliente-StateraTI-Setup.exe" -Algorithm SHA256).Hash
```

Compare o resultado com o arquivo `.sha256` da release.

## Pelo VSA X (roda como SYSTEM)

O portal é instalado no perfil do usuário, então não pode ser instalado direto como
SYSTEM. Use o `vsax-instalar-portal.ps1`: ele cria uma tarefa agendada temporária
para cada usuário com sessão aberta, roda o `instalar-portal.ps1` como esse usuário,
mostra o log e remove a tarefa.

Script do VSA X (PowerShell, executando como SYSTEM):

```powershell
$f = "$env:TEMP\vsax-instalar-portal.ps1"
Invoke-WebRequest 'https://raw.githubusercontent.com/Statera-TI/Portal-Cliente/main/vsax-instalar-portal.ps1' -OutFile $f -UseBasicParsing
& $f
exit $LASTEXITCODE
```

| Código | Significado |
|---|---|
| 0 | Instalado para todos os usuários logados |
| 1 | Falha em pelo menos um usuário (o log aparece na saída) |
| 3 | Nenhum usuário logado; rodar de novo quando houver alguém na máquina |
| 4 | Não está rodando como SYSTEM/administrador |

O `instalar-portal.ps1` sozinho, rodando como o próprio usuário, devolve 0 (ok),
1 (falha) ou 2 (executado como SYSTEM).
