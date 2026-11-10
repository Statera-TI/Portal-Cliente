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
```

## Pelo VSA X

Rode o `instalar-portal.ps1` no contexto do **usuário logado**. Códigos de saída:

| Código | Significado |
|---|---|
| 0 | Instalado e versão conferida |
| 1 | Falha no download, no hash, no instalador ou na conferência da versão |
| 2 | Executado como SYSTEM |
