param(
    [string]$PythonExe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$serverPath = Join-Path $PSScriptRoot "krt_mcp_server.py"

if (-not (Test-Path -LiteralPath $serverPath -PathType Leaf)) {
    throw "MCP server not found: $serverPath"
}

if ([string]::IsNullOrWhiteSpace($PythonExe)) {
    $pyCmd = Get-Command py -ErrorAction SilentlyContinue
    if ($pyCmd) {
        & $pyCmd.Source -3 $serverPath
        exit $LASTEXITCODE
    }

    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        & $pythonCmd.Source $serverPath
        exit $LASTEXITCODE
    }

    throw "Python 3 not found. Install Python or pass -PythonExe explicitly."
}

$pythonFullPath = [System.IO.Path]::GetFullPath($PythonExe)
if (-not (Test-Path -LiteralPath $pythonFullPath -PathType Leaf)) {
    throw "Python executable not found: $pythonFullPath"
}

Push-Location $repoRoot
try {
    & $pythonFullPath $serverPath
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
