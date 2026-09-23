param(
    [string]$Destination = (Join-Path $env:USERPROFILE '.codex\skills\sketch'),
    [switch]$Force,
    [switch]$SkipSelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'Sketch supports Windows only.'
}

$source = [System.IO.Path]::GetFullPath($PSScriptRoot)
$destinationPath = [System.IO.Path]::GetFullPath($Destination)

if ($source.TrimEnd('\') -eq $destinationPath.TrimEnd('\')) {
    Write-Host "Sketch is already located at $destinationPath"
    exit 0
}

if (Test-Path -LiteralPath $destinationPath) {
    if (-not $Force) {
        throw "Destination already exists: $destinationPath. Re-run with -Force to back it up and install this version."
    }
    $backupPath = "$destinationPath.backup-$([DateTime]::Now.ToString('yyyyMMdd-HHmmss'))"
    Move-Item -LiteralPath $destinationPath -Destination $backupPath
    Write-Host "Previous version backed up to $backupPath"
}

$parent = [System.IO.Path]::GetDirectoryName($destinationPath)
[System.IO.Directory]::CreateDirectory($parent) | Out-Null
[System.IO.Directory]::CreateDirectory($destinationPath) | Out-Null
Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination $destinationPath -Recurse -Force

if (-not $SkipSelfTest) {
    $testPath = Join-Path ([System.IO.Path]::GetTempPath()) ("sketch-install-test-{0}.png" -f [Guid]::NewGuid().ToString('N'))
    $uiTestPath = Join-Path ([System.IO.Path]::GetTempPath()) ("sketch-ui-test-{0}.png" -f [Guid]::NewGuid().ToString('N'))
    try {
        $json = & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $destinationPath 'scripts\sketchpad.ps1') -SelfTest -OutputPath $testPath
        $result = $json | ConvertFrom-Json
        if ($result.status -ne 'self_test' -or -not (Test-Path -LiteralPath $testPath)) {
            throw "Self-test did not complete successfully: $json"
        }
        $uiJson = & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $destinationPath 'scripts\sketchpad.ps1') -UiSelfTest -OutputPath $uiTestPath
        $uiResult = $uiJson | ConvertFrom-Json
        if ($uiResult.status -ne 'ui_self_test' -or -not (Test-Path -LiteralPath $uiTestPath)) {
            throw "UI self-test did not complete successfully: $uiJson"
        }
    }
    finally {
        if (Test-Path -LiteralPath $testPath) { Remove-Item -LiteralPath $testPath -Force }
        if (Test-Path -LiteralPath $uiTestPath) { Remove-Item -LiteralPath $uiTestPath -Force }
    }
}

Write-Host "Sketch installed at $destinationPath"
Write-Host 'Start a new Codex task and invoke $sketch.'
