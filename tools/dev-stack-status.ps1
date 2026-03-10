param(
    [switch]$Json,
    [switch]$VerifySkills
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "tooling-common.ps1")

$repoRoot = Enter-KrtRepoRoot -ScriptRoot $PSScriptRoot
$manifestPath = Join-Path $repoRoot.Path "tools/agent-skills.manifest.json"
$mcpWrapperPath = Join-Path $repoRoot.Path "tools/run-krt-mcp.ps1"
$mcpServerPath = Join-Path $repoRoot.Path "tools/krt_mcp_server.py"
$skillsSyncPath = Join-Path $repoRoot.Path "tools/sync-agent-skills.ps1"
$mechanicBootstrapPath = Join-Path $repoRoot.Path "tools/mech-bootstrap.ps1"
$mechanicWrapperPath = Join-Path $repoRoot.Path "tools/mech-krt.ps1"

$localSkillsRoot = if (-not [string]::IsNullOrWhiteSpace($env:KRT_LOCAL_SKILLS_ROOT)) {
    $env:KRT_LOCAL_SKILLS_ROOT
} else {
    "$env:USERPROFILE\.codex\skills"
}

$mechanicRoot = if (-not [string]::IsNullOrWhiteSpace($env:KRT_MECHANIC_ROOT)) {
    $env:KRT_MECHANIC_ROOT
} else {
    "C:\dev\Mechanic"
}

$mechanicExe = if (-not [string]::IsNullOrWhiteSpace($env:KRT_MECHANIC_EXE)) {
    $env:KRT_MECHANIC_EXE
} else {
    "C:\dev\Mechanic\desktop\.venv\Scripts\mech.exe"
}

$powershellExe = if (-not [string]::IsNullOrWhiteSpace($env:KRT_POWERSHELL_EXE)) {
    $env:KRT_POWERSHELL_EXE
} else {
    "powershell"
}

function Resolve-CommandTarget {
    param([string[]]$Candidates)

    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $trimmed = $candidate.Trim()
        $looksLikePath = [System.IO.Path]::IsPathRooted($trimmed) -or
            $trimmed.Contains("\") -or
            $trimmed.Contains("/")

        if ($looksLikePath) {
            $fullPath = [System.IO.Path]::GetFullPath($trimmed)
            if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
                return [pscustomobject]@{
                    Requested = $trimmed
                    Path = $fullPath
                }
            }
            continue
        }

        $command = Get-Command $trimmed -ErrorAction SilentlyContinue
        if ($command) {
            return [pscustomobject]@{
                Requested = $trimmed
                Path = $command.Source
            }
        }
    }

    return $null
}

function New-CommandStatus {
    param(
        [string]$Name,
        [string[]]$Candidates,
        [bool]$Required,
        [string]$Purpose,
        [string]$Suggestion
    )

    $resolved = Resolve-CommandTarget -Candidates $Candidates
    $available = $null -ne $resolved
    $status = if ($available) {
        "ready"
    } elseif ($Required) {
        "missing"
    } else {
        "warning"
    }

    return [pscustomobject]@{
        name = $Name
        required = $Required
        purpose = $Purpose
        requested = @($Candidates)
        available = $available
        status = $status
        path = if ($available) { $resolved.Path } else { $null }
        suggestion = if (-not $available) { $Suggestion } else { $null }
    }
}

function New-PathStatus {
    param(
        [string]$Name,
        [string]$Path,
        [bool]$Required,
        [string]$Suggestion,
        [switch]$Directory
    )

    $exists = if ($Directory) {
        Test-Path -LiteralPath $Path -PathType Container
    } else {
        Test-Path -LiteralPath $Path -PathType Leaf
    }

    $status = if ($exists) {
        "ready"
    } elseif ($Required) {
        "missing"
    } else {
        "warning"
    }

    return [pscustomobject]@{
        name = $Name
        required = $Required
        path = $Path
        exists = $exists
        status = $status
        suggestion = if (-not $exists) { $Suggestion } else { $null }
    }
}

function New-Warning {
    param(
        [string]$Code,
        [string]$Message,
        [string]$Severity = "warning"
    )

    return [pscustomobject]@{
        code = $Code
        severity = $Severity
        message = $Message
    }
}

$commandChecks = @(
    (New-CommandStatus `
        -Name "git" `
        -Candidates @("git") `
        -Required $true `
        -Purpose "skill sync and Mechanic bootstrap" `
        -Suggestion "Install git and ensure it is in PATH."),
    (New-CommandStatus `
        -Name "python" `
        -Candidates @("py", "python") `
        -Required $true `
        -Purpose "repo-local MCP server and Mechanic bootstrap" `
        -Suggestion "Install Python 3 and expose 'py' or 'python' in PATH."),
    (New-CommandStatus `
        -Name "powershell" `
        -Candidates @($powershellExe) `
        -Required $true `
        -Purpose "PowerShell wrappers used by MCP and tooling" `
        -Suggestion "Fix KRT_POWERSHELL_EXE or ensure PowerShell is available."),
    (New-CommandStatus `
        -Name "rg" `
        -Candidates @("rg") `
        -Required $false `
        -Purpose "fast repo scans" `
        -Suggestion "Install ripgrep to keep repo scans fast."),
    (New-CommandStatus `
        -Name "lua" `
        -Candidates @("lua", "luajit") `
        -Required $false `
        -Purpose "targeted Lua tests and schema tools" `
        -Suggestion "Install lua or luajit to run local Lua test helpers."),
    (New-CommandStatus `
        -Name "luacheck" `
        -Candidates @("luacheck") `
        -Required $false `
        -Purpose "Lua lint gate" `
        -Suggestion "Install luacheck to run the local lint gate."),
    (New-CommandStatus `
        -Name "stylua" `
        -Candidates @("stylua") `
        -Required $false `
        -Purpose "Lua formatting gate" `
        -Suggestion "Install stylua to run the formatter gate.")
)

$pathChecks = @(
    (New-PathStatus `
        -Name "skillsManifest" `
        -Path $manifestPath `
        -Required $true `
        -Suggestion "Restore tools/agent-skills.manifest.json."),
    (New-PathStatus `
        -Name "skillsSyncScript" `
        -Path $skillsSyncPath `
        -Required $true `
        -Suggestion "Restore tools/sync-agent-skills.ps1."),
    (New-PathStatus `
        -Name "mechanicBootstrapScript" `
        -Path $mechanicBootstrapPath `
        -Required $true `
        -Suggestion "Restore tools/mech-bootstrap.ps1."),
    (New-PathStatus `
        -Name "mechanicWrapperScript" `
        -Path $mechanicWrapperPath `
        -Required $true `
        -Suggestion "Restore tools/mech-krt.ps1."),
    (New-PathStatus `
        -Name "mcpWrapperScript" `
        -Path $mcpWrapperPath `
        -Required $true `
        -Suggestion "Restore tools/run-krt-mcp.ps1."),
    (New-PathStatus `
        -Name "mcpServerScript" `
        -Path $mcpServerPath `
        -Required $true `
        -Suggestion "Restore tools/krt_mcp_server.py.")
)

$manifest = $null
$manifestLoadError = $null
try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
} catch {
    $manifestLoadError = $_.Exception.Message
}

$managedSkills = @()
$vendoredSkillEntries = @()
if ($manifest -and $manifest.sources) {
    foreach ($source in $manifest.sources) {
        $skill = [string]$source.skill
        if ([string]::IsNullOrWhiteSpace($skill)) {
            continue
        }

        $managedSkills += $skill
        $destinationPath = Join-Path $repoRoot.Path ([string]$source.destinationPath -replace "/", "\")
        $skillDocPath = Join-Path $destinationPath "SKILL.md"
        $exists = Test-Path -LiteralPath $skillDocPath -PathType Leaf
        $vendoredSkillEntries += [pscustomobject]@{
            skill = $skill
            source = [string]$source.repo
            commit = [string]$source.commit
            destination = $destinationPath
            skillDoc = $skillDocPath
            exists = $exists
            status = if ($exists) { "ready" } else { "missing" }
        }
    }
}

$vendoredSkillsReady = $manifest -and $vendoredSkillEntries.Count -gt 0 -and
    @($vendoredSkillEntries | Where-Object { -not $_.exists }).Count -eq 0

$localSkillEntries = @()
foreach ($skill in $managedSkills) {
    $localSkillPath = Join-Path $localSkillsRoot $skill
    $localSkillDocPath = Join-Path $localSkillPath "SKILL.md"
    $exists = Test-Path -LiteralPath $localSkillDocPath -PathType Leaf
    $localSkillEntries += [pscustomobject]@{
        skill = $skill
        path = $localSkillPath
        skillDoc = $localSkillDocPath
        exists = $exists
        status = if ($exists) { "ready" } else { "missing" }
    }
}

$localSkillsReady = $localSkillEntries.Count -gt 0 -and
    @($localSkillEntries | Where-Object { -not $_.exists }).Count -eq 0

$mechanicRootExists = Test-Path -LiteralPath $mechanicRoot -PathType Container
$mechanicExeExists = Test-Path -LiteralPath $mechanicExe -PathType Leaf
$mechanicReady = $mechanicExeExists

$pythonReady = @($commandChecks | Where-Object { $_.name -eq "python" -and $_.available }).Count -gt 0
$powershellReady = @($commandChecks | Where-Object { $_.name -eq "powershell" -and $_.available }).Count -gt 0
$mcpFilesReady = @($pathChecks | Where-Object { $_.name -like "mcp*" -and $_.exists }).Count -eq 2
$mcpReady = $pythonReady -and $powershellReady -and $mcpFilesReady

$vendoredVerify = [pscustomobject]@{
    enabled = $VerifySkills.IsPresent
    status = "skipped"
    ready = $null
    message = "Snapshot verification skipped."
}

if ($VerifySkills) {
    if ($powershellReady -and (Test-Path -LiteralPath $skillsSyncPath -PathType Leaf)) {
        $powershellCommand = @($commandChecks | Where-Object { $_.name -eq "powershell" -and $_.available })[0]
        $verifyOutput = & $powershellCommand.path -NoProfile -ExecutionPolicy Bypass -File $skillsSyncPath `
            -VerifyOnly 2>&1
        $verifySucceeded = $LASTEXITCODE -eq 0
        $verifyText = ($verifyOutput | ForEach-Object {
            if ($_ -is [string]) {
                $_.TrimEnd()
            } else {
                [string]$_
            }
        }) -join [Environment]::NewLine

        $vendoredVerify = [pscustomobject]@{
            enabled = $true
            status = if ($verifySucceeded) { "clean" } else { "drift" }
            ready = $verifySucceeded
            message = if ([string]::IsNullOrWhiteSpace($verifyText)) {
                if ($verifySucceeded) { "Vendored skills match the pinned manifest." } else { "Verification failed." }
            } else {
                $verifyText
            }
        }
    } else {
        $vendoredVerify = [pscustomobject]@{
            enabled = $true
            status = "error"
            ready = $false
            message = "Cannot verify skill snapshots because PowerShell or the sync script is unavailable."
        }
    }
}

$warnings = New-Object System.Collections.Generic.List[object]
$suggestions = New-Object System.Collections.Generic.List[string]

if ($manifestLoadError) {
    $warnings.Add((New-Warning -Code "MANIFEST_LOAD_FAILED" -Message $manifestLoadError -Severity "error"))
    $suggestions.Add("Fix tools/agent-skills.manifest.json before using skill sync.")
}

if (-not $vendoredSkillsReady) {
    $warnings.Add((New-Warning `
        -Code "VENDORED_SKILLS_MISSING" `
        -Message "One or more vendored skills are missing from .agents/skills."))
    $suggestions.Add("Run: powershell -NoProfile -ExecutionPolicy Bypass -File tools/sync-agent-skills.ps1")
}

if (-not $localSkillsReady -and $managedSkills.Count -gt 0) {
    $warnings.Add((New-Warning `
        -Code "LOCAL_SKILLS_MISSING" `
        -Message "Managed skills are not fully installed in the local Codex skills directory."))
    $suggestions.Add(
        "Run: powershell -NoProfile -ExecutionPolicy Bypass -File tools/sync-agent-skills.ps1 -InstallLocal"
    )
}

if (-not $mechanicReady) {
    $warnings.Add((New-Warning `
        -Code "MECHANIC_NOT_READY" `
        -Message "Mechanic is not bootstrapped at the configured executable path."))
    $suggestions.Add("Run: powershell -NoProfile -ExecutionPolicy Bypass -File tools/mech-bootstrap.ps1")
}

if (-not $mcpReady) {
    $warnings.Add((New-Warning `
        -Code "MCP_NOT_READY" `
        -Message "Repo-local MCP server prerequisites are incomplete."))
    $suggestions.Add("Fix Python/PowerShell availability, then run: powershell -File tools/run-krt-mcp.ps1")
}

if ($VerifySkills -and $vendoredVerify.status -eq "drift") {
    $warnings.Add((New-Warning `
        -Code "VENDORED_SKILL_DRIFT" `
        -Message "Vendored skills drift from the manifest-pinned upstream snapshots."))
    $suggestions.Add("Run: powershell -NoProfile -ExecutionPolicy Bypass -File tools/sync-agent-skills.ps1")
}

$repoReady = $vendoredSkillsReady -and
    @($commandChecks | Where-Object { $_.required -and -not $_.available }).Count -eq 0 -and
    @($pathChecks | Where-Object { $_.required -and -not $_.exists }).Count -eq 0

$summary = [pscustomobject]@{
    repoReady = $repoReady
    localSkillsReady = $localSkillsReady
    mechanicReady = $mechanicReady
    mcpReady = $mcpReady
    fullReady = $repoReady -and $localSkillsReady -and $mechanicReady -and $mcpReady
    managedSkillCount = $managedSkills.Count
    warningCount = $warnings.Count
}

$warningItems = @($warnings.ToArray())
$suggestionItems = @($suggestions.ToArray())

$vendoredSkillsResult = [pscustomobject]@{
    manifestPath = $manifestPath
    ready = $vendoredSkillsReady
    total = $vendoredSkillEntries.Count
    entries = $vendoredSkillEntries
    verify = $vendoredVerify
}

$localSkillsResult = [pscustomobject]@{
    root = $localSkillsRoot
    ready = $localSkillsReady
    entries = $localSkillEntries
}

$mechanicResult = [pscustomobject]@{
    root = $mechanicRoot
    rootExists = $mechanicRootExists
    exe = $mechanicExe
    exeExists = $mechanicExeExists
    ready = $mechanicReady
    bootstrapCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File tools/mech-bootstrap.ps1"
}

$mcpResult = [pscustomobject]@{
    wrapperPath = $mcpWrapperPath
    serverPath = $mcpServerPath
    ready = $mcpReady
    startCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-krt-mcp.ps1"
}

$result = New-Object PSObject
$result | Add-Member -NotePropertyName "ok" -NotePropertyValue $true
$result | Add-Member -NotePropertyName "repoRoot" -NotePropertyValue $repoRoot.Path
$result | Add-Member `
    -NotePropertyName "reasoning" `
    -NotePropertyValue "AFD readiness in KRT depends on vendored skills, local installs, Mechanic, and MCP agreeing."
$result | Add-Member -NotePropertyName "summary" -NotePropertyValue $summary
$result | Add-Member -NotePropertyName "commands" -NotePropertyValue $commandChecks
$result | Add-Member -NotePropertyName "paths" -NotePropertyValue $pathChecks
$result | Add-Member -NotePropertyName "vendoredSkills" -NotePropertyValue $vendoredSkillsResult
$result | Add-Member -NotePropertyName "localSkills" -NotePropertyValue $localSkillsResult
$result | Add-Member -NotePropertyName "mechanic" -NotePropertyValue $mechanicResult
$result | Add-Member -NotePropertyName "mcp" -NotePropertyValue $mcpResult
$result | Add-Member -NotePropertyName "warnings" -NotePropertyValue $warningItems
$result | Add-Member -NotePropertyName "suggestions" -NotePropertyValue $suggestionItems

if ($Json) {
    $result | ConvertTo-Json -Depth 8
    exit 0
}

Write-Host "KRT Mechanic + AFD Stack Status"
Write-Host ("Repo root: {0}" -f $repoRoot.Path)
Write-Host ""
Write-Host ("Repo ready:        {0}" -f $summary.repoReady)
Write-Host ("Local skills ready:{0}" -f $summary.localSkillsReady)
Write-Host ("Mechanic ready:    {0}" -f $summary.mechanicReady)
Write-Host ("MCP ready:         {0}" -f $summary.mcpReady)
Write-Host ("Full ready:        {0}" -f $summary.fullReady)
Write-Host ""
Write-Host "Commands:"
foreach ($entry in $commandChecks) {
    Write-Host ("- {0}: {1}" -f $entry.name, $entry.status)
    if ($entry.path) {
        Write-Host ("  path: {0}" -f $entry.path)
    }
}
Write-Host ""
Write-Host "Vendored skills:"
Write-Host ("- ready: {0} ({1} managed skill(s))" -f $vendoredSkillsReady, $vendoredSkillEntries.Count)
if ($VerifySkills) {
    Write-Host ("- verify: {0}" -f $vendoredVerify.status)
}
Write-Host ""
Write-Host "Local skills root:"
Write-Host ("- {0}" -f $localSkillsRoot)
Write-Host ""
Write-Host "Mechanic:"
Write-Host ("- root exists: {0}" -f $mechanicRootExists)
Write-Host ("- exe exists:  {0}" -f $mechanicExeExists)
Write-Host ("- exe path:    {0}" -f $mechanicExe)
Write-Host ""
Write-Host "MCP:"
Write-Host ("- wrapper: {0}" -f $mcpWrapperPath)
Write-Host ("- server:  {0}" -f $mcpServerPath)
Write-Host ""

if ($warnings.Count -gt 0) {
    Write-Host "Warnings:"
    foreach ($warning in $warnings) {
        Write-Host ("- [{0}] {1}" -f $warning.code, $warning.message)
    }
    Write-Host ""
}

if ($suggestions.Count -gt 0) {
    Write-Host "Suggested next steps:"
    foreach ($suggestion in $suggestions) {
        Write-Host ("- {0}" -f $suggestion)
    }
}
