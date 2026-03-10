Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$toolingCommonPath = Join-Path $PSScriptRoot "tooling-common.ps1"
if (-not (Test-Path -LiteralPath $toolingCommonPath)) {
    $toolingCommonPath = Join-Path (Split-Path -Parent $PSScriptRoot) "tooling-common.ps1"
}
. $toolingCommonPath
$repoRoot = Enter-KrtRepoRoot -ScriptRoot $PSScriptRoot

$violations = New-Object System.Collections.Generic.List[string]

$binderPath = Join-Path $repoRoot "!KRT/Modules/UI/Binder"
if (Test-Path -LiteralPath $binderPath) {
    $binderFiles = @(Get-ChildItem -LiteralPath $binderPath -Recurse -File)
    if ($binderFiles.Count -gt 0) {
        $violations.Add("[Binder files present]")
        foreach ($file in $binderFiles) {
            $relative = ConvertTo-KrtRepoRelativePath -RepoRoot $repoRoot -Path $file.FullName -UseForwardSlashes
            $violations.Add("  $relative")
        }
    }
}

$tocPath = Join-Path $repoRoot "!KRT/!KRT.toc"
if (Test-Path -LiteralPath $tocPath) {
    $tocMatches = @(Get-KrtPatternMatches -RepoRoot $repoRoot -Pattern 'Modules\\UI\\Binder' -Path $tocPath)
    if ($tocMatches.Count -gt 0) {
        $violations.Add("[TOC includes Binder]")
        foreach ($line in $tocMatches) {
            $violations.Add("  $line")
        }
    }
}

$xmlMatches = @(Get-KrtPatternMatches `
    -RepoRoot $repoRoot `
    -Pattern '<Scripts>|<On[A-Za-z]+>' `
    -Path "!KRT/UI" `
    -ExtraArgs @("--glob", "*.xml"))
if ($xmlMatches.Count -gt 0) {
    $violations.Add("[XML inline scripts]")
    foreach ($line in $xmlMatches) {
        $violations.Add("  $line")
    }
}

if ($violations.Count -gt 0) {
    Write-Host "UI binding checks failed." -ForegroundColor Red
    foreach ($line in $violations) {
        Write-Host $line
    }
    exit 1
}

Write-Host "UI binding checks passed." -ForegroundColor Green
Write-Host "Checked:"
Write-Host "  Binder files absent under !KRT/Modules/UI/Binder"
Write-Host "  !KRT/!KRT.toc has no Modules\\UI\\Binder entries"
Write-Host "  No <Scripts> / <On...> in !KRT/UI/**/*.xml"
