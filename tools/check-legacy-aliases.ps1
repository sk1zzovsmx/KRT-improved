Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$toolingCommonPath = Join-Path $PSScriptRoot "tooling-common.ps1"
if (-not (Test-Path -LiteralPath $toolingCommonPath)) {
    $toolingCommonPath = Join-Path (Split-Path -Parent $PSScriptRoot) "tooling-common.ps1"
}
. $toolingCommonPath
$repoRoot = Enter-KrtRepoRoot -ScriptRoot $PSScriptRoot

$addonRoot = Join-Path $repoRoot "!KRT"
$libsRoot = [System.IO.Path]::GetFullPath((Join-Path $addonRoot "Libs"))
$libsRootPrefix = $libsRoot.TrimEnd("\", "/") + [System.IO.Path]::DirectorySeparatorChar
$legacyAliases = @(
    "Raid",
    "Chat",
    "Master",
    "Logger",
    "LootCounter",
    "ReservesUI",
    "Config",
    "Warnings",
    "Changes",
    "Spammer",
    "Loot",
    "Rolls"
)

$aliasPattern = [string]::Join("|", ($legacyAliases | ForEach-Object { [regex]::Escape($_) }))
$legacyAliasPattern = "\baddon\.(?:$aliasPattern)\b|\baddon\s*\[\s*(['""])(?:$aliasPattern)\1\s*\]"
$violations = New-Object System.Collections.Generic.List[string]

foreach ($file in Get-ChildItem -LiteralPath $addonRoot -Recurse -File -Filter "*.lua") {
    $fullPath = [System.IO.Path]::GetFullPath($file.FullName)
    if ($fullPath.StartsWith($libsRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        continue
    }

    $lineNo = 0
    foreach ($line in Get-Content -LiteralPath $file.FullName) {
        $lineNo = $lineNo + 1
        if ($line -cmatch $legacyAliasPattern) {
            $relative = ConvertTo-KrtRepoRelativePath -RepoRoot $repoRoot -Path $file.FullName -UseForwardSlashes
            $violations.Add(("{0}:{1}: {2}" -f $relative, $lineNo, $line.TrimEnd()))
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host "Legacy alias check failed." -ForegroundColor Red
    Write-Host "Retired top-level addon aliases must not be referenced directly:"
    Write-Host ("  {0}" -f ($legacyAliases -join ", "))
    Write-Host "Use canonical namespaced owners such as addon.Services.*, addon.Controllers.*, or addon.Widgets.*."
    foreach ($line in $violations) {
        Write-Host "  $line"
    }
    exit 1
}

Write-Host "Legacy alias check passed." -ForegroundColor Green
Write-Host "Checked:"
Write-Host "  KRT-owned Lua under !KRT/**/*.lua"
Write-Host "  Excluded vendored Lua under !KRT/Libs"
Write-Host "  No direct addon.LegacyAlias or bracket addon['LegacyAlias'] references"
