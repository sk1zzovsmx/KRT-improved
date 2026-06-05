param(
    [string]$OutputPath = "docs/TREE.md",
    [int]$MaxDepth = 4,
    [switch]$IncludeMetadata
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$toolingCommonPath = Join-Path $PSScriptRoot "tooling-common.ps1"
. $toolingCommonPath

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

$trackedFiles = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
$trackedDirs = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
$tracked = & git ls-files
foreach ($path in $tracked) {
    $normalized = $path.Replace("\", "/")
    [void]$trackedFiles.Add($normalized)

    $parts = @($normalized -split "/")
    for ($i = 1; $i -lt $parts.Count; $i = $i + 1) {
        $dir = ($parts[0..($i - 1)] -join "/")
        [void]$trackedDirs.Add($dir)
    }
}

function Get-RepoRelativePath {
    param([System.IO.FileSystemInfo]$Item)

    $root = $repoRoot.ProviderPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $fullName = $Item.FullName
    if ($fullName.Length -le $root.Length) {
        return ""
    }

    $relative = $fullName.Substring($root.Length + 1)
    return $relative.Replace("\", "/")
}

function Test-IsTrackedTreeItem {
    param([System.IO.FileSystemInfo]$Item)

    $relative = Get-RepoRelativePath -Item $Item
    if ($Item.PSIsContainer) {
        return $trackedDirs.Contains($relative)
    }

    return $trackedFiles.Contains($relative)
}

function Get-Children {
    param([string]$Path)

    $children = New-Object System.Collections.Generic.List[System.IO.FileSystemInfo]
    Get-ChildItem -LiteralPath $Path -Force |
        Where-Object { $_.Name -ne ".git" -and (Test-IsTrackedTreeItem -Item $_) } |
        ForEach-Object { [void]$children.Add($_) }

    $comparison = [System.Comparison[System.IO.FileSystemInfo]] {
        param($left, $right)

        if ($left.PSIsContainer -and -not $right.PSIsContainer) {
            return -1
        }
        if (-not $left.PSIsContainer -and $right.PSIsContainer) {
            return 1
        }

        return [System.StringComparer]::OrdinalIgnoreCase.Compare($left.Name, $right.Name)
    }
    $children.Sort($comparison)

    return @($children)
}

function Get-TreeLines {
    param(
        [string]$Path,
        [string]$Prefix,
        [int]$Depth,
        [int]$DepthLimit
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $children = @(Get-Children -Path $Path)

    for ($i = 0; $i -lt $children.Count; $i = $i + 1) {
        $item = $children[$i]
        $isLast = ($i -eq ($children.Count - 1))
        $branch = if ($isLast) { "\\-- " } else { "|-- " }
        $nextPrefix = if ($isLast) { "$Prefix    " } else { "$Prefix|   " }

        $lines.Add("$Prefix$branch$($item.Name)")

        if (-not $item.PSIsContainer) {
            continue
        }

        if (($Depth + 1) -ge $DepthLimit) {
            $hasChildren = @(Get-Children -Path $item.FullName).Count -gt 0
            if ($hasChildren) {
                $lines.Add("$nextPrefix\\-- ...")
            }
            continue
        }

        $childLines = Get-TreeLines -Path $item.FullName -Prefix $nextPrefix -Depth ($Depth + 1) -DepthLimit $DepthLimit
        foreach ($line in $childLines) {
            $lines.Add($line)
        }
    }

    return $lines
}

$treeLines = New-Object System.Collections.Generic.List[string]
$treeLines.Add(".")
$rootLines = Get-TreeLines -Path $repoRoot -Prefix "" -Depth 0 -DepthLimit $MaxDepth
foreach ($line in $rootLines) {
    $treeLines.Add($line)
}

$content = New-Object System.Collections.Generic.List[string]
$content.Add("# Repository Tree")
$content.Add("")
$content.Add("- MaxDepth: $MaxDepth")
$content.Add("- Deterministic: true")
if ($IncludeMetadata) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss K"
    $commit = (& git rev-parse --short HEAD 2>$null)
    if (-not $commit) {
        $commit = "unknown"
    }

    $dirty = (& git status --short 2>$null)
    $worktree = if ($dirty) { "dirty" } else { "clean" }

    $content.Add("- Generated: $timestamp")
    $content.Add("- Commit: $commit")
    $content.Add("- Worktree: $worktree")
}
$content.Add("")
$content.Add('```text')
foreach ($line in $treeLines) {
    $content.Add($line)
}
$content.Add('```')
$content.Add("")
$content.Add("_Regenerate with tools/update-tree.ps1 -MaxDepth $MaxDepth._")

Write-KrtUtf8NoBom -Path $OutputPath -Value $content
Write-Host "Updated $OutputPath"
