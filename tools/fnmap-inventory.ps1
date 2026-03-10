param(
    [switch]$IncludeAnonymousCallbacks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

$scanRoots = @(
    "!KRT/Core",
    "!KRT/Init.lua",
    "!KRT/Modules",
    "!KRT/Services",
    "!KRT/Controllers",
    "!KRT/Widgets",
    "!KRT/EntryPoints",
    "!KRT/Localization"
)

function Get-Layer([string]$filePath) {
    $normalized = $filePath -replace "\\", "/"
    if ($normalized -match "^!KRT/([^/]+)/") {
        return $Matches[1]
    }
    if ($normalized -eq "!KRT/Init.lua") {
        return "Root"
    }
    return "Other"
}

function Get-Owner([string]$functionName, [string]$typeName) {
    if ($typeName -eq "anonymous_callback") {
        return "local"
    }
    if ($functionName -match "^([A-Za-z_][A-Za-z0-9_]*)[:\.]") {
        return $Matches[1]
    }
    return "local"
}

function Normalize-Path([string]$fullPath) {
    $full = [System.IO.Path]::GetFullPath($fullPath)
    $root = [System.IO.Path]::GetFullPath($repoRoot.Path)
    if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($root.Length).TrimStart("\", "/") -replace "\\", "/"
    }
    return ($fullPath -replace "\\", "/")
}

function Add-Entry([System.Collections.Generic.List[object]]$entries, [hashtable]$entry) {
    $entries.Add([pscustomobject]$entry)
}

$luaFiles = New-Object System.Collections.Generic.List[string]
foreach ($root in $scanRoots) {
    if (-not (Test-Path -LiteralPath $root)) {
        continue
    }
    $item = Get-Item -LiteralPath $root
    if ($item.PSIsContainer) {
        $files = Get-ChildItem -Path $root -Recurse -File -Filter "*.lua"
        foreach ($f in $files) {
            $luaFiles.Add($f.FullName)
        }
    } else {
        $luaFiles.Add($item.FullName)
    }
}

$entries = New-Object System.Collections.Generic.List[object]
$fileLineCount = @{}

foreach ($fullFile in ($luaFiles | Sort-Object -Unique)) {
    $repoPath = Normalize-Path $fullFile
    $layer = Get-Layer $repoPath
    $lines = Get-Content -LiteralPath $fullFile
    $fileLineCount[$repoPath] = $lines.Count

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $lineNo = $i + 1
        $matched = $false

        if ($line -match "^\s*local\s+function\s+([A-Za-z_][A-Za-z0-9_:\.]*)\s*\(") {
            $fn = $Matches[1]
            Add-Entry $entries @{
                Layer = $layer
                File = $repoPath
                LineStart = $lineNo
                LineEnd = $lineNo
                Function = $fn
                Type = "local_function"
                Exported = "No"
                Owner = Get-Owner $fn "local_function"
                Calls = ""
                UsedBy = ""
                Cluster = ""
                Class = ""
                Action = ""
                Status = "new"
            }
            $matched = $true
        } elseif ($line -match "^\s*function\s+([A-Za-z_][A-Za-z0-9_:\.]*)\s*\(") {
            $fn = $Matches[1]
            $typeName = if ($fn.Contains(":")) { "method_colon" } else { "method_dot" }
            Add-Entry $entries @{
                Layer = $layer
                File = $repoPath
                LineStart = $lineNo
                LineEnd = $lineNo
                Function = $fn
                Type = $typeName
                Exported = "Yes"
                Owner = Get-Owner $fn $typeName
                Calls = ""
                UsedBy = ""
                Cluster = ""
                Class = ""
                Action = ""
                Status = "new"
            }
            $matched = $true
        } elseif ($line -match "^\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function\s*\(") {
            $fn = $Matches[1]
            Add-Entry $entries @{
                Layer = $layer
                File = $repoPath
                LineStart = $lineNo
                LineEnd = $lineNo
                Function = $fn
                Type = "local_closure"
                Exported = "No"
                Owner = Get-Owner $fn "local_closure"
                Calls = ""
                UsedBy = ""
                Cluster = ""
                Class = ""
                Action = ""
                Status = "new"
            }
            $matched = $true
        } elseif ($line -match "^\s*([A-Za-z_][A-Za-z0-9_:\.\[\]]*)\s*=\s*function\s*\(") {
            $fn = $Matches[1]
            Add-Entry $entries @{
                Layer = $layer
                File = $repoPath
                LineStart = $lineNo
                LineEnd = $lineNo
                Function = $fn
                Type = "field_closure"
                Exported = "Yes"
                Owner = Get-Owner $fn "field_closure"
                Calls = ""
                UsedBy = ""
                Cluster = ""
                Class = ""
                Action = ""
                Status = "new"
            }
            $matched = $true
        }

        if ($IncludeAnonymousCallbacks -and -not $matched -and $line -match "\bfunction\s*\(") {
            $fn = "anonymous@$lineNo"
            Add-Entry $entries @{
                Layer = $layer
                File = $repoPath
                LineStart = $lineNo
                LineEnd = $lineNo
                Function = $fn
                Type = "anonymous_callback"
                Exported = "No"
                Owner = "local"
                Calls = ""
                UsedBy = ""
                Cluster = ""
                Class = ""
                Action = ""
                Status = "new"
            }
        }
    }
}

$entriesByFile = $entries | Group-Object File
foreach ($group in $entriesByFile) {
    $items = @($group.Group | Sort-Object LineStart)
    for ($i = 0; $i -lt $items.Count; $i++) {
        $current = $items[$i]
        $maxLine = [int]$fileLineCount[$group.Name]
        if ($i -lt ($items.Count - 1)) {
            $nextStart = [int]$items[$i + 1].LineStart
            $current.LineEnd = [Math]::Max([int]$current.LineStart, $nextStart - 1)
        } else {
            $current.LineEnd = [Math]::Max([int]$current.LineStart, $maxLine)
        }
    }
}

$docsDir = Join-Path $repoRoot "docs"
if (-not (Test-Path -LiteralPath $docsDir)) {
    New-Item -ItemType Directory -Path $docsDir | Out-Null
}

$csvPath = Join-Path $docsDir "FUNCTION_REGISTRY.csv"
$entries |
    Sort-Object Layer, File, LineStart |
    Select-Object Layer, File, LineStart, LineEnd, Function, Type, Exported, Owner,
        Calls, UsedBy, Cluster, Class, Action, Status |
    Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

$curated = $entries | Where-Object {
    $_.Type -ne "anonymous_callback" -and (
        $_.Exported -eq "Yes" -or
        $_.Function -match "ensureLootRuntimeState|getFeatureShared|FormatReserve|getController|split|trim|Localize|Update"
    )
}

$mdPath = Join-Path $docsDir "FUNCTION_REGISTRY.md"
$mdLines = New-Object System.Collections.Generic.List[string]
$mdLines.Add("# Function Registry")
$mdLines.Add("")
$mdLines.Add('Generated by `tools/fnmap-inventory.ps1`.')
$mdLines.Add(("- IncludeAnonymousCallbacks: {0}" -f ($IncludeAnonymousCallbacks.IsPresent.ToString().ToLowerInvariant())))
$mdLines.Add("")
$mdLines.Add('Raw CSV: `docs/FUNCTION_REGISTRY.csv`.')
$mdLines.Add("")

$layers = $curated | Group-Object Layer | Sort-Object Name
foreach ($layerGroup in $layers) {
    $mdLines.Add("## $($layerGroup.Name)")
    $mdLines.Add("")
    $mdLines.Add("| Function | Type | Exported | File | Line | Owner |")
    $mdLines.Add("| --- | --- | --- | --- | ---: | --- |")
    $rows = $layerGroup.Group | Sort-Object File, LineStart
    foreach ($row in $rows) {
        $mdLines.Add(
            ("| {0} | {1} | {2} | {3} | {4} | {5} |" -f
                $row.Function, $row.Type, $row.Exported, $row.File, $row.LineStart, $row.Owner)
        )
    }
    $mdLines.Add("")
}

Set-Content -Path $mdPath -Value $mdLines -Encoding UTF8

Write-Host ("Function inventory complete. Entries={0}" -f $entries.Count) -ForegroundColor Green
Write-Host ("CSV: {0}" -f (Normalize-Path $csvPath))
Write-Host ("MD : {0}" -f (Normalize-Path $mdPath))
