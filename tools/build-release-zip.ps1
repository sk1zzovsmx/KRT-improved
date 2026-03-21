param(
    [string]$OutputDir = "dist",
    [string]$Version = "",
    [string]$FileName = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$toolingCommonPath = Join-Path $PSScriptRoot "tooling-common.ps1"
if (-not (Test-Path -LiteralPath $toolingCommonPath)) {
    $toolingCommonPath = Join-Path (Split-Path -Parent $PSScriptRoot) "tooling-common.ps1"
}
. $toolingCommonPath

$repoRoot = Enter-KrtRepoRoot -ScriptRoot $PSScriptRoot
$addonName = "!KRT"
$addonPath = Join-Path $repoRoot $addonName
if (-not (Test-Path -LiteralPath $addonPath -PathType Container)) {
    throw "Addon folder not found: $addonPath"
}

$tocPath = Join-Path $addonPath "!KRT.toc"
if (-not (Test-Path -LiteralPath $tocPath -PathType Leaf)) {
    throw "TOC file not found: $tocPath"
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $versionMatch = Select-String -Path $tocPath -Pattern '^## Version:\s*(.+)\s*$' | Select-Object -First 1
    if ($versionMatch) {
        $Version = $versionMatch.Matches[0].Groups[1].Value.Trim()
    }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = "dev"
}

$safeVersion = ($Version -replace '[\\/:*?"<>| ]', "-")
if ([string]::IsNullOrWhiteSpace($FileName)) {
    $FileName = "{0}-{1}.zip" -f $addonName, $safeVersion
}

$outputRoot = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    [System.IO.Path]::GetFullPath($OutputDir)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputDir))
}
if (-not (Test-Path -LiteralPath $outputRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
}

$zipPath = Join-Path $outputRoot $FileName
if (Test-Path -LiteralPath $zipPath -PathType Leaf) {
    Remove-Item -LiteralPath $zipPath -Force
}

Write-Host ("Building release archive: {0}" -f $zipPath)
Push-Location $repoRoot
try {
    Compress-Archive -LiteralPath $addonName -DestinationPath $zipPath -CompressionLevel Optimal -Force
} finally {
    Pop-Location
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $unexpectedEntries = @(
        $zip.Entries | Where-Object {
            $entryName = ($_.FullName -replace "\\", "/")
            if ([string]::IsNullOrWhiteSpace($entryName)) {
                return $false
            }
            return -not ($entryName -eq "$addonName/" -or $entryName.StartsWith("$addonName/"))
        }
    )
} finally {
    $zip.Dispose()
}

if ($unexpectedEntries.Count -gt 0) {
    $sample = ($unexpectedEntries | Select-Object -First 5 | ForEach-Object { $_.FullName }) -join ", "
    throw "Archive validation failed. Unexpected entries: $sample"
}

Write-Host ("Archive ready: {0}" -f $zipPath) -ForegroundColor Green
Write-Host ("Contents root: {0}/" -f $addonName)
