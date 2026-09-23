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
$protectedPaths = @(
    [System.IO.Path]::GetPathRoot($destinationPath),
    [System.IO.Path]::GetFullPath($env:USERPROFILE),
    [System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.codex')),
    [System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.codex\skills'))
) | ForEach-Object { $_.TrimEnd('\') }

if ($protectedPaths -contains $destinationPath.TrimEnd('\')) {
    throw "Refusing to install into or replace a protected directory: $destinationPath"
}

if ($source.TrimEnd('\') -eq $destinationPath.TrimEnd('\')) {
    Write-Host "Sketch is already located at $destinationPath"
    exit 0
}

if (Test-Path -LiteralPath $destinationPath) {
    if (-not $Force) {
        throw "Destination already exists: $destinationPath. Re-run with -Force to replace it with this version."
    }
    Remove-Item -LiteralPath $destinationPath -Recurse -Force
    Write-Host "Previous version removed from $destinationPath"
}

$parent = [System.IO.Path]::GetDirectoryName($destinationPath)
[System.IO.Directory]::CreateDirectory($parent) | Out-Null
[System.IO.Directory]::CreateDirectory($destinationPath) | Out-Null
Copy-Item -LiteralPath (Join-Path $source 'SKILL.md') -Destination $destinationPath -Force
Copy-Item -LiteralPath (Join-Path $source 'agents') -Destination $destinationPath -Recurse -Force
Copy-Item -LiteralPath (Join-Path $source 'scripts') -Destination $destinationPath -Recurse -Force

if (-not $SkipSelfTest) {
    $testPath = Join-Path ([System.IO.Path]::GetTempPath()) ("sketch-install-test-{0}.png" -f [Guid]::NewGuid().ToString('N'))
    $uiTestPath = Join-Path ([System.IO.Path]::GetTempPath()) ("sketch-ui-test-{0}.png" -f [Guid]::NewGuid().ToString('N'))
    $uiTestPaths = @()
    try {
        $json = & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $destinationPath 'scripts\sketchpad.ps1') -SelfTest -OutputPath $testPath
        $result = $json | ConvertFrom-Json
        if ($result.status -ne 'self_test' -or -not (Test-Path -LiteralPath $testPath)) {
            throw "Self-test did not complete successfully: $json"
        }
        $uiJson = & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $destinationPath 'scripts\sketchpad.ps1') -UiSelfTest -OutputPath $uiTestPath
        $uiResult = $uiJson | ConvertFrom-Json
        $uiTestPaths = @($uiResult.paths)
        $allUiPathsExist = $uiTestPaths.Count -eq 2
        foreach ($path in $uiTestPaths) {
            if (-not (Test-Path -LiteralPath $path)) { $allUiPathsExist = $false }
        }
        if ($uiResult.status -ne 'ui_self_test' -or -not $allUiPathsExist) {
            throw "UI self-test did not complete successfully: $uiJson"
        }
    }
    finally {
        if (Test-Path -LiteralPath $testPath) { Remove-Item -LiteralPath $testPath -Force }
        foreach ($path in @($uiTestPath) + $uiTestPaths) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        }
    }
}

Write-Host "Sketch installed at $destinationPath"
Write-Host 'Start a new Codex task and invoke $sketch.'
