#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Status', 'Apply', 'Restore')][string]$Action = 'Menu',
    [string]$AdapterId
)

$script:RegistryRoot = [Microsoft.Win32.Registry]::LocalMachine
$script:ValueName = 'DalPSRFeatureEnable'

function Get-AmdAdapter {
    foreach ($device in Get-PnpDevice -Class Display -PresentOnly -ErrorAction Stop) {
        if ($device.InstanceId -notmatch '^PCI\\VEN_1002&') { continue }
        $driver = (Get-PnpDeviceProperty -InstanceId $device.InstanceId -KeyName DEVPKEY_Device_Driver -ErrorAction Stop).Data
        if ($driver -notmatch '^\{4d36e968-e325-11ce-bfc1-08002be10318\}\\\d{4}$') { continue }
        $path = "SYSTEM\CurrentControlSet\Control\Class\$driver"
        $key = $script:RegistryRoot.OpenSubKey($path)
        if (!$key) { continue }
        try {
            [pscustomobject]@{
                Name = $device.FriendlyName
                InstanceId = $device.InstanceId
                RegistryPath = $path
                DriverVersion = $key.GetValue('DriverVersion', '')
            }
        } finally { $key.Dispose() }
    }
}

function Get-PsrValue($Key) {
    if ($Key.GetValueNames() -notcontains $script:ValueName) {
        return [pscustomobject]@{ Exists = $false; Kind = $null; Value = $null }
    }
    [pscustomobject]@{
        Exists = $true
        Kind = $Key.GetValueKind($script:ValueName).ToString()
        Value = $Key.GetValue($script:ValueName)
    }
}

function Get-BackupPath($Adapter) {
    $identity = ($Adapter.InstanceId + '|' + $Adapter.RegistryPath).ToUpperInvariant()
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity))
        'SOFTWARE\AMDPSRCursorFix\Backups\' + [BitConverter]::ToString($hash).Replace('-', '')
    } finally { $sha.Dispose() }
}

function Read-Backup($Adapter, $Key) {
    if (!$Key) { return }
    $json = $Key.GetValue('Record', $null)
    if (!$json) { return }
    $backup = $json | ConvertFrom-Json
    if ($backup.Schema -ne 1 -or $backup.InstanceId -ne $Adapter.InstanceId -or
        $backup.RegistryPath -ne $Adapter.RegistryPath -or $backup.State -notin 'Prepared','Applied','Restored') {
        throw 'Invalid backup for this adapter. Review its registry record before proceeding.'
    }
    $backup
}

function Set-PsrPolicy($Adapter, [ValidateSet('Apply','Restore')][string]$Operation) {
    $mutex = [Threading.Mutex]::new($false, 'Global\AMDPSRCursorFix')
    $locked = $false
    $key = $null
    $journal = $null
    try {
        try { $locked = $mutex.WaitOne(10000) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (!$locked) { throw 'Another cursor fix operation is running.' }
        $key = $script:RegistryRoot.OpenSubKey($Adapter.RegistryPath, $true)
        if (!$key) { throw 'The display adapter registry key is unavailable for writing.' }
        $value = Get-PsrValue $key
        $journal = $script:RegistryRoot.CreateSubKey((Get-BackupPath $Adapter))
        $backup = Read-Backup $Adapter $journal
        if ($Operation -eq 'Restore') {
            if (!$backup -or $backup.State -eq 'Restored') { return 'No active backup for this adapter.' }
            $wanted = $backup.Original
            $nextState = 'Restored'
        } else {
            if ($value.Exists -and $value.Kind -ne 'DWord') {
                throw 'The existing PSR setting has an unexpected registry type. It was left intact.'
            }
            if (!$backup -or $backup.State -eq 'Restored') {
                if ($value.Exists -and $value.Value -eq 0) {
                    return 'PSR is already disabled outside this backup. Use the tool or procedure that originally set it to revert it.'
                }
                $backup = [pscustomobject]@{
                    Schema = 1
                    InstanceId = $Adapter.InstanceId
                    RegistryPath = $Adapter.RegistryPath
                    Original = $value
                    State = 'Prepared'
                }
                $journal.SetValue('Record', ($backup | ConvertTo-Json -Compress -Depth 4))
                $journal.Flush()
            }
            $wanted = [pscustomobject]@{ Exists = $true; Kind = 'DWord'; Value = 0 }
            $nextState = 'Applied'
        }

        if (!$wanted.Exists) {
            $key.DeleteValue($script:ValueName, $false)
        } elseif ($wanted.Kind -eq 'DWord') {
            $key.SetValue($script:ValueName, [int]$wanted.Value, [Microsoft.Win32.RegistryValueKind]::DWord)
        } else {
            # Retain support for backups produced by the earlier tool.
            $original = switch ($wanted.Kind) {
                'QWord' { [long]$wanted.Value }
                'Binary' { ,([byte[]]@($wanted.Value)) }
                'None' { ,([byte[]]@($wanted.Value)) }
                'MultiString' { ,([string[]]@($wanted.Value)) }
                'String' { [string]$wanted.Value }
                'ExpandString' { [string]$wanted.Value }
                default { throw "Unknown saved registry type $($wanted.Kind)." }
            }
            $key.SetValue($script:ValueName, $original, [Microsoft.Win32.RegistryValueKind]$wanted.Kind)
        }
        $key.Flush()
        $actual = Get-PsrValue $key
        if ($actual.Exists -ne $wanted.Exists -or $actual.Kind -ne $wanted.Kind -or
            ($wanted.Kind -eq 'DWord' -and $actual.Value -ne $wanted.Value)) {
            throw 'The registry readback did not match. The saved backup is available for Restore.'
        }
        $backup.State = $nextState
        $journal.SetValue('Record', ($backup | ConvertTo-Json -Compress -Depth 4))
        $journal.Flush()
        if ($Operation -eq 'Apply') { return 'PSR override saved. Restart the display adapter or Windows, then test the mouse and GPU switching.' }
        'Original setting restored. Restart the display adapter or Windows to activate it.'
    } finally {
        if ($journal) { $journal.Dispose() }
        if ($key) { $key.Dispose() }
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Select-Adapter($Adapters, [string]$Id, [string]$Operation) {
    $rxPattern = 'PCI\VEN_1002&DEV_7480&SUBSYS_15131043&*'
    $igpuPattern = 'PCI\VEN_1002&DEV_1681&SUBSYS_15131043&*'
    $knownModel = $false
    if ($Operation -eq 'Apply') {
        $model = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Model
        $knownModel = $model -match '\bFA617NT\b|\bFA617NT_'
        if ($knownModel) {
            if ($Id -and $Id -like $igpuPattern) { throw 'On this ASUS model, Apply targets the RX 7700S. Leave the integrated GPU at its driver default.' }
            $Adapters = @($Adapters | Where-Object InstanceId -like $rxPattern)
            if (!$Adapters.Count) { throw 'The RX 7700S is unavailable. Use Standard mode and check Device Manager.' }
        }
    }
    if ($Id) {
        $selected = @($Adapters | Where-Object InstanceId -eq $Id)
        if ($selected.Count -ne 1) { throw 'AdapterId must match a present, eligible AMD display adapter from Status.' }
        return $selected[0]
    }
    if (!$Adapters.Count) { throw 'No eligible AMD display adapter found.' }
    if ($Adapters.Count -eq 1) { return $Adapters[0] }
    Write-Host 'Select only the AMD GPU that drives the panel when the stutter occurs.'
    for ($i = 0; $i -lt $Adapters.Count; $i++) {
        Write-Host "[$($i + 1)] $($Adapters[$i].Name)  $($Adapters[$i].DriverVersion)"
    }
    $number = 0
    if (![int]::TryParse((Read-Host 'GPU number'), [ref]$number) -or $number -lt 1 -or $number -gt $Adapters.Count) {
        throw 'Choose a listed GPU number.'
    }
    $Adapters[$number - 1]
}

function Show-Status($Adapters) {
    foreach ($adapter in $Adapters) {
        $key = $script:RegistryRoot.OpenSubKey($adapter.RegistryPath)
        $journal = $script:RegistryRoot.OpenSubKey((Get-BackupPath $adapter))
        try {
            $value = Get-PsrValue $key
            $backup = Read-Backup $adapter $journal
            [pscustomobject]@{
                GPU = $adapter.Name
                Driver = $adapter.DriverVersion
                PSR = if ($value.Exists) { "$($value.Kind) $($value.Value)" } else { 'Driver default' }
                Backup = if ($backup) { $backup.State } else { 'None' }
                AdapterId = $adapter.InstanceId
            }
        } finally {
            if ($journal) { $journal.Dispose() }
            if ($key) { $key.Dispose() }
        }
    }
}

function Invoke-Change($Adapter, [string]$Operation) {
    if ($Operation -eq 'Apply') {
        Write-Warning 'Disabling PSR can increase idle power use and prevent SmartAccess Graphics from returning to the integrated GPU.'
    }
    Write-Host "$Operation on $($Adapter.Name)"
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host (Set-PsrPolicy $Adapter $Operation)
        return
    }

    # Single-quote literal paths/IDs inside the elevated PowerShell process.
    $path = $PSCommandPath.Replace("'", "''")
    $id = $Adapter.InstanceId.Replace("'", "''")
    $command = "& '$path' -Action '$Operation' -AdapterId '$id'"
    $command += '; $code = $LASTEXITCODE; Read-Host ''Press Enter to close''; exit $code'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $shell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $child = Start-Process $shell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) -Wait -PassThru
    if ($child.ExitCode) { throw 'The elevated step failed. Check Status and the message in the elevated window.' }
}

# Dot-sourcing exposes functions for the isolated registry tests.
if ($MyInvocation.InvocationName -eq '.') { return }
$ErrorActionPreference = 'Stop'
try {
    if ($Action -eq 'Status') { Show-Status @(Get-AmdAdapter) | Format-List; exit 0 }
    if ($Action -ne 'Menu') {
        Invoke-Change (Select-Adapter @(Get-AmdAdapter) $AdapterId $Action) $Action
        exit 0
    }
    do {
        Write-Host "`nAMD PSR Cursor Fix"
        Write-Host '1  Status'
        Write-Host '2  Disable PSR on an AMD adapter'
        Write-Host '3  Restore AMD adapter setting'
        Write-Host '0  Exit'
        $choice = Read-Host 'Choose'
        switch ($choice) {
            '1' { Show-Status @(Get-AmdAdapter) | Format-List }
            '2' {
                Write-Host 'On the tested ASUS A16, disabling PSR prevents SmartAccess Graphics from returning to the integrated GPU.'
                $adapter = Select-Adapter @(Get-AmdAdapter) $AdapterId Apply
                if ((Read-Host "Disable PSR on $($adapter.Name)? [y/N]") -eq 'y') { Invoke-Change $adapter Apply }
            }
            '3' { Invoke-Change (Select-Adapter @(Get-AmdAdapter) $AdapterId Restore) Restore }
        }
    } while ($choice -ne '0')
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
