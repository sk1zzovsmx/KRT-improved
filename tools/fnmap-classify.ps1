Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

$csvPath = Join-Path $repoRoot "docs/FUNCTION_REGISTRY.csv"
if (-not (Test-Path -LiteralPath $csvPath)) {
    throw "Missing docs/FUNCTION_REGISTRY.csv. Run tools/fnmap-inventory.ps1 first."
}

function Normalize-Path([string]$fullPath) {
    $full = [System.IO.Path]::GetFullPath($fullPath)
    $root = [System.IO.Path]::GetFullPath($repoRoot.Path)
    if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($root.Length).TrimStart("\", "/") -replace "\\", "/"
    }
    return ($fullPath -replace "\\", "/")
}

function Get-FunctionKey([string]$name) {
    if ($name -match "^anonymous@") {
        return $name
    }
    if ($name -match "([A-Za-z_][A-Za-z0-9_]*)$") {
        return $Matches[1]
    }
    return $name
}

function Get-SeedCluster([object]$row, [string]$functionKey) {
    $fn = $row.Function
    $file = $row.File

    if ($fn -eq "Core.GetFeatureShared" -or $fn -eq "Core.getFeatureShared") {
        return "core.bootstrap.getFeatureShared"
    }
    if (
        $fn -eq "Core.EnsureLootRuntimeState" -or
        $fn -eq "Core.ensureLootRuntimeState" -or
        $functionKey -eq "ensureLootRuntimeState"
    ) {
        return "core.bootstrap.ensureLootRuntimeState"
    }
    if ($functionKey -match "^FormatReserve(ItemIdLabel|ItemFallback|DroppedBy)$") {
        return ("reserves.formatters.{0}" -f $functionKey)
    }
    if (
        $functionKey -match "^[gG]et(Master|Logger|Warnings|Changes|Spammer)Controller$" -or
        $fn -eq "Core.GetController" -or
        $fn -eq "Core.getController" -or
        $functionKey -eq "getController"
    ) {
        return "entrypoints.controllerGetters.core"
    }
    if (
        $file -eq "!KRT/Modules/Strings.lua" -and
        ($functionKey -eq "splitArgs" -or $functionKey -eq "trimText")
    ) {
        return "strings.trim/split*"
    }
    if (
        ($file -eq "!KRT/Controllers/Warnings.lua" -or $file -eq "!KRT/Controllers/Changes.lua") -and
        ($functionKey -eq "LocalizeUIFrame" -or $functionKey -eq "UpdateUIFrame")
    ) {
        return "listPanel.localize/update"
    }

    return ""
}

function Get-BodyHash([object]$row, [hashtable]$cache) {
    $filePath = Join-Path $repoRoot ($row.File -replace "/", "\")
    if (-not (Test-Path -LiteralPath $filePath)) {
        return ""
    }
    if (-not $cache.ContainsKey($row.File)) {
        $cache[$row.File] = @(Get-Content -LiteralPath $filePath)
    }

    $lines = $cache[$row.File]
    if (-not $lines -or $lines.Count -eq 0) {
        return ""
    }

    $start = [Math]::Max(1, [int]$row.LineStart)
    $end = [Math]::Min([int]$row.LineEnd, $lines.Count)
    if ($end -lt $start) {
        $end = $lines.Count
    }

    $buffer = New-Object System.Collections.Generic.List[string]
    for ($i = $start; $i -le $end; $i++) {
        $line = $lines[$i - 1]
        $line = ($line -replace "--.*$", "").Trim()
        if ($line -ne "") {
            $buffer.Add($line)
        }
    }

    $normalized = [string]::Join("`n", $buffer)
    if ($normalized -eq "") {
        return ""
    }

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
        $hash = $sha1.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash) -replace "-", "").ToLowerInvariant()
    } finally {
        $sha1.Dispose()
    }
}

$rows = Import-Csv -Path $csvPath
$fileCache = @{}
$allowPoly = @(
    "OnLoad", "Refresh", "Toggle", "Hide", "Show", "Select", "Edit", "Delete", "Clear", "Announce"
)

foreach ($row in $rows) {
    $row.LineStart = [int]$row.LineStart
    $row.LineEnd = [int]$row.LineEnd
    $functionKey = Get-FunctionKey $row.Function
    $bodyHash = Get-BodyHash $row $fileCache
    $row | Add-Member -NotePropertyName FunctionKey -NotePropertyValue $functionKey -Force
    $row | Add-Member -NotePropertyName BodyHash -NotePropertyValue $bodyHash -Force
    $seed = Get-SeedCluster $row $row.FunctionKey
    if ([string]::IsNullOrWhiteSpace($row.Cluster) -and $seed -ne "") {
        $row.Cluster = $seed
    }
}

$groups = $rows | Group-Object FunctionKey

foreach ($group in $groups) {
    $functionKey = $group.Name
    $groupRows = $group.Group
    $hashes = $groupRows | ForEach-Object { $_.BodyHash } | Where-Object { $_ -ne "" } | Select-Object -Unique
    $hashCount = @($hashes).Count
    $dupCount = @($groupRows).Count

    foreach ($row in $groupRows) {
        if ($row.Function -match "^anonymous@") {
            $row.Class = "structural-pattern"
            $row.Action = "extract"
            continue
        }

        if ($allowPoly -contains $functionKey) {
            $row.Class = "api-polymorphic"
            $row.Action = "keep"
            continue
        }

        if (
            $row.Function -eq "Core.registerLegacyAlias" -or
            $row.Function -eq "Core.registerLegacyAliasPath"
        ) {
            $row.Class = "legacy-alias"
            $row.Action = "keep"
            continue
        }

        if (
            $row.Function -eq "Core.GetFeatureShared" -or
            $row.Function -eq "Core.EnsureLootRuntimeState" -or
            $row.Function -eq "Core.GetController"
        ) {
            $row.Class = "structural-pattern"
            $row.Action = "keep"
            continue
        }

        if (
            ($row.Type -eq "field_closure" -or $row.Type -eq "local_closure") -and
            $dupCount -gt 1
        ) {
            $row.Class = "structural-pattern"
            $row.Action = "extract"
            continue
        }

        if ($dupCount -gt 1 -and $hashCount -eq 1) {
            $row.Class = "clone-exact"
            $row.Action = "merge"
            continue
        }

        if ($dupCount -gt 1) {
            if ($functionKey -match "^FormatReserve(ItemIdLabel|ItemFallback|DroppedBy)$") {
                $row.Class = "clone-near"
                $row.Action = "merge"
                continue
            }
            if ($functionKey -eq "LocalizeUIFrame" -or $functionKey -eq "UpdateUIFrame") {
                $row.Class = "structural-pattern"
                $row.Action = "extract"
                continue
            }
            if (
                $functionKey -eq "splitArgs" -or
                $functionKey -eq "trimText"
            ) {
                $row.Class = "name-collision"
                $row.Action = "rename"
                continue
            }

            $row.Class = "name-collision"
            $row.Action = "rename"
            continue
        }

        if ([string]::IsNullOrWhiteSpace($row.Class)) {
            $row.Class = "structural-pattern"
        }
        if ([string]::IsNullOrWhiteSpace($row.Action)) {
            $row.Action = "keep"
        }
    }
}

foreach ($row in $rows) {
    if ([string]::IsNullOrWhiteSpace($row.Status)) {
        $row.Status = "open"
    }
}

$rows |
    Sort-Object Layer, File, LineStart |
    Select-Object Layer, File, LineStart, LineEnd, Function, Type, Exported, Owner,
        Calls, UsedBy, Cluster, Class, Action, Status |
    Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

$clusterPath = Join-Path $repoRoot "docs/FN_CLUSTERS.md"
$md = New-Object System.Collections.Generic.List[string]
$md.Add("# FN Clusters")
$md.Add("")
$md.Add('Generated by `tools/fnmap-classify.ps1`.')
$md.Add("")

$classCounts = $rows | Group-Object Class | Sort-Object Name
$md.Add("## Class Summary")
$md.Add("")
$md.Add("| Class | Count |")
$md.Add("| --- | ---: |")
foreach ($c in $classCounts) {
    $md.Add(("| {0} | {1} |" -f $c.Name, $c.Count))
}
$md.Add("")

function Add-Section(
    [System.Collections.Generic.List[string]]$target,
    [string]$title,
    [object[]]$items
) {
    $target.Add("## $title")
    $target.Add("")
    $target.Add("| Cluster | Function | Class | Action | File | Line |")
    $target.Add("| --- | --- | --- | --- | --- | ---: |")
    foreach ($row in ($items | Sort-Object Cluster, Function, File, LineStart)) {
        $cluster = if ([string]::IsNullOrWhiteSpace($row.Cluster)) { "-" } else { $row.Cluster }
        $target.Add(
            ("| {0} | {1} | {2} | {3} | {4} | {5} |" -f
                $cluster, $row.Function, $row.Class, $row.Action, $row.File, $row.LineStart)
        )
    }
    $target.Add("")
}

$mergeNow = $rows | Where-Object {
    ($_.Action -eq "merge") -or
    (
        $_.Action -eq "extract" -and
        ($_.Function -eq "LocalizeUIFrame" -or $_.Function -eq "UpdateUIFrame")
    ) -or
    (
        -not [string]::IsNullOrWhiteSpace($_.Cluster) -and
        $_.Action -in @("merge", "extract")
    )
}
$rename = $rows | Where-Object {
    $_.Action -eq "rename" -and $_.Function -notmatch "^anonymous@"
}
$keep = $rows | Where-Object {
    $_.Action -eq "keep" -and -not [string]::IsNullOrWhiteSpace($_.Cluster)
}

Add-Section -target $md -title "merge-now" -items $mergeNow
Add-Section -target $md -title "rename" -items $rename
Add-Section -target $md -title "keep" -items $keep

Set-Content -Path $clusterPath -Value $md -Encoding UTF8

Write-Host "Function classification complete." -ForegroundColor Green
Write-Host ("CSV: {0}" -f (Normalize-Path $csvPath))
Write-Host ("MD : {0}" -f (Normalize-Path $clusterPath))
