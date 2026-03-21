param(
    [switch]$AllFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Normalize-Path([string]$fullPath) {
    $full = [System.IO.Path]::GetFullPath($fullPath)
    $root = [System.IO.Path]::GetFullPath($repoRoot.Path)
    if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($root.Length).TrimStart("\", "/") -replace "\\", "/"
    }
    return ($fullPath -replace "\\", "/")
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

function Test-PublicTaxonomy([string]$style, [string]$method) {
    if ($style -eq "UPPER") {
        return $true
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
        return $true
    }

    $prefixes = @(
        "Get",
        "Find",
        "Is",
        "Can",
        "Set",
        "Add",
        "Remove",
        "Delete",
        "Upsert",
        "Ensure",
        "Bind",
        "Localize",
        "Request",
        "RequestRefresh",
        "Refresh",
        "Toggle",
        "Show",
        "Hide"
    )

    foreach ($prefix in $prefixes) {
        if ($method.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
            return $true
        }
    }
    return $false
}

function Get-StagedAddedLines {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git not found in PATH."
    }

    $diffOutput = & git diff --cached --unified=0 --diff-filter=ACMR -- "*.lua" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --cached --unified=0 --diff-filter=ACMR -- '*.lua' failed."
    }

    $filesToLines = @{}
    $currentPath = $null
    $newLine = 0

    foreach ($lineObj in @($diffOutput)) {
        $line = [string]$lineObj

        if ($line -match "^\+\+\+\s+b/(.+)$") {
            $currentPath = ($Matches[1] -replace "\\", "/")
            if (-not $filesToLines.ContainsKey($currentPath)) {
                $filesToLines[$currentPath] = New-Object System.Collections.Generic.HashSet[int]
            }
            continue
        }

        if ($line -match "^@@\s+-[0-9,]+\s+\+([0-9]+)(?:,([0-9]+))?\s+@@") {
            $newLine = [int]$Matches[1]
            continue
        }

        if (-not $currentPath) {
            continue
        }

        if ($line.StartsWith("+") -and -not $line.StartsWith("+++")) {
            [void]$filesToLines[$currentPath].Add($newLine)
            $newLine = $newLine + 1
            continue
        }

        if ($line.StartsWith("-") -and -not $line.StartsWith("---")) {
            continue
        }

        if ($line.StartsWith(" ")) {
            $newLine = $newLine + 1
        }
    }

    return $filesToLines
}

function Get-ApiDefinitionsFromFile([string]$repoPath) {
    $fullPath = Join-Path $repoRoot ($repoPath -replace "/", "\")
    if (-not (Test-Path -LiteralPath $fullPath)) {
        return @()
    }

    $aliases = @{ addon = "addon" }
    $lines = Get-Content -LiteralPath $fullPath
    $records = New-Object System.Collections.Generic.List[object]

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
                $records.Add([pscustomobject]@{
                    ApiPath = "$target$separator$method"
                    Target = $target
                    Method = $method
                    Style = $style
                    Scope = $scope
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
                    $records.Add([pscustomobject]@{
                        ApiPath = "$target.$method"
                        Target = $target
                        Method = $method
                        Style = $style
                        Scope = $scope
                        File = $repoPath
                        Line = $lineNo
                    })
                }
            }
        }
    }

    return $records.ToArray()
}

if ($AllFiles) {
    $stagedAddedLines = @{}
    $luaFiles = Get-ChildItem -Path "!KRT" -Recurse -File -Filter "*.lua" |
        Where-Object { $_.FullName -notmatch [regex]::Escape("\!KRT\Libs\") } |
        ForEach-Object { Normalize-Path $_.FullName }
    $targetFiles = @($luaFiles | Sort-Object -Unique)
    Write-Host "Checking API nomenclature on all addon Lua files..."
} else {
    $stagedAddedLines = Get-StagedAddedLines
    $targetFiles = @($stagedAddedLines.Keys | Sort-Object)
    if ($targetFiles.Count -eq 0) {
        Write-Host "Skipping API nomenclature check (no staged Lua additions)."
        exit 0
    }
    Write-Host "Checking API nomenclature on staged Lua additions..."
}

$violations = New-Object System.Collections.Generic.List[string]

foreach ($repoPath in $targetFiles) {
    if ($repoPath -match "^!KRT/Libs/") {
        continue
    }

    $apis = Get-ApiDefinitionsFromFile $repoPath
    foreach ($api in $apis) {
        if ($api.Scope -ne "Public") {
            continue
        }

        if (-not $AllFiles) {
            if (-not $stagedAddedLines.ContainsKey($repoPath)) {
                continue
            }
            if (-not $stagedAddedLines[$repoPath].Contains([int]$api.Line)) {
                continue
            }
        }

        $caseOk = ($api.Style -eq "PascalCase" -or $api.Style -eq "UPPER")
        $taxonomyOk = Test-PublicTaxonomy $api.Style $api.Method

        if (-not $caseOk -or -not $taxonomyOk) {
            $reasons = New-Object System.Collections.Generic.List[string]
            if (-not $caseOk) {
                $reasons.Add("case")
            }
            if (-not $taxonomyOk) {
                $reasons.Add("taxonomy")
            }
            $violations.Add(
                ("{0}:{1}: {2} [{3}] ({4})" -f
                    $api.File, $api.Line, $api.ApiPath, $api.Method, ($reasons -join ", "))
            )
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host "API nomenclature check failed." -ForegroundColor Red
    Write-Host "Public API methods must be PascalCase/UPPER and match verb taxonomy."
    Write-Host "Allowed verbs: Get, Find, Is, Can, Set, Add, Remove, Delete, Upsert,"
    Write-Host "Ensure, Bind, Localize, Request, RequestRefresh, Refresh, Toggle, Show, Hide."
    Write-Host "Allowed exact lifecycle names: OnLoad, OnLoadFrame, AcquireRefs,"
    Write-Host "BindHandlers, RefreshUI, Refresh, RequestRefresh, Toggle, Show, Hide."
    foreach ($violation in $violations) {
        Write-Host ("  - {0}" -f $violation)
    }
    exit 1
}

Write-Host "API nomenclature check passed." -ForegroundColor Green
if (-not $AllFiles) {
    Write-Host "Checked staged API additions only."
}
