param(
    [string]$OutputCsv = "docs/API_REGISTRY.csv",
    [string]$OutputPublicCsv = "docs/API_REGISTRY_PUBLIC.csv",
    [string]$OutputInternalCsv = "docs/API_REGISTRY_INTERNAL.csv",
    [string]$OutputMd = "docs/API_NOMENCLATURE_CENSUS.md"
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

function Normalize-Path([string]$fullPath) {
    $full = [System.IO.Path]::GetFullPath($fullPath)
    $root = [System.IO.Path]::GetFullPath($repoRoot.Path)
    if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($root.Length).TrimStart("\", "/") -replace "\\", "/"
    }
    return ($fullPath -replace "\\", "/")
}

function Resolve-OutputPath([string]$pathValue) {
    if ([System.IO.Path]::IsPathRooted($pathValue)) {
        return $pathValue
    }
    return Join-Path $repoRoot $pathValue
}

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

function Get-NameStyle([string]$name) {
    if ($name -cmatch "^[A-Z0-9_]+$") {
        return "UPPER"
    }
    if ($name -cmatch "^[A-Z][A-Za-z0-9]*$" -and $name -notmatch "_") {
        return "PascalCase"
    }
    if ($name -cmatch "^[a-z][A-Za-z0-9]*$" -and $name -notmatch "_") {
        return "camelCase"
    }
    if ($name -match "_") {
        return "snake_or_mixed"
    }
    return "mixed"
}

function Get-ApiScope([string]$target, [string]$method) {
    if ($method -match "^_") {
        return "Internal"
    }
    if ($target -match "(^|\.)_ui(\.|$)") {
        return "Internal"
    }
    return "Public"
}

function Get-TaxonomyInfo([string]$scope, [string]$style, [string]$method) {
    if ($scope -ne "Public") {
        return [pscustomobject]@{
            Verb = $method
            Category = "Internal"
            IsConformant = $true
        }
    }

    if ($style -eq "UPPER") {
        return [pscustomobject]@{
            Verb = $method
            Category = "Event"
            IsConformant = $true
        }
    }

    $exactLifecycle = @(
        "OnLoad",
        "OnLoadFrame",
        "AcquireRefs",
        "BindHandlers",
        "RefreshUI",
        "Refresh",
        "RequestRefresh",
        "Toggle",
        "Show",
        "Hide"
    )
    if ($exactLifecycle -contains $method) {
        return [pscustomobject]@{
            Verb = $method
            Category = "Lifecycle"
            IsConformant = $true
        }
    }

    $prefixGroups = @(
        [pscustomobject]@{ Prefixes = @("Get", "Find", "Is", "Can"); Category = "Query" },
        [pscustomobject]@{ Prefixes = @("Set", "Add", "Remove", "Delete", "Upsert"); Category = "Mutation" },
        [pscustomobject]@{
            Prefixes = @("Ensure", "Bind", "Localize", "Request", "RequestRefresh", "Refresh", "Toggle", "Show", "Hide")
            Category = "Lifecycle"
        }
    )

    foreach ($group in $prefixGroups) {
        foreach ($prefix in $group.Prefixes) {
            if ($method.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                return [pscustomobject]@{
                    Verb = $prefix
                    Category = $group.Category
                    IsConformant = $true
                }
            }
        }
    }

    $verb = $method
    if ($method -cmatch "^([A-Z][a-z0-9]*)") {
        $verb = $Matches[1]
    }
    return [pscustomobject]@{
        Verb = $verb
        Category = "Unclassified"
        IsConformant = $false
    }
}

function Resolve-AliasPath([string]$expr, [hashtable]$aliases) {
    if ([string]::IsNullOrEmpty($expr)) {
        return $null
    }
    if ($expr -like "addon*") {
        return $expr
    }

    $parts = $expr -split "\."
    if ($parts.Count -eq 0) {
        return $null
    }

    $root = $parts[0]
    if (-not $aliases.ContainsKey($root)) {
        return $null
    }

    $resolved = $aliases[$root]
    if ($parts.Count -gt 1) {
        $suffix = ($parts[1..($parts.Count - 1)] -join ".")
        $resolved = "$resolved.$suffix"
    }
    return $resolved
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

$records = New-Object System.Collections.Generic.List[object]

foreach ($fullFile in ($luaFiles | Sort-Object -Unique)) {
    $repoPath = Normalize-Path $fullFile
    if ($repoPath -match "^!KRT/Libs/") {
        continue
    }

    $layer = Get-Layer $repoPath
    $aliases = @{ addon = "addon" }
    $lines = Get-Content -LiteralPath $fullFile

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $lineNo = $i + 1

        if ($line -match "^\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*" +
            "([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\s*$") {
            $aliasName = $Matches[1]
            $aliasExpr = $Matches[2]
            $resolved = Resolve-AliasPath $aliasExpr $aliases
            if ($resolved -and $resolved -like "addon*") {
                $aliases[$aliasName] = $resolved
            }
        }

        if ($line -match "^\s*function\s+" +
            "([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\s*" +
            "([:\.])\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(") {
            $targetExpr = $Matches[1]
            $separator = $Matches[2]
            $method = $Matches[3]
            $target = Resolve-AliasPath $targetExpr $aliases
            if ($target -and $target -like "addon*") {
                $style = Get-NameStyle $method
                $scope = Get-ApiScope $target $method
                $taxonomy = Get-TaxonomyInfo $scope $style $method
                $records.Add([pscustomobject]@{
                    ApiPath = "$target$separator$method"
                    Target = $target
                    Method = $method
                    Separator = $separator
                    MethodStyle = $style
                    ApiScope = $scope
                    Verb = $taxonomy.Verb
                    TaxonomyCategory = $taxonomy.Category
                    IsCaseConformant = ($style -eq "PascalCase" -or $style -eq "UPPER")
                    IsTaxonomyConformant = $taxonomy.IsConformant
                    IsUnderscoreMethod = ($method -match "^_")
                    Layer = $layer
                    File = $repoPath
                    Line = $lineNo
                })
            }
        }

        if ($line -match "^\s*([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+)\s*" +
            "=\s*function\s*\(") {
            $lhs = $Matches[1]
            $parts = $lhs -split "\."
            if ($parts.Count -gt 1) {
                $method = $parts[-1]
                $targetExpr = ($parts[0..($parts.Count - 2)] -join ".")
                $target = Resolve-AliasPath $targetExpr $aliases
                if ($target -and $target -like "addon*") {
                    $style = Get-NameStyle $method
                    $scope = Get-ApiScope $target $method
                    $taxonomy = Get-TaxonomyInfo $scope $style $method
                    $records.Add([pscustomobject]@{
                        ApiPath = "$target.$method"
                        Target = $target
                        Method = $method
                        Separator = "."
                        MethodStyle = $style
                        ApiScope = $scope
                        Verb = $taxonomy.Verb
                        TaxonomyCategory = $taxonomy.Category
                        IsCaseConformant = ($style -eq "PascalCase" -or $style -eq "UPPER")
                        IsTaxonomyConformant = $taxonomy.IsConformant
                        IsUnderscoreMethod = ($method -match "^_")
                        Layer = $layer
                        File = $repoPath
                        Line = $lineNo
                    })
                }
            }
        }
    }
}

$grouped = $records | Group-Object ApiPath | Sort-Object Name
$apis = New-Object System.Collections.Generic.List[object]

foreach ($group in $grouped) {
    $first = $group.Group | Sort-Object File, Line | Select-Object -First 1
    $apis.Add([pscustomobject]@{
        ApiPath = $group.Name
        Target = $first.Target
        Method = $first.Method
        Separator = $first.Separator
        MethodStyle = $first.MethodStyle
        ApiScope = $first.ApiScope
        Verb = $first.Verb
        TaxonomyCategory = $first.TaxonomyCategory
        IsCaseConformant = $first.IsCaseConformant
        IsTaxonomyConformant = $first.IsTaxonomyConformant
        IsUnderscoreMethod = $first.IsUnderscoreMethod
        DefinitionCount = $group.Count
        Layer = $first.Layer
        File = $first.File
        Line = $first.Line
    })
}

$totalApis = ($apis | Measure-Object).Count
$totalDefs = ($records | Measure-Object).Count
$namespaceCount = (($apis | Group-Object Target) | Measure-Object).Count
$fileCount = (($records | Group-Object File) | Measure-Object).Count
$publicApis = @($apis | Where-Object { $_.ApiScope -eq "Public" })
$internalApis = @($apis | Where-Object { $_.ApiScope -eq "Internal" })
$publicCount = $publicApis.Count
$internalCount = $internalApis.Count

$styleRowsAll = $apis |
    Group-Object MethodStyle |
    Sort-Object Count -Descending |
    ForEach-Object {
        $pct = if ($totalApis -gt 0) {
            [Math]::Round(100.0 * $_.Count / [double]$totalApis, 2)
        } else {
            0
        }
        [pscustomobject]@{
            MethodStyle = $_.Name
            Count = $_.Count
            Percent = $pct
        }
    }

$styleRowsPublic = $publicApis |
    Group-Object MethodStyle |
    Sort-Object Count -Descending |
    ForEach-Object {
        $pct = if ($publicCount -gt 0) {
            [Math]::Round(100.0 * $_.Count / [double]$publicCount, 2)
        } else {
            0
        }
        [pscustomobject]@{
            MethodStyle = $_.Name
            Count = $_.Count
            Percent = $pct
        }
    }

$taxonomyRows = $publicApis |
    Group-Object TaxonomyCategory |
    Sort-Object Count -Descending |
    ForEach-Object {
        $pct = if ($publicCount -gt 0) {
            [Math]::Round(100.0 * $_.Count / [double]$publicCount, 2)
        } else {
            0
        }
        [pscustomobject]@{
            Category = $_.Name
            Count = $_.Count
            Percent = $pct
        }
    }

$topTargets = $publicApis |
    Group-Object Target |
    Sort-Object Count -Descending |
    Select-Object -First 25 |
    ForEach-Object { [pscustomobject]@{ Target = $_.Name; Count = $_.Count } }

$upperMethods = $publicApis |
    Where-Object { $_.MethodStyle -eq "UPPER" } |
    Sort-Object ApiPath |
    Select-Object ApiPath, File, Line

$nonConformantPublic = $publicApis |
    Where-Object { -not $_.IsCaseConformant -or -not $_.IsTaxonomyConformant } |
    Sort-Object ApiPath |
    Select-Object ApiPath, MethodStyle, Verb, TaxonomyCategory, IsCaseConformant,
        IsTaxonomyConformant, File, Line
$nonConformantPublicPreview = @($nonConformantPublic | Select-Object -First 80)

$csvOut = Resolve-OutputPath $OutputCsv
$publicCsvOut = Resolve-OutputPath $OutputPublicCsv
$internalCsvOut = Resolve-OutputPath $OutputInternalCsv
$mdOut = Resolve-OutputPath $OutputMd

foreach ($outPath in @($csvOut, $publicCsvOut, $internalCsvOut, $mdOut)) {
    $parent = Split-Path -Path $outPath -Parent
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -Path $parent -ItemType Directory | Out-Null
    }
}

$apis |
    Sort-Object ApiPath |
    Select-Object ApiPath, ApiScope, Target, Method, Separator, MethodStyle, Verb,
        TaxonomyCategory, IsCaseConformant, IsTaxonomyConformant, IsUnderscoreMethod,
        DefinitionCount, Layer, File, Line |
    Export-Csv -Path $csvOut -NoTypeInformation -Encoding UTF8

$publicApis |
    Sort-Object ApiPath |
    Select-Object ApiPath, ApiScope, Target, Method, Separator, MethodStyle, Verb,
        TaxonomyCategory, IsCaseConformant, IsTaxonomyConformant, DefinitionCount,
        Layer, File, Line |
    Export-Csv -Path $publicCsvOut -NoTypeInformation -Encoding UTF8

$internalApis |
    Sort-Object ApiPath |
    Select-Object ApiPath, ApiScope, Target, Method, Separator, MethodStyle, Verb,
        TaxonomyCategory, IsCaseConformant, IsTaxonomyConformant, DefinitionCount,
        Layer, File, Line |
    Export-Csv -Path $internalCsvOut -NoTypeInformation -Encoding UTF8

$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
$md = New-Object System.Collections.Generic.List[string]

$md.Add("# API Nomenclature Census")
$md.Add("")
$md.Add(('Generated by `tools/fnmap-api-census.ps1` on {0}.' -f $generatedAt))
$md.Add("")
$md.Add("## Snapshot")
$md.Add("")
$md.Add("| Metric | Value |")
$md.Add("| --- | ---: |")
$md.Add("| Scanned Lua files | $fileCount |")
$md.Add("| API method definitions | $totalDefs |")
$md.Add("| Unique API surface | $totalApis |")
$md.Add("| Public API surface | $publicCount |")
$md.Add("| Internal API surface | $internalCount |")
$md.Add(('| Namespaces (`Target`) | {0} |' -f $namespaceCount))
$md.Add("")
$md.Add("## Method Naming Distribution (All APIs)")
$md.Add("")
$md.Add("| Style | Count | Percent |")
$md.Add("| --- | ---: | ---: |")
foreach ($row in $styleRowsAll) {
    $md.Add("| $($row.MethodStyle) | $($row.Count) | $($row.Percent)% |")
}
$md.Add("")
$md.Add("## Method Naming Distribution (Public APIs)")
$md.Add("")
$md.Add("| Style | Count | Percent |")
$md.Add("| --- | ---: | ---: |")
foreach ($row in $styleRowsPublic) {
    $md.Add("| $($row.MethodStyle) | $($row.Count) | $($row.Percent)% |")
}
$md.Add("")
$md.Add("## Public API Verb Taxonomy")
$md.Add("")
$md.Add("| Category | Count | Percent |")
$md.Add("| --- | ---: | ---: |")
foreach ($row in $taxonomyRows) {
    $md.Add("| $($row.Category) | $($row.Count) | $($row.Percent)% |")
}
$md.Add("")
$md.Add("## Top Namespaces By Public API Count")
$md.Add("")
$md.Add("| Namespace | API count |")
$md.Add("| --- | ---: |")
foreach ($row in $topTargets) {
    $md.Add("| $($row.Target) | $($row.Count) |")
}
$md.Add("")
$md.Add("## Non-Conformant Public Methods")
$md.Add("")
if (($nonConformantPublic | Measure-Object).Count -eq 0) {
    $md.Add("No non-conformant methods found.")
} else {
    $md.Add(
        "Showing first $($nonConformantPublicPreview.Count) of " +
        "$($nonConformantPublic.Count) non-conformant public methods. " +
        "See `docs/API_REGISTRY_PUBLIC.csv` for the full list."
    )
    $md.Add("")
    $md.Add("| API | Style | Verb | Taxonomy | Case OK | Taxonomy OK | File | Line |")
    $md.Add("| --- | --- | --- | --- | --- | --- | --- | ---: |")
    foreach ($row in $nonConformantPublicPreview) {
        $md.Add(
            "| $($row.ApiPath) | $($row.MethodStyle) | $($row.Verb) | $($row.TaxonomyCategory) | " +
            "$($row.IsCaseConformant) | $($row.IsTaxonomyConformant) | $($row.File) | $($row.Line) |"
        )
    }
}
$md.Add("")
$md.Add("## UPPER Methods (Event-Style)")
$md.Add("")
if (($upperMethods | Measure-Object).Count -eq 0) {
    $md.Add("No UPPER event-style methods found.")
} else {
    $md.Add("| API | File | Line |")
    $md.Add("| --- | --- | ---: |")
    foreach ($row in $upperMethods) {
        $md.Add("| $($row.ApiPath) | $($row.File) | $($row.Line) |")
    }
}
$md.Add("")
$md.Add("## Extraction Rules")
$md.Add("")
$md.Add('- Includes method definitions on `addon.*` tables.')
$md.Add('- Resolves local aliases when assigned directly from `addon.*` paths.')
$md.Add('- Captures both `function X:Y()` and `X.Y = function()` forms.')
$md.Add('- Excludes vendored libraries under `!KRT/Libs`.')
$md.Add('- Classifies public vs internal APIs using method underscore prefix and `._ui` targets.')
$md.Add('- Applies a public-API verb taxonomy for readability tracking.')

Set-Content -Path $mdOut -Value $md -Encoding UTF8

Write-Host ("API census complete. Unique API surface={0}" -f $totalApis) -ForegroundColor Green
Write-Host ("CSV: {0}" -f (Normalize-Path $csvOut))
Write-Host ("CSV: {0}" -f (Normalize-Path $publicCsvOut))
Write-Host ("CSV: {0}" -f (Normalize-Path $internalCsvOut))
Write-Host ("MD : {0}" -f (Normalize-Path $mdOut))
