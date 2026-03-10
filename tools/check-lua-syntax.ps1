Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$luacheckCmd = Get-Command luacheck -ErrorAction SilentlyContinue
if (-not $luacheckCmd) {
    Write-Host "luacheck not found in PATH." -ForegroundColor Red
    exit 1
}

$rgCmd = Get-Command rg -ErrorAction SilentlyContinue
if ($rgCmd) {
    $files = @(& $rgCmd.Source --files -g "*.lua")
    if ($LASTEXITCODE -ne 0) {
        throw "rg failed while enumerating Lua files."
    }
} else {
    Write-Host "rg not found in PATH; falling back to Get-ChildItem." -ForegroundColor Yellow
    $files = @(Get-ChildItem -Path "." -Recurse -File -Filter "*.lua" | ForEach-Object { $_.FullName })
}

if ($files.Count -eq 0) {
    Write-Host "No Lua files found. Nothing to check."
    exit 0
}

Write-Host ("Checking Lua syntax in {0} files..." -f $files.Count)

$args = @(
    "--no-config",
    "--std",
    "lua51",
    "--only",
    "0",
    "--no-color",
    "--codes"
)
$args += $files

$output = & $luacheckCmd.Source @args 2>&1
$exitCode = $LASTEXITCODE
foreach ($line in @($output)) {
    Write-Host $line
}

if ($exitCode -ne 0) {
    Write-Host "Lua syntax check failed." -ForegroundColor Red
    exit $exitCode
}

Write-Host "Lua syntax check passed." -ForegroundColor Green
