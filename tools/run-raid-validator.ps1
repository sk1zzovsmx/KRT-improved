param(
    [Parameter(Mandatory = $true)]
    [string]$SavedVariablesPath,
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

$validatorPath = Resolve-Path (Join-Path $repoRoot "tools/validate-raid-schema.lua")
$svPath = Resolve-Path -LiteralPath $SavedVariablesPath
$luaRuntime = Resolve-LuaRuntime -Preferred $Runtime

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
