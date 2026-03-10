param(
    [switch]$VerifyOnly,
    [switch]$InstallLocal,
    [string]$ManifestPath = "tools/agent-skills.manifest.json",
    [string]$LocalSkillsRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($VerifyOnly -and $InstallLocal) {
    throw "Cannot combine -VerifyOnly and -InstallLocal."
}

if ([string]::IsNullOrWhiteSpace($LocalSkillsRoot)) {
    if (-not [string]::IsNullOrWhiteSpace($env:KRT_LOCAL_SKILLS_ROOT)) {
        $LocalSkillsRoot = $env:KRT_LOCAL_SKILLS_ROOT
    } else {
        $LocalSkillsRoot = "$env:USERPROFILE\.codex\skills"
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

if ([System.IO.Path]::IsPathRooted($ManifestPath)) {
    $manifestFullPath = [System.IO.Path]::GetFullPath($ManifestPath)
} else {
    $manifestFullPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot.Path $ManifestPath))
}

if (-not (Test-Path -LiteralPath $manifestFullPath -PathType Leaf)) {
    throw "Manifest not found: $manifestFullPath"
}

$manifest = Get-Content -LiteralPath $manifestFullPath -Raw | ConvertFrom-Json
if (-not $manifest.sources) {
    throw "Manifest has no sources: $manifestFullPath"
}

$token = $env:GITHUB_TOKEN
if (-not $token) {
    $token = $env:GH_TOKEN
}

$httpHeaders = @{
    "User-Agent" = "krt-agent-skills-sync"
    "Accept" = "application/octet-stream"
}
if ($token) {
    $httpHeaders["Authorization"] = "Bearer $token"
}

$cacheRoot = Join-Path ([System.IO.Path]::GetTempPath()) "krt-agent-skills-sync"
if (-not (Test-Path -LiteralPath $cacheRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null
}

$snapshotCache = @{}

function Normalize-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        throw "Empty $FieldName."
    }

    $normalized = ($PathValue -replace "\\", "/").Trim()
    $normalized = $normalized.TrimEnd("/")

    if ([System.IO.Path]::IsPathRooted($normalized)) {
        throw "Absolute path is not allowed for ${FieldName}: $PathValue"
    }

    if ($normalized.StartsWith("../", [System.StringComparison]::Ordinal) -or
        $normalized.Contains("/../")) {
        throw "Path traversal is not allowed for ${FieldName}: $PathValue"
    }

    return $normalized
}

function Get-RepoSnapshotRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Commit
    )

    $key = "$Repo@$Commit"
    if ($snapshotCache.ContainsKey($key)) {
        return [string]$snapshotCache[$key]
    }

    $repoSafe = ($Repo -replace "[^A-Za-z0-9._-]", "_")
    $zipPath = Join-Path $cacheRoot ("{0}_{1}.zip" -f $repoSafe, $Commit)
    $extractPath = Join-Path $cacheRoot ("{0}_{1}" -f $repoSafe, $Commit)

    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
        $zipUrl = "https://codeload.github.com/$Repo/zip/$Commit"
        $zipTempPath = "$zipPath.download.$PID"
        Invoke-WebRequest -Method Get -Uri $zipUrl -Headers $httpHeaders -OutFile $zipTempPath
        Move-Item -LiteralPath $zipTempPath -Destination $zipPath -Force
    }

    if (-not (Test-Path -LiteralPath $extractPath -PathType Container)) {
        New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force
    }

    $topLevelDirectories = @(Get-ChildItem -LiteralPath $extractPath -Directory)
    if ($topLevelDirectories.Count -ne 1) {
        throw "Unexpected archive layout for $Repo@$Commit in $extractPath"
    }

    $snapshotRoot = $topLevelDirectories[0].FullName
    $snapshotCache[$key] = $snapshotRoot
    return $snapshotRoot
}

function Get-SourceFilesFromSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Commit,
        [Parameter(Mandatory = $true)][string]$SourceBasePath
    )

    $snapshotRoot = Get-RepoSnapshotRoot -Repo $Repo -Commit $Commit
    $sourcePath = Join-Path $snapshotRoot ($SourceBasePath -replace "/", "\")

    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Source path '$SourceBasePath' not found in $Repo@$Commit."
    }

    $files = New-Object System.Collections.Generic.List[object]
    $item = Get-Item -LiteralPath $sourcePath
    if (-not $item.PSIsContainer) {
        $files.Add([pscustomobject]@{
            RelativePath = $item.Name
            Bytes = [System.IO.File]::ReadAllBytes($item.FullName)
        })
        return $files
    }

    $sourceRoot = [System.IO.Path]::GetFullPath($sourcePath)
    $prefixLength = $sourceRoot.Length
    if (-not $sourceRoot.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $prefixLength = $prefixLength + 1
    }

    $sourceFiles = Get-ChildItem -LiteralPath $sourceRoot -File -Recurse
    foreach ($file in $sourceFiles) {
        $relativePath = $file.FullName.Substring($prefixLength) -replace "\\", "/"
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            continue
        }

        $files.Add([pscustomobject]@{
            RelativePath = $relativePath
            Bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        })
    }

    if ($files.Count -eq 0) {
        throw "No files found under source path '$SourceBasePath' in $Repo@$Commit."
    }

    return $files
}

function Get-FileBytesOrNull {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    return [System.IO.File]::ReadAllBytes([System.IO.Path]::GetFullPath($Path))
}

function Test-ByteArrayEqual {
    param(
        [byte[]]$Left,
        [byte[]]$Right
    )

    if ($null -eq $Left -or $null -eq $Right) {
        return $false
    }

    if ($Left.Length -ne $Right.Length) {
        return $false
    }

    for ($i = 0; $i -lt $Left.Length; $i = $i + 1) {
        if ($Left[$i] -ne $Right[$i]) {
            return $false
        }
    }

    return $true
}

function Get-RelativeFilesInDirectory {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
        return @()
    }

    $rootFullPath = [System.IO.Path]::GetFullPath($RootPath)
    $prefixLength = $rootFullPath.Length
    if (-not $rootFullPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $prefixLength = $prefixLength + 1
    }

    $files = Get-ChildItem -LiteralPath $RootPath -File -Recurse | ForEach-Object {
        $fullPath = $_.FullName
        $relativePath = $fullPath.Substring($prefixLength) -replace "\\", "/"
        $relativePath
    }

    return @($files)
}

function Remove-EmptyDirectories {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
        return
    }

    $directories = Get-ChildItem -LiteralPath $RootPath -Directory -Recurse |
        Sort-Object FullName -Descending

    foreach ($directory in $directories) {
        $children = Get-ChildItem -LiteralPath $directory.FullName -Force
        if ($children.Count -eq 0) {
            Remove-Item -LiteralPath $directory.FullName -Force
        }
    }
}

$managedSkills = New-Object System.Collections.Generic.HashSet[string]
$managedDestinations = New-Object System.Collections.Generic.HashSet[string]
$verificationProblems = New-Object System.Collections.Generic.List[string]

$updatedFiles = 0
$createdFiles = 0
$removedFiles = 0
$verifiedFiles = 0
$unchangedFiles = 0

foreach ($source in $manifest.sources) {
    $skill = [string]$source.skill
    $repo = [string]$source.repo
    $commit = [string]$source.commit
    $sourceBasePath = Normalize-RelativePath -PathValue ([string]$source.sourceBasePath) -FieldName "sourceBasePath"
    $destinationPath = Normalize-RelativePath -PathValue ([string]$source.destinationPath) -FieldName "destinationPath"

    if ([string]::IsNullOrWhiteSpace($skill)) {
        throw "Manifest source has empty skill name."
    }
    if ([string]::IsNullOrWhiteSpace($repo) -or [string]::IsNullOrWhiteSpace($commit)) {
        throw "Manifest source '$skill' has empty repo/commit."
    }
    if (-not $destinationPath.StartsWith(".agents/skills/", [System.StringComparison]::Ordinal)) {
        throw "Destination for '$skill' must stay under .agents/skills/: $destinationPath"
    }

    if (-not $managedSkills.Add($skill)) {
        throw "Duplicate skill in manifest: $skill"
    }
    if (-not $managedDestinations.Add($destinationPath)) {
        throw "Duplicate destinationPath in manifest: $destinationPath"
    }

    Write-Host "Processing skill '$skill' from $repo@$commit"
    $sourceFiles = Get-SourceFilesFromSnapshot -Repo $repo -Commit $commit -SourceBasePath $sourceBasePath

    $expectedFiles = @{}
    foreach ($sourceFile in $sourceFiles) {
        $expectedFiles[[string]$sourceFile.RelativePath] = [byte[]]$sourceFile.Bytes
    }

    $destinationFullPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot.Path $destinationPath))
    if (-not (Test-Path -LiteralPath $destinationFullPath -PathType Container)) {
        if ($VerifyOnly) {
            $verificationProblems.Add("Missing directory for '$skill': $destinationPath")
        } else {
            New-Item -ItemType Directory -Path $destinationFullPath -Force | Out-Null
        }
    }

    $existingRelativeFiles = Get-RelativeFilesInDirectory -RootPath $destinationFullPath
    $expectedRelativeFiles = @($expectedFiles.Keys)

    foreach ($relativePath in $expectedRelativeFiles) {
        $targetPath = Join-Path $destinationFullPath ($relativePath -replace "/", "\")
        $expectedBytes = [byte[]]$expectedFiles[$relativePath]
        $localBytes = Get-FileBytesOrNull -Path $targetPath

        if ($VerifyOnly) {
            if ($null -eq $localBytes) {
                $verificationProblems.Add("Missing file for '$skill': $destinationPath/$relativePath")
                continue
            }
            if (-not (Test-ByteArrayEqual -Left $localBytes -Right $expectedBytes)) {
                $verificationProblems.Add("Modified file for '$skill': $destinationPath/$relativePath")
            } else {
                $verifiedFiles = $verifiedFiles + 1
            }
            continue
        }

        $parentDir = Split-Path -Path $targetPath -Parent
        if (-not (Test-Path -LiteralPath $parentDir -PathType Container)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }

        if ($null -eq $localBytes) {
            [System.IO.File]::WriteAllBytes($targetPath, $expectedBytes)
            Write-Host ("  created " + $destinationPath + "/" + $relativePath)
            $createdFiles = $createdFiles + 1
        } elseif (-not (Test-ByteArrayEqual -Left $localBytes -Right $expectedBytes)) {
            [System.IO.File]::WriteAllBytes($targetPath, $expectedBytes)
            Write-Host ("  updated " + $destinationPath + "/" + $relativePath)
            $updatedFiles = $updatedFiles + 1
        } else {
            $unchangedFiles = $unchangedFiles + 1
        }
    }

    foreach ($existingRelativePath in $existingRelativeFiles) {
        if ($expectedFiles.ContainsKey($existingRelativePath)) {
            continue
        }

        if ($VerifyOnly) {
            $verificationProblems.Add("Unexpected file for '$skill': $destinationPath/$existingRelativePath")
            continue
        }

        $staleFilePath = Join-Path $destinationFullPath ($existingRelativePath -replace "/", "\")
        Remove-Item -LiteralPath $staleFilePath -Force
        Write-Host ("  removed " + $destinationPath + "/" + $existingRelativePath)
        $removedFiles = $removedFiles + 1
    }

    if (-not $VerifyOnly) {
        Remove-EmptyDirectories -RootPath $destinationFullPath
    }
}

if ($VerifyOnly) {
    if ($verificationProblems.Count -gt 0) {
        Write-Host ""
        Write-Host "Verification failed:" -ForegroundColor Red
        foreach ($problem in $verificationProblems) {
            Write-Host (" - " + $problem) -ForegroundColor Red
        }
        exit 1
    }

    Write-Host ("Verification passed. Files verified: " + $verifiedFiles)
    exit 0
}

Write-Host ""
Write-Host ("Sync complete. Created={0} Updated={1} Removed={2} Unchanged={3}" -f `
    $createdFiles, $updatedFiles, $removedFiles, $unchangedFiles)

if ($InstallLocal) {
    $localRootFullPath = [System.IO.Path]::GetFullPath($LocalSkillsRoot)
    if (-not (Test-Path -LiteralPath $localRootFullPath -PathType Container)) {
        New-Item -ItemType Directory -Path $localRootFullPath -Force | Out-Null
    }

    foreach ($source in $manifest.sources) {
        $skill = [string]$source.skill
        $destinationPath = Normalize-RelativePath `
            -PathValue ([string]$source.destinationPath) `
            -FieldName "destinationPath"
        $repoSkillPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot.Path $destinationPath))
        $localSkillPath = Join-Path $localRootFullPath $skill

        if (-not (Test-Path -LiteralPath $repoSkillPath -PathType Container)) {
            throw "Cannot install '$skill': repo skill path missing: $repoSkillPath"
        }

        if (Test-Path -LiteralPath $localSkillPath) {
            Remove-Item -LiteralPath $localSkillPath -Recurse -Force
        }

        Copy-Item -LiteralPath $repoSkillPath -Destination $localSkillPath -Recurse -Force
        Write-Host ("Installed local skill: " + $skill + " -> " + $localSkillPath)
    }
}
