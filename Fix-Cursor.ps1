#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Menu','Status','Apply','Restore','Default')][string]$Action = 'Menu',
    [string]$AdapterId,
    [switch]$Restart
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src\PsrFix.psm1') -Force

function Select-Adapter {
    $adapters = @(Get-AmdAdapter)
    if ($AdapterId) {
        $matches = @($adapters | Where-Object InstanceId -eq $AdapterId)
        if ($matches.Count -ne 1) { throw 'AdapterId must match one present AMD display adapter from Status.' }
        return $matches[0]
    }
    if ($adapters.Count -eq 0) { throw 'No present AMD PCI display adapter was found.' }
    if ($adapters.Count -eq 1) { return $adapters[0] }
    Write-Host 'Choose the GPU shown under Connected to in Settings > System > Display > Advanced display.'
    for ($i = 0; $i -lt $adapters.Count; $i++) { Write-Host "[$($i + 1)] $($adapters[$i].Name)  $($adapters[$i].DriverVersion)" }
    $number = 0
    if (![int]::TryParse((Read-Host 'GPU number'), [ref]$number) -or $number -lt 1 -or $number -gt $adapters.Count) { throw 'Select a listed GPU number.' }
    return $adapters[$number - 1]
}

function Invoke-Change {
    param($Adapter, [string]$Operation, [bool]$RestartDevice)
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        # Encode literal arguments so paths and hardware IDs cannot become shell commands.
        $scriptPath = $PSCommandPath.Replace("'", "''")
        $deviceId = $Adapter.InstanceId.Replace("'", "''")
        $command = "& '$scriptPath' -Action '$Operation' -AdapterId '$deviceId'"
        if ($RestartDevice) { $command += ' -Restart' }
        $command += '; $result = $LASTEXITCODE; Read-Host ''Press Enter to close''; exit $result'
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $process = Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) -PassThru -Wait
        if ($process.ExitCode -ne 0) { throw "The elevated operation exited with code $($process.ExitCode). Read its message and check Status." }
        return
    }
    $result = Set-PsrPolicy -Adapter $Adapter -Action $Operation
    Write-Host $result.Message
    if ($RestartDevice -and $result.Changed) { Write-Host (Restart-PsrAdapter $Adapter) }
}

try {
    if ($Action -eq 'Status') { Get-PsrStatus | Format-List; exit 0 }
    if ($Action -ne 'Menu') {
        Invoke-Change -Adapter (Select-Adapter) -Operation $Action -RestartDevice $Restart.IsPresent
        exit 0
    }
    do {
        Write-Host "`nAMD PSR Cursor Fix"
        Write-Host '1  Show adapters and current settings'
        Write-Host '2  Apply cursor fix (disable PSR)'
        Write-Host '3  Restore saved setting'
        Write-Host '4  Use driver default (remove override)'
        Write-Host '0  Exit'
        $choice = Read-Host 'Choose an option'
        if ($choice -eq '1') { Get-PsrStatus | Format-List }
        if ($choice -in '2','3','4') {
            $operation = @{ '2'='Apply'; '3'='Restore'; '4'='Default' }[$choice]
            $adapter = Select-Adapter
            if ($operation -eq 'Apply') { Write-Host 'Disabling PSR may increase idle display power use. Other hardware and driver versions need individual validation.' }
            $restartNow = (Read-Host 'Restart this display device now to activate the setting? The screen may blink. [y/N]') -eq 'y'
            Invoke-Change -Adapter $adapter -Operation $operation -RestartDevice $restartNow
        }
    } while ($choice -ne '0')
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
