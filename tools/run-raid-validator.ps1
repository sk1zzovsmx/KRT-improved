param(
    [Parameter(Mandatory = $true)]
    [string]$SavedVariablesPath,
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

$validatorPath = Resolve-Path (Join-Path $repoRoot "tools/validate-raid-schema.lua")
$svPath = Resolve-KrtInputPath -Path $SavedVariablesPath -BasePath $invocationLocation
$luaRuntime = Resolve-KrtLuaRuntime -Preferred $Runtime

if (-not $luaRuntime) {
    Write-Host "Lua runtime not found. Install 'lua' or 'luajit' and retry." -ForegroundColor Red
    exit 1
}

$svHasRaidKey = Select-String -Path $svPath.Path -Pattern "\bKRT_Raids\b" -Quiet
if (-not $svHasRaidKey) {
    Write-Host "Warning: '$($svPath.Path)' does not contain 'KRT_Raids' text." -ForegroundColor Yellow
}

Write-Host "Running validator..."
Write-Host "  runtime:  $luaRuntime"
Write-Host "  validator: $($validatorPath.Path)"
Write-Host "  input:    $($svPath.Path)"

& $luaRuntime $validatorPath.Path $svPath.Path
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Host "Raid validator failed (exit code: $exitCode)." -ForegroundColor Red
    exit $exitCode
}

Write-Host "Raid validator completed successfully." -ForegroundColor Green
