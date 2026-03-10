Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

Write-Host "Running layering checks..."
& (Join-Path $repoRoot "tools/check-layering.ps1")

Write-Host "Running UI binding checks..."
& (Join-Path $repoRoot "tools/check-ui-binding.ps1")

Write-Host "Refreshing docs/TREE.md..."
& (Join-Path $repoRoot "tools/update-tree.ps1")

if (Get-Command git -ErrorAction SilentlyContinue) {
    $null = & cmd /c "git add -- docs/TREE.md 2>nul"
    if ($LASTEXITCODE -ne 0) {
        throw "git add docs/TREE.md failed."
    }
}

Write-Host "Pre-commit checks completed."
