param(
    [string]$Runtime = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$toolingCommonPath = Join-Path $PSScriptRoot "tooling-common.ps1"
if (-not (Test-Path -LiteralPath $toolingCommonPath)) {
    $toolingCommonPath = Join-Path (Split-Path -Parent $PSScriptRoot) "tooling-common.ps1"
}
. $toolingCommonPath
$repoRoot = Enter-KrtRepoRoot -ScriptRoot $PSScriptRoot

if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$testPath = Resolve-Path (Join-Path $repoRoot "tests/release_stabilization_spec.lua")
$luaRuntime = Resolve-KrtLuaRuntime -Preferred $Runtime
if (-not $luaRuntime) {
    Write-Host "Lua runtime not found; skipping targeted stabilization tests." -ForegroundColor Yellow
    exit 0
}

Write-Host "Running targeted stabilization tests..."
Write-Host "  runtime: $luaRuntime"
Write-Host "  tests:   $($testPath.Path)"

& $luaRuntime $testPath.Path
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    Write-Host "Targeted stabilization tests failed." -ForegroundColor Red
    exit $exitCode
}

Write-Host "Targeted stabilization tests completed successfully." -ForegroundColor Green
