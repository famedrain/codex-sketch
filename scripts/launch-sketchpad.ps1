param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-LauncherError {
    param([string]$Message)
    [pscustomobject]@{ status = 'error'; message = $Message } | ConvertTo-Json -Compress
}

if ($env:OS -ne 'Windows_NT') {
    Write-LauncherError 'Sketch supports Windows only.'
    exit 1
}

try {
    if ($null -eq ('CodexVisibleDesktopProcess' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class CodexVisibleDesktopProcess
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO
    {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public int dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION
    {
        public IntPtr hProcess;
        public IntPtr hThread;
        public int dwProcessId;
        public int dwThreadId;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CreateProcess(
        string applicationName,
        StringBuilder commandLine,
        IntPtr processAttributes,
        IntPtr threadAttributes,
        bool inheritHandles,
        uint creationFlags,
        IntPtr environment,
        string currentDirectory,
        ref STARTUPINFO startupInfo,
        out PROCESS_INFORMATION processInformation);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetExitCodeProcess(IntPtr process, out uint exitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr handle);
}
'@
    }

    $sketchScript = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'sketchpad.ps1'))
    $resultDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'codex-sketch'
    [System.IO.Directory]::CreateDirectory($resultDirectory) | Out-Null
    $resultPath = Join-Path $resultDirectory ("result-{0}.json" -f [Guid]::NewGuid().ToString('N'))
    $powerShellPath = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $powerShellPath)) {
        $powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    $quotedPowerShell = '"{0}"' -f $powerShellPath.Replace('"', '\"')
    $quotedScript = '"{0}"' -f $sketchScript.Replace('"', '\"')
    $quotedResult = '"{0}"' -f $resultPath.Replace('"', '\"')
    $commandLine = New-Object System.Text.StringBuilder("$quotedPowerShell -NoProfile -STA -ExecutionPolicy Bypass -File $quotedScript -ResultPath $quotedResult")

    $startupInfo = New-Object CodexVisibleDesktopProcess+STARTUPINFO
    $startupInfo.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($startupInfo)
    $startupInfo.lpDesktop = 'winsta0\default'
    $processInfo = New-Object CodexVisibleDesktopProcess+PROCESS_INFORMATION
    $createNoWindow = [uint32]0x08000000
    $created = [CodexVisibleDesktopProcess]::CreateProcess(
        $powerShellPath,
        $commandLine,
        [IntPtr]::Zero,
        [IntPtr]::Zero,
        $false,
        $createNoWindow,
        [IntPtr]::Zero,
        $PSScriptRoot,
        [ref]$startupInfo,
        [ref]$processInfo)

    if (-not $created) {
        throw "Could not start Sketch on the visible desktop. Windows error: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }

    [void][CodexVisibleDesktopProcess]::CloseHandle($processInfo.hThread)
    try {
        while ($true) {
            if (Test-Path -LiteralPath $resultPath) {
                $json = [System.IO.File]::ReadAllText($resultPath)
                Write-Output $json
                break
            }

            $waitResult = [CodexVisibleDesktopProcess]::WaitForSingleObject($processInfo.hProcess, 250)
            if ($waitResult -eq 0) {
                [uint32]$exitCode = 0
                [void][CodexVisibleDesktopProcess]::GetExitCodeProcess($processInfo.hProcess, [ref]$exitCode)
                throw "Sketch exited without returning a result. Exit code: $exitCode"
            }
            if ($waitResult -eq 0xFFFFFFFF) {
                throw "Could not wait for Sketch. Windows error: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
            }
        }
    }
    finally {
        [void][CodexVisibleDesktopProcess]::CloseHandle($processInfo.hProcess)
        if (Test-Path -LiteralPath $resultPath) {
            Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
        }
    }
}
catch {
    Write-LauncherError $_.Exception.Message
    exit 1
}
