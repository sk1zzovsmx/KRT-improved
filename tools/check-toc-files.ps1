Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$toolingCommonPath = Join-Path $PSScriptRoot "tooling-common.ps1"
if (-not (Test-Path -LiteralPath $toolingCommonPath)) {
    $toolingCommonPath = Join-Path (Split-Path -Parent $PSScriptRoot) "tooling-common.ps1"
}
. $toolingCommonPath
$repoRoot = Enter-KrtRepoRoot -ScriptRoot $PSScriptRoot

$violations = New-Object System.Collections.Generic.List[string]
$savedVariableNotes = New-Object System.Collections.Generic.List[string]

function Normalize-TocEntry {
    param([string]$Entry)

    return ($Entry.Trim() -replace "/", "\")
}

$tocFiles = @(
    Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter "*.toc" |
        Where-Object { $_.FullName -notmatch [regex]::Escape("\Libs\") } |
        Sort-Object FullName
)
if ($tocFiles.Count -eq 0) {
    $violations.Add("[toc]")
    $violations.Add("  No .toc files found under repo root.")
}

foreach ($tocFile in $tocFiles) {
    $tocRelative = ConvertTo-KrtRepoRelativePath -RepoRoot $repoRoot -Path $tocFile.FullName -UseForwardSlashes
    $addonFolder = Split-Path -Leaf $tocFile.DirectoryName
    $tocBaseName = [System.IO.Path]::GetFileNameWithoutExtension($tocFile.Name)

    $isCanonicalName = $tocBaseName -eq $addonFolder
    $isFlavorName = $tocBaseName.StartsWith($addonFolder + "-", [System.StringComparison]::OrdinalIgnoreCase)
    if (-not ($isCanonicalName -or $isFlavorName)) {
        $violations.Add("[toc naming]")
        $violations.Add("  ${tocRelative}: TOC base name '$tocBaseName' does not match folder '$addonFolder'.")
    }

    $lines = Get-Content -LiteralPath $tocFile.FullName
    foreach ($rawLine in $lines) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line -match "^##\s*SavedVariables(?:PerCharacter)?\s*:\s*(.+)$") {
            $savedVariableNotes.Add("$tocRelative -> $($Matches[1].Trim())")
            continue
        }

        if ($line.StartsWith("##", [System.StringComparison]::Ordinal)) {
            continue
        }
        if ($line.StartsWith("#", [System.StringComparison]::Ordinal)) {
            continue
        }

        $entryPath = Join-Path $tocFile.DirectoryName (Normalize-TocEntry -Entry $line)
        if (-not (Test-Path -LiteralPath $entryPath)) {
            $violations.Add("[toc files]")
            $violations.Add("  ${tocRelative}: missing '$line'")
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host "TOC file checks failed." -ForegroundColor Red
    foreach ($line in $violations) {
        Write-Host $line
    }
    exit 1
}

Write-Host "TOC file checks passed." -ForegroundColor Green
Write-Host "Confirmed:"
Write-Host "  1) TOC names match addon folder names (or flavor-specific suffixes)"
Write-Host "  2) Every non-comment TOC entry resolves to an existing file"
if ($savedVariableNotes.Count -gt 0) {
    Write-Host "  3) SavedVariables declarations discovered:"
    foreach ($line in $savedVariableNotes) {
        Write-Host "     $line"
    }
} else {
    Write-Host "  3) No SavedVariables declarations were found in scanned TOCs"
}
