# Регрессионный прогон PE64 (mkji self-hosted compiler).
# Запускать из корня проекта: powershell -File tests/run_pe_tests.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mkji = Join-Path $root 'mkji.exe'

$cases = @(
    'examples/hello.mk',
    'examples/classes.mk',
    'tests/smoke.mk'
)

foreach ($src in $cases) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($src)
    $exe = Join-Path $PSScriptRoot "$name.exe"
    Write-Host "=== $name (pe) ==="
    & $mkji (Join-Path $root $src) -o $exe --target pe | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "compile failed for $src" }
    & $exe
    if ($LASTEXITCODE -ne 0) { throw "$name.exe failed with exit $LASTEXITCODE" }
}

Write-Host '=== negative test (expect failure) ==='
$bad = Join-Path $PSScriptRoot 'bad_all.mk'
$oldPref = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$out = (& $mkji $bad -o (Join-Path $PSScriptRoot 'bad_all.exe') --target pe 2>&1 | Out-String)
$code = $LASTEXITCODE
$ErrorActionPreference = $oldPref
if ($code -eq 0) { throw 'expected compile to fail for bad_all.mk' }
Write-Host "negative test failed as expected"

Write-Host 'all PE tests passed'
