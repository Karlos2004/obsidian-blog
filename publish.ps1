$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$syncScript = Join-Path $repoRoot 'sync-content.ps1'

$stateDirectory = Join-Path $env:LOCALAPPDATA 'QuartzPublish'
$logPath = Join-Path $stateDirectory 'publish.log'
$lockPath = Join-Path $stateDirectory 'publish.lock'

$lockStream = $null
$transcriptStarted = $false
$exitCode = 1

New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null

# Prevent two publishing jobs from running simultaneously.
try {
    $lockStream = [System.IO.File]::Open(
        $lockPath,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
}
catch {
    Set-Content -LiteralPath $logPath -Value 'A publishing job is already running.'
    exit 2
}

try {
    Start-Transcript -LiteralPath $logPath -Force | Out-Null
    $transcriptStarted = $true

    Set-Location -LiteralPath $repoRoot
    $env:GIT_TERMINAL_PROMPT = '0'

    # Trust only this repository for Git commands launched by this process.
    # This avoids ownership-check differences between interactive PowerShell
    # and applications such as AutoHotkey without changing global Git config.
    $env:GIT_CONFIG_COUNT = '1'
    $env:GIT_CONFIG_KEY_0 = 'safe.directory'
    $env:GIT_CONFIG_VALUE_0 = $repoRoot.Replace('\', '/')

    if (-not (Test-Path -LiteralPath '.git' -PathType Container)) {
        throw 'Quartz Git repository was not found.'
    }

    if (-not (Test-Path -LiteralPath $syncScript -PathType Leaf)) {
        throw 'sync-content.ps1 was not found.'
    }

    # Abort if an earlier manual edit has not been committed.
    $existingChanges = @(& git status --porcelain)

    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to read the Git working-tree status.'
    }

    if ($existingChanges.Count -gt 0) {
        throw @"
The Quartz working tree is not clean.
Review it manually before publishing:

$($existingChanges -join [Environment]::NewLine)
"@
    }

    Write-Host 'Downloading the latest GitHub changes...'

    & git pull --rebase origin v5

    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to update the local v5 branch.'
    }

    Write-Host 'Synchronizing 70_Publish...'

    & $syncScript

    $contentChanges = @(& git status --porcelain -- content)

    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to inspect content changes.'
    }

    if ($contentChanges.Count -eq 0) {
        Write-Host 'There are no new publishing changes.'
        $exitCode = 0
    }
    else {
        Write-Host 'Validating the Quartz build...'

        & npx quartz build

        if ($LASTEXITCODE -ne 0) {
            throw 'Quartz build validation failed.'
        }

        # Stage only the public content directory.
        & git add --all -- content

        if ($LASTEXITCODE -ne 0) {
            throw 'Unable to stage the published content.'
        }

        $commitMessage = 'Update published notes ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')

        & git commit -m $commitMessage

        if ($LASTEXITCODE -ne 0) {
            throw 'Unable to create the publishing commit.'
        }

        # Account for a remote update that occurred during the build.
        & git pull --rebase origin v5

        if ($LASTEXITCODE -ne 0) {
            throw 'Unable to rebase the publishing commit.'
        }

        & git push origin v5

        if ($LASTEXITCODE -ne 0) {
            throw 'Unable to push the publishing commit.'
        }

        Write-Host 'Publishing completed successfully.'
        $exitCode = 0
    }
}
catch {
    Write-Host ('PUBLISHING FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    $exitCode = 1
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }

    if ($null -ne $lockStream) {
        $lockStream.Dispose()
    }
}

exit $exitCode
