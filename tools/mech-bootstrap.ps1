param(
    [string]$MechanicRoot,
    [string]$RepoUrl = "https://github.com/Falkicon/Mechanic.git",
    [string]$Ref = "main",
    [switch]$Pull,
    [switch]$SkipPipUpgrade,
    [switch]$RunSetupTools
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($MechanicRoot)) {
    if (-not [string]::IsNullOrWhiteSpace($env:KRT_MECHANIC_ROOT)) {
        $MechanicRoot = $env:KRT_MECHANIC_ROOT
    } else {
        $MechanicRoot = "C:\dev\Mechanic"
    }
}

function Resolve-PythonLauncher {
    $pyCmd = Get-Command py -ErrorAction SilentlyContinue
    if ($pyCmd) {
        return @($pyCmd.Source, "-3")
    }

    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        return @($pythonCmd.Source)
    }

    throw "Python launcher not found. Install Python 3 and ensure 'py' or 'python' is in PATH."
}

function Invoke-ProcessOrThrow {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$WorkingDirectory
    )

    if ($WorkingDirectory) {
        & $FilePath @Arguments
    } else {
        & $FilePath @Arguments
    }

    if ($LASTEXITCODE -ne 0) {
        throw ("Command failed ({0}): {1}" -f $LASTEXITCODE, ($FilePath + " " + ($Arguments -join " ")))
    }
}

$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) {
    throw "git not found in PATH."
}

$pythonCommand = Resolve-PythonLauncher
$pythonExe = $pythonCommand[0]
$pythonPrefix = @()
if ($pythonCommand.Count -gt 1) {
    $pythonPrefix = $pythonCommand[1..($pythonCommand.Count - 1)]
}

$mechanicRootFullPath = [System.IO.Path]::GetFullPath($MechanicRoot)
$desktopPath = Join-Path $mechanicRootFullPath "desktop"
$venvPython = Join-Path $desktopPath ".venv\Scripts\python.exe"
$venvMech = Join-Path $desktopPath ".venv\Scripts\mech.exe"

if (-not (Test-Path -LiteralPath $mechanicRootFullPath)) {
    $parent = Split-Path -Path $mechanicRootFullPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Write-Host ("Cloning Mechanic into {0}" -f $mechanicRootFullPath)
    Invoke-ProcessOrThrow -FilePath $gitCmd.Source -Arguments @(
        "clone",
        "--branch",
        $Ref,
        "--single-branch",
        $RepoUrl,
        $mechanicRootFullPath
    )
} else {
    Write-Host ("Mechanic root already exists: {0}" -f $mechanicRootFullPath)
    if ($Pull) {
        Write-Host "Updating repository..."
        Invoke-ProcessOrThrow `
            -FilePath $gitCmd.Source `
            -Arguments @("-C", $mechanicRootFullPath, "fetch", "origin")
        Invoke-ProcessOrThrow -FilePath $gitCmd.Source -Arguments @("-C", $mechanicRootFullPath, "checkout", $Ref)
        Invoke-ProcessOrThrow `
            -FilePath $gitCmd.Source `
            -Arguments @("-C", $mechanicRootFullPath, "pull", "--ff-only", "origin", $Ref)
    }
}

if (-not (Test-Path -LiteralPath $desktopPath -PathType Container)) {
    throw "Mechanic desktop folder not found: $desktopPath"
}

if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
    Write-Host "Creating virtual environment..."
    $venvArgs = @()
    $venvArgs += $pythonPrefix
    $venvArgs += @("-m", "venv", (Join-Path $desktopPath ".venv"))
    Invoke-ProcessOrThrow -FilePath $pythonExe -Arguments $venvArgs
}

if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
    throw "Virtual environment python not found after creation: $venvPython"
}

if (-not $SkipPipUpgrade) {
    Write-Host "Upgrading pip in venv..."
    Invoke-ProcessOrThrow -FilePath $venvPython -Arguments @("-m", "pip", "install", "--upgrade", "pip")
}

Write-Host "Installing Mechanic desktop package (editable)..."
Push-Location $desktopPath
try {
    Invoke-ProcessOrThrow -FilePath $venvPython -Arguments @("-m", "pip", "install", "-e", ".")
} finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $venvMech -PathType Leaf)) {
    throw "mech executable not found after install: $venvMech"
}

if ($RunSetupTools) {
    Write-Host "Running 'mech setup --skip-config'..."
    & $venvMech setup --skip-config
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "mech setup returned a non-zero exit code. Check output and rerun manually if needed."
    }
}

Write-Host ""
Write-Host "Mechanic bootstrap completed."
Write-Host ("Mechanic root: {0}" -f $mechanicRootFullPath)
Write-Host ("CLI path: {0}" -f $venvMech)
Write-Host ""
Write-Host "Quick checks:"
Write-Host ("  {0} --help" -f $venvMech)
Write-Host ("  {0} call env.status" -f $venvMech)
