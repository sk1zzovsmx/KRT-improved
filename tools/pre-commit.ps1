Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Get-StagedLuaFiles {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return @()
    }

    $output = & git diff --cached --name-only --diff-filter=ACMR -- "*.lua" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --cached --name-only --diff-filter=ACMR -- '*.lua' failed."
    }

    return @($output | Where-Object { $_ -is [string] -and $_.Trim() -ne "" })
}

function Run-LuaChecks {
    param([string[]]$StagedLuaFiles)

    if (-not $StagedLuaFiles -or $StagedLuaFiles.Count -eq 0) {
        Write-Host "Skipping Lua gates (no staged .lua files)."
        return
    }

    Write-Host "Running Lua syntax check..."
    & (Join-Path $repoRoot "tools/check-lua-syntax.ps1")

    Write-Host "Running Luacheck..."
    $luacheckCmd = Get-Command luacheck -ErrorAction SilentlyContinue
    if (-not $luacheckCmd) {
        throw "luacheck not found in PATH."
    }
    & $luacheckCmd.Source --codes --no-color !KRT tools tests
    if ($LASTEXITCODE -ne 0) {
        throw "luacheck --codes --no-color !KRT tools tests failed."
    }

    Write-Host "Running Lua uniformity check..."
    & (Join-Path $repoRoot "tools/check-lua-uniformity.ps1")

    Write-Host "Running StyLua check..."
    $styluaCmd = Get-Command stylua -ErrorAction SilentlyContinue
    if (-not $styluaCmd) {
        throw "stylua not found in PATH."
    }
    & $styluaCmd.Source --check !KRT tools tests
    if ($LASTEXITCODE -ne 0) {
        throw "stylua --check !KRT tools tests failed."
    }
}

$stagedLuaFiles = Get-StagedLuaFiles

Write-Host "Running TOC file checks..."
& (Join-Path $repoRoot "tools/check-toc-files.ps1")

Write-Host "Running layering checks..."
& (Join-Path $repoRoot "tools/check-layering.ps1")

Write-Host "Running UI binding checks..."
& (Join-Path $repoRoot "tools/check-ui-binding.ps1")

Run-LuaChecks -StagedLuaFiles $stagedLuaFiles

Write-Host "Refreshing docs/TREE.md..."
& (Join-Path $repoRoot "tools/update-tree.ps1")

if (Get-Command git -ErrorAction SilentlyContinue) {
    $null = & git diff --quiet -- docs/TREE.md
    if ($LASTEXITCODE -gt 1) {
        throw "git diff --quiet docs/TREE.md failed."
    }

    if ($LASTEXITCODE -eq 1) {
        $null = & git add -- docs/TREE.md
        if ($LASTEXITCODE -ne 0) {
            throw "git add docs/TREE.md failed."
        }
    }
}

Write-Host "Pre-commit checks completed."
