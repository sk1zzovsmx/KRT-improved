Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

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

$binderPath = Join-Path $repoRoot "!KRT/Modules/UI/Binder"
if (Test-Path -LiteralPath $binderPath) {
    $binderFiles = @(Get-ChildItem -LiteralPath $binderPath -Recurse -File)
    if ($binderFiles.Count -gt 0) {
        $violations.Add("[Binder files present]")
        foreach ($file in $binderFiles) {
            $violations.Add("  $(To-RepoRelativePath -Path $file.FullName)")
        }
    }
}

$tocPath = Join-Path $repoRoot "!KRT/!KRT.toc"
if (Test-Path -LiteralPath $tocPath) {
    $tocMatches = @(Select-String -Path $tocPath -Pattern 'Modules\\UI\\Binder')
    if ($tocMatches.Count -gt 0) {
        $violations.Add("[TOC includes Binder]")
        foreach ($m in $tocMatches) {
            $violations.Add("  !KRT/!KRT.toc:$($m.LineNumber):$($m.Line.TrimEnd())")
        }
    }
}

$xmlTargets = New-Object System.Collections.Generic.List[string]
$xmlTargets.Add((Join-Path $repoRoot "!KRT/UI"))
$xmlTargets.Add((Join-Path $repoRoot "!KRT/Templates.xml"))

$xmlPattern = '<Scripts>|<On[A-Za-z]+>'
$xmlHeaderAdded = $false
foreach ($target in $xmlTargets) {
    if (-not (Test-Path -LiteralPath $target)) {
        continue
    }

    $item = Get-Item -LiteralPath $target
    if ($item.PSIsContainer) {
        $files = @(Get-ChildItem -LiteralPath $target -Recurse -File -Filter "*.xml")
    } else {
        $files = @($item)
    }

    foreach ($file in $files) {
        $matches = @(Select-String -Path $file.FullName -Pattern $xmlPattern)
        if ($matches.Count -eq 0) {
            continue
        }

        if (-not $xmlHeaderAdded) {
            $violations.Add("[XML inline scripts]")
            $xmlHeaderAdded = $true
        }
        $relative = To-RepoRelativePath -Path $file.FullName
        foreach ($m in $matches) {
            $violations.Add("  ${relative}:$($m.LineNumber):$($m.Line.TrimEnd())")
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host "UI binding checks failed." -ForegroundColor Red
    foreach ($line in $violations) {
        Write-Host $line
    }
    exit 1
}

Write-Host "UI binding checks passed." -ForegroundColor Green
Write-Host "Checked:"
Write-Host "  Binder files absent under !KRT/Modules/UI/Binder"
Write-Host "  !KRT/!KRT.toc has no Modules\\UI\\Binder entries"
Write-Host "  No <Scripts> / <On...> in !KRT/UI/*.xml and !KRT/Templates.xml"
