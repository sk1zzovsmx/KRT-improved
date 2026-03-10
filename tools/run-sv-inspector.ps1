param(
    [Parameter(Mandatory = $true)]
    [string]$SavedVariablesPath,
    [ValidateSet("table", "csv")]
    [string]$Format = "table",
    [ValidateSet("all", "baseline", "raids", "sanity")]
    [string]$Section = "all",
    [string]$Out = "",
    [string]$Runtime = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Resolve-LuaRuntime {
    param([string]$Preferred)

    if ($Preferred -and $Preferred.Trim() -ne "") {
        $command = Get-Command $Preferred -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Source
        }
        throw "Requested runtime '$Preferred' not found in PATH."
    }

    foreach ($name in @("lua", "luajit")) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Source
        }
    }

    return $null
}

$inspectorPath = Resolve-Path (Join-Path $repoRoot "tools/sv-inspector.lua")
$svPath = Resolve-Path -LiteralPath $SavedVariablesPath
$luaRuntime = Resolve-LuaRuntime -Preferred $Runtime

if (-not $luaRuntime) {
    Write-Host "Lua runtime not found. Install 'lua' or 'luajit' and retry." -ForegroundColor Red
    exit 1
}

$argsList = @($inspectorPath.Path, $svPath.Path, "--format", $Format, "--section", $Section)
if ($Out -and $Out.Trim() -ne "") {
    $argsList += @("--out", $Out)
}

Write-Host "Running SV inspector..."
Write-Host "  runtime:   $luaRuntime"
Write-Host "  inspector: $($inspectorPath.Path)"
Write-Host "  input:     $($svPath.Path)"
Write-Host "  format:    $Format"
Write-Host "  section:   $Section"
if ($Out -and $Out.Trim() -ne "") {
    Write-Host "  output:    $Out"
}

& $luaRuntime @argsList
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Host "SV inspector failed (exit code: $exitCode)." -ForegroundColor Red
    exit $exitCode
}

Write-Host "SV inspector completed successfully." -ForegroundColor Green

