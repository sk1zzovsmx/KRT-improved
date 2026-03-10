Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$toolingCommonPath = Join-Path $PSScriptRoot "tooling-common.ps1"
if (-not (Test-Path -LiteralPath $toolingCommonPath)) {
    $toolingCommonPath = Join-Path (Split-Path -Parent $PSScriptRoot) "tooling-common.ps1"
}
. $toolingCommonPath
$repoRoot = Enter-KrtRepoRoot -ScriptRoot $PSScriptRoot
Disable-KrtNativeCommandErrors

$violations = New-Object System.Collections.Generic.List[string]

function Add-SectionHeader {
    param([string]$Header)
    $violations.Add($Header)
}

function Add-SectionLine {
    param([string]$Line)
    $violations.Add("  $Line")
}

function Get-KrtOwnedLuaFiles {
    $all = New-Object System.Collections.Generic.List[System.IO.FileInfo]

    $krtRoot = Join-Path $repoRoot "!KRT"
    if (Test-Path -LiteralPath $krtRoot) {
        $krtFiles = Get-ChildItem -LiteralPath $krtRoot -Recurse -File -Filter "*.lua"
        foreach ($f in $krtFiles) {
            if ($f.FullName -match [regex]::Escape("\!KRT\Libs\")) {
                continue
            }
            $all.Add($f)
        }
    }

    $toolsRoot = Join-Path $repoRoot "tools"
    if (Test-Path -LiteralPath $toolsRoot) {
        $toolFiles = Get-ChildItem -LiteralPath $toolsRoot -Recurse -File -Filter "*.lua"
        foreach ($f in $toolFiles) {
            $all.Add($f)
        }
    }

    $testsRoot = Join-Path $repoRoot "tests"
    if (Test-Path -LiteralPath $testsRoot) {
        $testFiles = Get-ChildItem -LiteralPath $testsRoot -Recurse -File -Filter "*.lua"
        foreach ($f in $testFiles) {
            $all.Add($f)
        }
    }

    return @($all)
}

function Get-KrtAddonLuaFiles {
    $all = New-Object System.Collections.Generic.List[System.IO.FileInfo]

    $krtRoot = Join-Path $repoRoot "!KRT"
    if (-not (Test-Path -LiteralPath $krtRoot)) {
        return @($all)
    }

    $krtFiles = Get-ChildItem -LiteralPath $krtRoot -Recurse -File -Filter "*.lua"
    foreach ($f in $krtFiles) {
        if ($f.FullName -match [regex]::Escape("\!KRT\Libs\")) {
            continue
        }
        $all.Add($f)
    }

    return @($all)
}

function Test-IsPascalCase {
    param([string]$Name)

    return ($Name -cmatch "^[A-Z][A-Za-z0-9]*$")
}

function Test-IsCamelCase {
    param([string]$Name)

    return ($Name -cmatch "^[a-z][A-Za-z0-9]*$")
}

function Test-IsUpperSnakeCase {
    param([string]$Name)

    return ($Name -cmatch "^[A-Z][A-Z0-9_]*$")
}

function Test-IsLuaMetamethod {
    param([string]$Name)

    return ($Name -cmatch "^__[A-Za-z0-9_]+$")
}

function Test-IsAllowedPublicFunctionName {
    param([string]$Name)

    return (Test-IsPascalCase -Name $Name) -or
        (Test-IsUpperSnakeCase -Name $Name) -or
        (Test-IsLuaMetamethod -Name $Name)
}

function Test-IsAllowedUiHookName {
    param([string]$Name)

    $allowed = @(
        "AcquireRefs",
        "BindHandlers",
        "Localize",
        "OnLoadFrame",
        "RefreshUI",
        "Refresh"
    )

    return $allowed -contains $Name
}

function Test-IsAllowedPrivateFunctionName {
    param([string]$Name)

    return (Test-IsCamelCase -Name $Name) -or
        (Test-IsAllowedUiHookName -Name $Name) -or
        (Test-IsUpperSnakeCase -Name $Name) -or
        (Test-IsLuaMetamethod -Name $Name)
}

Write-Host "Check 1/6: luacheck on KRT-owned Lua..."
$luacheckCmd = Get-Command luacheck -ErrorAction SilentlyContinue
if (-not $luacheckCmd) {
    Add-SectionHeader "[luacheck]"
    Add-SectionLine "luacheck not found in PATH."
} else {
    $lintOutput = & $luacheckCmd.Source --codes --no-color !KRT tools tests 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-SectionHeader "[luacheck]"
        Add-SectionLine "luacheck --codes --no-color !KRT tools tests failed."
        foreach ($line in @($lintOutput)) {
            Add-SectionLine $line
        }
    }
}

Write-Host "Check 2/6: canonical section headers in feature modules..."
$stateHeader = "-- ----- Internal state ----- --"
$helpersHeader = "-- ----- Private helpers ----- --"
$publicHeader = "-- ----- Public methods ----- --"
$headerTargets = @(
    "!KRT/Controllers",
    "!KRT/Services",
    "!KRT/Widgets",
    "!KRT/EntryPoints"
)

$headerFiles = New-Object System.Collections.Generic.List[System.IO.FileInfo]
foreach ($target in $headerTargets) {
    $path = Join-Path $repoRoot $target
    if (-not (Test-Path -LiteralPath $path)) {
        continue
    }
    foreach ($f in Get-ChildItem -LiteralPath $path -Recurse -File -Filter "*.lua") {
        $headerFiles.Add($f)
    }
}

$headerProblems = New-Object System.Collections.Generic.List[string]
foreach ($file in $headerFiles) {
    $lines = Get-Content -LiteralPath $file.FullName
    $stateIdx = -1
    $helpersIdx = -1
    $publicIdx = -1

    for ($i = 0; $i -lt $lines.Count; $i = $i + 1) {
        $trimmed = $lines[$i].Trim()
        if ($stateIdx -lt 0 -and $trimmed -eq $stateHeader) {
            $stateIdx = $i + 1
            continue
        }
        if ($helpersIdx -lt 0 -and $trimmed -eq $helpersHeader) {
            $helpersIdx = $i + 1
            continue
        }
        if ($publicIdx -lt 0 -and $trimmed -eq $publicHeader) {
            $publicIdx = $i + 1
            continue
        }
    }

    $hasAll = ($stateIdx -gt 0) -and ($helpersIdx -gt 0) -and ($publicIdx -gt 0)
    $isOrdered = $hasAll -and ($stateIdx -lt $helpersIdx) -and ($helpersIdx -lt $publicIdx)
    if (-not $isOrdered) {
        $rel = ConvertTo-KrtRepoRelativePath -RepoRoot $repoRoot -Path $file.FullName -UseForwardSlashes
        $headerProblems.Add(
            ("{0} (state={1}, helpers={2}, public={3})" -f $rel, $stateIdx, $helpersIdx, $publicIdx)
        )
    }
}

if ($headerProblems.Count -gt 0) {
    Add-SectionHeader "[canonical headers]"
    foreach ($line in $headerProblems) {
        Add-SectionLine $line
    }
}

Write-Host "Check 3/6: no tab-indent and no trailing whitespace..."
$formatProblems = New-Object System.Collections.Generic.List[string]
$codeFiles = Get-KrtOwnedLuaFiles
foreach ($file in $codeFiles) {
    $lines = Get-Content -LiteralPath $file.FullName
    for ($i = 0; $i -lt $lines.Count; $i = $i + 1) {
        $lineNumber = $i + 1
        $line = $lines[$i]
        if ($line -match "^\t+") {
            $formatProblems.Add(
                ("{0}:{1}: tab-indented line" -f
                    (ConvertTo-KrtRepoRelativePath -RepoRoot $repoRoot -Path $file.FullName -UseForwardSlashes),
                    $lineNumber)
            )
        }
        if ($line -match "[ \t]+$") {
            $formatProblems.Add(
                ("{0}:{1}: trailing whitespace" -f
                    (ConvertTo-KrtRepoRelativePath -RepoRoot $repoRoot -Path $file.FullName -UseForwardSlashes),
                    $lineNumber)
            )
        }
    }
}

if ($formatProblems.Count -gt 0) {
    Add-SectionHeader "[whitespace]"
    foreach ($line in $formatProblems) {
        Add-SectionLine $line
    }
}

Write-Host "Check 4/6: git EOL state (no w/crlf outside !KRT/Libs)..."
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) {
    Add-SectionHeader "[eol]"
    Add-SectionLine "git not found in PATH."
} else {
    $eolOutput = & $gitCmd.Source ls-files --eol -- "*.lua" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-SectionHeader "[eol]"
        Add-SectionLine "git ls-files --eol -- '*.lua' failed."
        foreach ($line in @($eolOutput)) {
            Add-SectionLine $line
        }
    } else {
        $eolProblems = New-Object System.Collections.Generic.List[string]
        foreach ($line in @($eolOutput)) {
            $match = [regex]::Match($line, "\t(?<path>.+)$")
            if (-not $match.Success) {
                continue
            }
            $path = ($match.Groups["path"].Value -replace "\\", "/")
            if ($path.StartsWith("!KRT/Libs/", [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            if ($line -match "\bw/crlf\b") {
                $eolProblems.Add($line)
            }
        }

        if ($eolProblems.Count -gt 0) {
            Add-SectionHeader "[eol]"
            foreach ($line in $eolProblems) {
                Add-SectionLine $line
            }
        }
    }
}

Write-Host "Check 5/6: canonical public function naming..."
$namingProblems = New-Object System.Collections.Generic.List[string]
$addonLuaFiles = Get-KrtAddonLuaFiles
foreach ($file in $addonLuaFiles) {
    $lines = Get-Content -LiteralPath $file.FullName

    for ($i = 0; $i -lt $lines.Count; $i = $i + 1) {
        $lineNumber = $i + 1
        $line = $lines[$i]

        if (-not ($line -match "^\s*function\s+([A-Za-z_][A-Za-z0-9_\.]*)(?::([A-Za-z_][A-Za-z0-9_]*))?\s*\(")) {
            continue
        }

        $prefix = $Matches[1]
        $methodName = $Matches[2]
        if ($methodName) {
            if (-not (Test-IsAllowedPublicFunctionName -Name $methodName)) {
                $namingProblems.Add(
                    ("{0}:{1}: public method '{2}' should use PascalCase or WoW event naming" -f
                        (ConvertTo-KrtRepoRelativePath -RepoRoot $repoRoot -Path $file.FullName -UseForwardSlashes),
                        $lineNumber, $methodName)
                )
            }
            continue
        }

        if ($prefix.Contains(".")) {
            $segments = $prefix -split "\."
            $name = $segments[$segments.Length - 1]
            if (-not (Test-IsAllowedPublicFunctionName -Name $name)) {
                $namingProblems.Add(
                    ("{0}:{1}: public function '{2}' should use PascalCase or WoW event naming" -f
                        (ConvertTo-KrtRepoRelativePath -RepoRoot $repoRoot -Path $file.FullName -UseForwardSlashes),
                        $lineNumber, $name)
                )
            }
            continue
        }
    }
}

if ($namingProblems.Count -gt 0) {
    Add-SectionHeader "[naming]"
    foreach ($line in $namingProblems) {
        Add-SectionLine $line
    }
}

Write-Host "Check 6/6: private helper naming..."
$privateNamingProblems = New-Object System.Collections.Generic.List[string]
$ownedLuaFiles = Get-KrtOwnedLuaFiles
foreach ($file in $ownedLuaFiles) {
    $lines = Get-Content -LiteralPath $file.FullName

    for ($i = 0; $i -lt $lines.Count; $i = $i + 1) {
        $lineNumber = $i + 1
        $line = $lines[$i]

        if ($line -match "^\s*local\s+function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(") {
            $name = $Matches[1]
            if (-not (Test-IsAllowedPrivateFunctionName -Name $name)) {
                $privateNamingProblems.Add(
                    ("{0}:{1}: private helper '{2}' should use camelCase or an allowed UI hook name" -f
                        (ConvertTo-KrtRepoRelativePath -RepoRoot $repoRoot -Path $file.FullName -UseForwardSlashes),
                        $lineNumber, $name)
                )
            }
            continue
        }

        if ($line -match "^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(") {
            $name = $Matches[1]
            if (-not (Test-IsAllowedPrivateFunctionName -Name $name)) {
                $privateNamingProblems.Add(
                    ("{0}:{1}: bare helper '{2}' should use camelCase or an allowed UI hook name" -f
                        (ConvertTo-KrtRepoRelativePath -RepoRoot $repoRoot -Path $file.FullName -UseForwardSlashes),
                        $lineNumber, $name)
                )
            }
        }
    }
}

if ($privateNamingProblems.Count -gt 0) {
    Add-SectionHeader "[private helper naming]"
    foreach ($line in $privateNamingProblems) {
        Add-SectionLine $line
    }
}

if ($violations.Count -gt 0) {
    Write-Host "Lua uniformity checks failed." -ForegroundColor Red
    foreach ($line in $violations) {
        Write-Host $line
    }
    exit 1
}

Write-Host "Lua uniformity checks passed." -ForegroundColor Green
Write-Host "Confirmed:"
Write-Host "  1) luacheck passes for !KRT, tools, and tests"
Write-Host "  2) Canonical section headers are present and ordered"
Write-Host "  3) No tab-indented lines and no trailing whitespace"
Write-Host "  4) No w/crlf on tracked .lua files outside !KRT/Libs"
Write-Host "  5) Public function naming matches canonical rules"
Write-Host "  6) Private helper naming matches canonical rules"
