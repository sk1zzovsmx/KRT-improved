param(
    [string]$TargetPath = "",
    [switch]$Fixtures,
    [string]$Runtime = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$invocationLocation = Get-Location
$toolingCommonPath = Join-Path $PSScriptRoot "tooling-common.ps1"
if (-not (Test-Path -LiteralPath $toolingCommonPath)) {
    $toolingCommonPath = Join-Path (Split-Path -Parent $PSScriptRoot) "tooling-common.ps1"
}
. $toolingCommonPath
$repoRoot = Enter-KrtRepoRoot -ScriptRoot $PSScriptRoot

if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

if ($Fixtures -and [string]::IsNullOrWhiteSpace($TargetPath)) {
    $TargetPath = Join-Path $repoRoot "tests/fixtures/sv"
}

if ([string]::IsNullOrWhiteSpace($TargetPath)) {
    throw "Missing target path. Pass -TargetPath <file|dir> or use -Fixtures."
}

$validatorPath = Resolve-Path (Join-Path $repoRoot "tools/sv-roundtrip.lua")
$luaRuntime = Resolve-KrtLuaRuntime -Preferred $Runtime
if (-not $luaRuntime) {
    Write-Host "Lua runtime not found. Install 'lua' or 'luajit' and retry." -ForegroundColor Red
    exit 1
}

$target = Resolve-KrtInputPath -Path $TargetPath -BasePath $invocationLocation
$item = Get-Item -LiteralPath $target.Path

$inputs = @()
if ($item.PSIsContainer) {
    $inputs = @(Get-ChildItem -LiteralPath $item.FullName -File -Filter "*.lua" | Sort-Object Name)
    if ($inputs.Count -eq 0) {
        throw "No .lua files found under '$($item.FullName)'."
    }
} else {
    $inputs = @($item)
}

Write-Host "Running SV round-trip validator..."
Write-Host "  runtime:   $luaRuntime"
Write-Host "  validator: $($validatorPath.Path)"
Write-Host "  targets:   $($inputs.Count)"

$failed = 0
foreach ($input in $inputs) {
    Write-Host ""
    Write-Host ">>> $($input.FullName)"
    & $luaRuntime $validatorPath.Path $input.FullName
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $failed++
        Write-Host "FAILED (exit code: $exitCode)" -ForegroundColor Red
    } else {
        Write-Host "OK" -ForegroundColor Green
    }
}

if ($failed -gt 0) {
    Write-Host ""
    Write-Host "SV round-trip validation failed for $failed file(s)." -ForegroundColor Red
    exit 2
}

Write-Host ""
Write-Host "SV round-trip validation completed successfully." -ForegroundColor Green
