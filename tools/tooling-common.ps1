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

function Get-KrtGlobFromArgs {
    param([string[]]$ExtraArgs = @())

    for ($i = 0; $i -lt $ExtraArgs.Count; $i = $i + 1) {
        if (($ExtraArgs[$i] -eq "--glob" -or $ExtraArgs[$i] -eq "-g") -and ($i + 1) -lt $ExtraArgs.Count) {
            return $ExtraArgs[$i + 1]
        }
    }

    return "*"
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

        $result = & $rgCmd.Source @args 2>&1
        if ($LASTEXITCODE -eq 0) {
            return @($result)
        }
        if ($LASTEXITCODE -eq 1) {
            return @()
        }

        $errorText = ($result -join [Environment]::NewLine)
        throw "rg failed for pattern '$Pattern' in '$Path': $errorText"
    }

    $glob = Get-KrtGlobFromArgs -ExtraArgs $ExtraArgs
    $files = @(Get-KrtPathFiles -Path $Path -Glob $glob)
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
