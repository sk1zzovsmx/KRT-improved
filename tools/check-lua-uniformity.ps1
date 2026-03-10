Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$violations = New-Object System.Collections.Generic.List[string]

function To-RepoRelativePath {
    param([string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetFullPath($repoRoot.Path)
    if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($root.Length).TrimStart('\', '/')
    }

    return $Path
}

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

    return @($all)
}

Write-Host "Check 1/4: luacheck on KRT-owned Lua..."
$luacheckCmd = Get-Command luacheck -ErrorAction SilentlyContinue
if (-not $luacheckCmd) {
    Add-SectionHeader "[luacheck]"
    Add-SectionLine "luacheck not found in PATH."
} else {
    $lintOutput = & $luacheckCmd.Source --codes --no-color !KRT tools 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-SectionHeader "[luacheck]"
        Add-SectionLine "luacheck --codes --no-color !KRT tools failed."
        foreach ($line in @($lintOutput)) {
            Add-SectionLine $line
        }
    }
}

Write-Host "Check 2/4: canonical section headers in feature modules..."
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
        $rel = To-RepoRelativePath -Path $file.FullName
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

Write-Host "Check 3/4: no tab-indent and no trailing whitespace..."
$formatProblems = New-Object System.Collections.Generic.List[string]
$codeFiles = Get-KrtOwnedLuaFiles
foreach ($file in $codeFiles) {
    $lines = Get-Content -LiteralPath $file.FullName
    for ($i = 0; $i -lt $lines.Count; $i = $i + 1) {
        $lineNumber = $i + 1
        $line = $lines[$i]
        if ($line -match "^\t+") {
            $formatProblems.Add(
                ("{0}:{1}: tab-indented line" -f (To-RepoRelativePath -Path $file.FullName), $lineNumber)
            )
        }
        if ($line -match "[ \t]+$") {
            $formatProblems.Add(
                ("{0}:{1}: trailing whitespace" -f (To-RepoRelativePath -Path $file.FullName), $lineNumber)
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

Write-Host "Check 4/4: git EOL state (no w/crlf outside !KRT/Libs)..."
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

if ($violations.Count -gt 0) {
    Write-Host "Lua uniformity checks failed." -ForegroundColor Red
    foreach ($line in $violations) {
        Write-Host $line
    }
    exit 1
}

Write-Host "Lua uniformity checks passed." -ForegroundColor Green
Write-Host "Confirmed:"
Write-Host "  1) luacheck passes for !KRT and tools"
Write-Host "  2) Canonical section headers are present and ordered"
Write-Host "  3) No tab-indented lines and no trailing whitespace"
Write-Host "  4) No w/crlf on tracked .lua files outside !KRT/Libs"
