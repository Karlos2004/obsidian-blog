$ErrorActionPreference = 'Stop'

$source = 'C:\obsidian vault\70_Publish'
$destination = Join-Path $PSScriptRoot 'content'

if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    throw "게시 원본 폴더를 찾을 수 없습니다: $source"
}

if (-not (Test-Path -LiteralPath (Join-Path $source 'index.md') -PathType Leaf)) {
    throw '70_Publish에 index.md가 없습니다. 동기화를 중단합니다.'
}

if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'package.json') -PathType Leaf)) {
    throw 'Quartz 프로젝트 폴더에서 실행된 것이 아닙니다.'
}

Write-Host '70_Publish를 Quartz content 폴더에 동기화합니다...'

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
    throw "콘텐츠 동기화에 실패했습니다. robocopy 종료 코드: $copyResult"
}

$fileCount = (
    Get-ChildItem -LiteralPath $destination -Recurse -File
).Count

Write-Host "동기화 완료: $fileCount개 파일"