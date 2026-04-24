function Get-KrtRepoRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptRoot
    )

    $current = Resolve-Path -LiteralPath $ScriptRoot
    while ($true) {
        $tocPath = Join-Path $current.Path "!KRT/!KRT.toc"
        if (Test-Path -LiteralPath $tocPath -PathType Leaf) {
            return $current
        }

        $parentPath = Split-Path -Path $current.Path -Parent
        if ([string]::IsNullOrWhiteSpace($parentPath) -or $parentPath -eq $current.Path) {
            throw "Unable to resolve KRT repo root from '$ScriptRoot'."
        }

        $current = Resolve-Path -LiteralPath $parentPath
    }
}

function Enter-KrtRepoRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptRoot
    )

    $repoRoot = Get-KrtRepoRoot -ScriptRoot $ScriptRoot
    Set-Location $repoRoot
    return $repoRoot
}

function Resolve-KrtInputPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [object]$BasePath = $null,
        [switch]$AllowMissing
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Path cannot be empty."
    }

    $base = if ($BasePath -is [System.Management.Automation.PathInfo]) {
        $BasePath.Path
    } elseif ($BasePath) {
        [string]$BasePath
    } else {
        (Get-Location).Path
    }

    $candidate = if ([System.IO.Path]::IsPathRooted($Path)) {
        [System.IO.Path]::GetFullPath($Path)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $base $Path))
    }

    if ($AllowMissing) {
        return $candidate
    }

    return Resolve-Path -LiteralPath $candidate
}

function Resolve-KrtLuaRuntime {
    param(
        [string]$Preferred = ""
    )

    if ($Preferred -and $Preferred.Trim() -ne "") {
        $command = Get-Command $Preferred -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Source
        }
        throw "Requested runtime '$Preferred' not found in PATH."
    }

    foreach ($name in @("lua", "luajit")) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Source
        }
    }

    return $null
}

function Disable-KrtNativeCommandErrors {
    if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
        Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false -Scope 1
    }
}

function ConvertTo-KrtRepoRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [object]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$UseForwardSlashes
    )

    $full = [System.IO.Path]::GetFullPath($Path)
    $rootPath = if ($RepoRoot -is [System.Management.Automation.PathInfo]) {
        [System.IO.Path]::GetFullPath($RepoRoot.Path)
    } else {
        [System.IO.Path]::GetFullPath([string]$RepoRoot)
    }

    if ($full.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $full.Substring($rootPath.Length).TrimStart("\", "/")
        if ($UseForwardSlashes) {
            return ($relative -replace "\\", "/")
        }
        return $relative
    }

    if ($UseForwardSlashes) {
        return ($Path -replace "\\", "/")
    }
    return $Path
}

function Write-KrtRgFallbackWarning {
    param(
        [string]$Reason = ""
    )

    $alreadyWarned = $false
    if (Get-Variable -Name KrtRgFallbackWarned -Scope Script -ErrorAction SilentlyContinue) {
        $alreadyWarned = ($script:KrtRgFallbackWarned -eq $true)
    }

    if (-not $alreadyWarned) {
        $cleanReason = ""
        if ($Reason -and $Reason.Trim() -ne "") {
            $cleanReason = (($Reason -split "(`r`n|`n|`r)")[0]).Trim()
        }

        if ($cleanReason -ne "") {
            Write-Host ("rg unavailable; falling back to Select-String. Reason: {0}" -f $cleanReason) -ForegroundColor Yellow
        } else {
            Write-Host "rg unavailable; falling back to Select-String." -ForegroundColor Yellow
        }
        Set-Variable -Name KrtRgFallbackWarned -Scope Script -Value $true
    }
}

function Get-KrtGlobFilters {
    param([string[]]$ExtraArgs = @())

    $includes = New-Object System.Collections.Generic.List[string]
    $excludes = New-Object System.Collections.Generic.List[string]

    for ($i = 0; $i -lt $ExtraArgs.Count; $i = $i + 1) {
        $arg = [string]$ExtraArgs[$i]
        if (($arg -eq "--glob" -or $arg -eq "-g") -and ($i + 1) -lt $ExtraArgs.Count) {
            $glob = [string]$ExtraArgs[$i + 1]
            $i = $i + 1
            if ([string]::IsNullOrWhiteSpace($glob)) {
                continue
            }
            if ($glob.StartsWith("!")) {
                $excludes.Add($glob.Substring(1))
            } else {
                $includes.Add($glob)
            }
        }
    }

    if ($includes.Count -eq 0) {
        $includes.Add("*")
    }

    return [PSCustomObject]@{
        Includes = @($includes)
        Excludes = @($excludes)
    }
}

function Get-KrtPathFiles {
    param(
        [string]$Path,
        [string]$Glob = "*"
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    $item = Get-Item -LiteralPath $Path
    if (-not $item.PSIsContainer) {
        return @($item)
    }

    return @(Get-ChildItem -LiteralPath $Path -Recurse -File -Filter $Glob)
}

function ConvertTo-KrtSearchRelativePath {
    param(
        [string]$RootPath,
        [string]$FilePath
    )

    $fullPath = [System.IO.Path]::GetFullPath($FilePath)
    if (-not [string]::IsNullOrWhiteSpace($RootPath)) {
        $root = [System.IO.Path]::GetFullPath($RootPath)
        if ($fullPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relative = $fullPath.Substring($root.Length).TrimStart("\", "/")
            return ($relative -replace "\\", "/")
        }
    }

    return (Split-Path -Path $fullPath -Leaf)
}

function Write-KrtUtf8NoBom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$Value
    )

    $parent = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -Path $parent -ItemType Directory | Out-Null
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    $content = [string]::Join([Environment]::NewLine, $Value)
    if ($Value.Count -gt 0) {
        $content = $content + [Environment]::NewLine
    }

    [System.IO.File]::WriteAllText($Path, $content, $encoding)
}

function Export-KrtCsvUtf8NoBom {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$InputObject,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    begin {
        $rows = New-Object System.Collections.Generic.List[object]
    }

    process {
        $rows.Add($InputObject)
    }

    end {
        $csv = @($rows | ConvertTo-Csv -NoTypeInformation)
        Write-KrtUtf8NoBom -Path $Path -Value $csv
    }
}

function Get-KrtGlobVariants {
    param([string]$Glob)

    if ([string]::IsNullOrWhiteSpace($Glob)) {
        return @()
    }

    $normalized = ($Glob -replace "\\", "/").Trim()
    if ($normalized -eq "") {
        return @()
    }

    $variants = New-Object System.Collections.Generic.List[string]
    $variants.Add($normalized)

    if ($normalized.StartsWith("**/")) {
        $variants.Add($normalized.Substring(3))
    }
    if ($normalized.StartsWith("./")) {
        $variants.Add($normalized.Substring(2))
    }

    return @($variants | Select-Object -Unique)
}

function Test-KrtPathMatchesGlob {
    param(
        [string]$RelativePath,
        [string]$LeafName,
        [string]$Glob
    )

    $variants = Get-KrtGlobVariants -Glob $Glob
    foreach ($variant in $variants) {
        $matcher = [System.Management.Automation.WildcardPattern]::new(
            $variant,
            [System.Management.Automation.WildcardOptions]::IgnoreCase
        )

        if ($matcher.IsMatch($RelativePath)) {
            return $true
        }

        $hasSeparator = $variant.Contains("/") -or $variant.Contains("\")
        if (-not $hasSeparator -and $matcher.IsMatch($LeafName)) {
            return $true
        }
    }

    return $false
}

function Test-KrtPathAllowedByGlobFilters {
    param(
        [string]$RelativePath,
        [string]$LeafName,
        [PSObject]$Filters
    )

    $isIncluded = $false
    foreach ($glob in @($Filters.Includes)) {
        if (Test-KrtPathMatchesGlob -RelativePath $RelativePath -LeafName $LeafName -Glob $glob) {
            $isIncluded = $true
            break
        }
    }
    if (-not $isIncluded) {
        return $false
    }

    foreach ($glob in @($Filters.Excludes)) {
        if (Test-KrtPathMatchesGlob -RelativePath $RelativePath -LeafName $LeafName -Glob $glob) {
            return $false
        }
    }

    return $true
}

function Get-KrtFilteredPathFiles {
    param(
        [string]$Path,
        [string[]]$ExtraArgs = @()
    )

    $files = @(Get-KrtPathFiles -Path $Path -Glob "*")
    if ($files.Count -eq 0) {
        return @()
    }

    $filters = Get-KrtGlobFilters -ExtraArgs $ExtraArgs
    $item = Get-Item -LiteralPath $Path
    $rootPath = if ($item.PSIsContainer) {
        $item.FullName
    } else {
        Split-Path -Path $item.FullName -Parent
    }

    $out = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    foreach ($file in $files) {
        $relativePath = ConvertTo-KrtSearchRelativePath -RootPath $rootPath -FilePath $file.FullName
        $leafName = Split-Path -Path $file.FullName -Leaf
        if (Test-KrtPathAllowedByGlobFilters -RelativePath $relativePath -LeafName $leafName -Filters $filters) {
            [void]$out.Add($file)
        }
    }

    return @($out)
}

function Get-KrtPatternMatches {
    param(
        [Parameter(Mandatory = $true)]
        [object]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string]$Pattern,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string[]]$ExtraArgs = @()
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    $rgCmd = Get-Command rg -ErrorAction SilentlyContinue
    if ($rgCmd) {
        $args = @("--line-number", "--no-heading", "--color", "never")
        $args += $ExtraArgs
        $args += @($Pattern, $Path)

        $rgResult = $null
        $rgExitCode = $null
        $rgUnavailable = $false
        $rgFailureReason = ""

        try {
            $rgResult = & $rgCmd.Source @args 2>&1
            $rgExitCode = $LASTEXITCODE
        } catch {
            $rgUnavailable = $true
            $rgFailureReason = $_.Exception.Message
        }

        if (-not $rgUnavailable) {
            if ($rgExitCode -eq 0) {
                return @($rgResult)
            }
            if ($rgExitCode -eq 1) {
                return @()
            }

            $errorText = ($rgResult -join [Environment]::NewLine)
            if ($errorText -match "(?i)access.*denied|permission denied|accesso negato") {
                $rgUnavailable = $true
                $rgFailureReason = $errorText
            } else {
                throw "rg failed for pattern '$Pattern' in '$Path': $errorText"
            }
        }

        if ($rgUnavailable) {
            Write-KrtRgFallbackWarning -Reason $rgFailureReason
        }
    }

    $files = @(Get-KrtFilteredPathFiles -Path $Path -ExtraArgs $ExtraArgs)
    if ($files.Count -eq 0) {
        return @()
    }

    $matches = New-Object System.Collections.Generic.List[string]
    foreach ($file in $files) {
        $result = Select-String -Path $file.FullName -Pattern $Pattern -AllMatches
        foreach ($match in $result) {
            $relative = ConvertTo-KrtRepoRelativePath -RepoRoot $RepoRoot -Path $match.Path -UseForwardSlashes
            $matches.Add(("{0}:{1}:{2}" -f $relative, $match.LineNumber, $match.Line.TrimEnd()))
        }
    }

    return @($matches)
}
