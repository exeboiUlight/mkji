# Пересборка self-hosted компилятора mkji на Windows (PE64).
# Запускать из корня проекта: powershell -ExecutionPolicy Bypass -File build.ps1
$ErrorActionPreference = 'Stop'
$mkji = Join-Path $PSScriptRoot 'mkji.exe'

& $mkji src\main.mk -o mkji.exe --target pe
if ($LASTEXITCODE -ne 0) { throw 'failed to rebuild mkji.exe' }

& $mkji src\main.mk -o mkji_self.exe --target pe
if ($LASTEXITCODE -ne 0) { throw 'failed to rebuild mkji_self.exe' }

Write-Host 'mkji rebuilt successfully'
