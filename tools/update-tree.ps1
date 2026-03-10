param(
    [string]$OutputPath = "docs/TREE.md",
    [int]$MaxDepth = 3,
    [switch]$IncludeMetadata
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

function Get-Children {
    param([string]$Path)
    Get-ChildItem -LiteralPath $Path -Force |
        Where-Object { $_.Name -ne ".git" } |
        Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name
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
$content.Add('_Regenerate with `tools/update-tree.ps1`._')

Set-Content -Path $OutputPath -Value $content -Encoding utf8
Write-Host "Updated $OutputPath"
