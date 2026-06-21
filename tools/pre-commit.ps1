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

function Get-StagedPythonToolingFiles {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return @()
    }

    $output = & git diff --cached --name-only --diff-filter=ACMR -- "*.py" "pyproject.toml" "tools/requirements-dev.txt" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --cached --name-only --diff-filter=ACMR for Python tooling files failed."
    }

    return @($output | Where-Object { $_ -is [string] -and $_.Trim() -ne "" })
}

function Invoke-KrtCli {
    param([string[]]$Arguments)

    $scriptPath = Join-Path $repoRoot "tools/krt.py"
    $venvPython = Join-Path $repoRoot ".venv\Scripts\python.exe"
    if (Test-Path -LiteralPath $venvPython) {
        & $venvPython $scriptPath @Arguments
    } else {
        $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
        if ($pyLauncher) {
            & $pyLauncher.Source -3 $scriptPath @Arguments
        } else {
            $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
            if (-not $pythonCmd) {
                $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
            }
            if (-not $pythonCmd) {
                throw "python3/python not found in PATH."
            }
            & $pythonCmd.Source $scriptPath @Arguments
        }
    }

    if ($LASTEXITCODE -ne 0) {
        throw ("tools/krt.py {0} failed." -f ($Arguments -join " "))
    }
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

    Write-Host "Running API nomenclature check (staged additions)..."
    & (Join-Path $repoRoot "tools/check-api-nomenclature.ps1")

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

function Run-PythonChecks {
    param([string[]]$StagedPythonToolingFiles)

    if (-not $StagedPythonToolingFiles -or $StagedPythonToolingFiles.Count -eq 0) {
        Write-Host "Skipping Python gates (no staged Python tooling files)."
        return
    }

    Write-Host "Running Python quality check..."
    Invoke-KrtCli @("python-quality-check")
}

$stagedLuaFiles = Get-StagedLuaFiles
$stagedPythonToolingFiles = Get-StagedPythonToolingFiles

Write-Host "Running TOC file checks..."
& (Join-Path $repoRoot "tools/check-toc-files.ps1")

Write-Host "Running layering checks..."
& (Join-Path $repoRoot "tools/check-layering.ps1")

Write-Host "Running retired alias checks..."
& (Join-Path $repoRoot "tools/check-retired-aliases.ps1")

Write-Host "Running UI binding checks..."
& (Join-Path $repoRoot "tools/check-ui-binding.ps1")

Run-LuaChecks -StagedLuaFiles $stagedLuaFiles
Run-PythonChecks -StagedPythonToolingFiles $stagedPythonToolingFiles

Write-Host "Running API catalog drift check..."
Invoke-KrtCli @("api-catalog-check")

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
