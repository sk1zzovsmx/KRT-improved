Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$cliPath = Join-Path $repoRoot "tools/krt.py"

$pyCmd = Get-Command py -ErrorAction SilentlyContinue
if ($pyCmd) {
    & $pyCmd.Source -3 $cliPath install-hooks
    exit $LASTEXITCODE
}

$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if ($pythonCmd) {
    & $pythonCmd.Source $cliPath install-hooks
    exit $LASTEXITCODE
}

throw "Python 3 not found. Install Python or use 'tools/krt.py install-hooks'."
