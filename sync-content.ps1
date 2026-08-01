$ErrorActionPreference = 'Stop'

$source = 'C:\obsidian vault\70_Publish'
$destination = Join-Path $PSScriptRoot 'content'

if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    throw "Publish source folder was not found: $source"
}

if (-not (Test-Path -LiteralPath (Join-Path $source 'index.md') -PathType Leaf)) {
    throw '70_Publish does not contain index.md. Synchronization stopped.'
}

if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'package.json') -PathType Leaf)) {
    throw 'This script must be run from the Quartz project directory.'
}

Write-Host 'Synchronizing 70_Publish to the Quartz content directory...'

& robocopy `
    $source `
    $destination `
    /MIR `
    /R:2 `
    /W:1 `
    /XD '.obsidian' `
    /XF '.DS_Store' 'Thumbs.db'

$copyResult = $LASTEXITCODE

if ($copyResult -ge 8) {
    throw "Content synchronization failed. Robocopy exit code: $copyResult"
}

$fileCount = (
    Get-ChildItem -LiteralPath $destination -Recurse -File
).Count

Write-Host "Synchronization completed: $fileCount file(s)."
