param(
    [string]$OutputDir = "dist",
    [string]$Version = "",
    [string]$FileName = "",
    [switch]$WriteChecksum
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$cliPath = Join-Path $repoRoot "tools/krt.py"
$argsList = @($cliPath, "build-release-zip", "--output-dir", $OutputDir)

if (-not [string]::IsNullOrWhiteSpace($Version)) {
    $argsList += @("--version", $Version)
}
if (-not [string]::IsNullOrWhiteSpace($FileName)) {
    $argsList += @("--file-name", $FileName)
}
if ($WriteChecksum) {
    $argsList += "--write-checksum"
}

$pyCmd = Get-Command py -ErrorAction SilentlyContinue
if ($pyCmd) {
    & $pyCmd.Source -3 @argsList
    exit $LASTEXITCODE
}

$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if ($pythonCmd) {
    & $pythonCmd.Source @argsList
    exit $LASTEXITCODE
}

throw "Python 3 not found. Install Python or use 'tools/krt.py build-release-zip'."
