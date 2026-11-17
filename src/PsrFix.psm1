Set-StrictMode -Version Latest
$script:RegistryRoot = [Microsoft.Win32.Registry]::LocalMachine
$script:BackupRoot = 'SOFTWARE\AMDPSRCursorFix\Backups'
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
                Status = $device.Status
            }
        } finally { $key.Dispose() }
    }
}

function Get-PsrValue {
    param([Parameter(Mandatory)]$Adapter)
    $key = $script:RegistryRoot.OpenSubKey($Adapter.RegistryPath)
    if (!$key) { throw 'The selected display adapter registry key no longer exists. Refresh Status.' }
    try {
        $exists = $key.GetValueNames() -contains $script:ValueName
        $kind = $null
        $value = $null
        if ($exists) {
            $kind = $key.GetValueKind($script:ValueName).ToString()
            $value = $key.GetValue($script:ValueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
        [pscustomobject]@{ Exists = $exists; Kind = $kind; Value = $value }
    } finally { $key.Dispose() }
}

function Get-PsrBackupPath {
    param([Parameter(Mandatory)]$Adapter)
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $identity = ($Adapter.InstanceId + '|' + $Adapter.RegistryPath).ToUpperInvariant()
        $digest = [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity))).Replace('-', '')
        return "$script:BackupRoot\$digest"
    } finally { $hash.Dispose() }
}

function Get-PsrBackup {
    param([Parameter(Mandatory)]$Adapter)
    $key = $script:RegistryRoot.OpenSubKey((Get-PsrBackupPath $Adapter))
    if (!$key) { return $null }
    try {
        $json = $key.GetValue('Record', $null)
        if (!$json) { return $null }
        $record = $json | ConvertFrom-Json
        if ($record.Schema -ne 1 -or $record.InstanceId -ne $Adapter.InstanceId -or $record.RegistryPath -ne $Adapter.RegistryPath) {
            throw 'The saved backup does not match this adapter. No setting was written.'
        }
        return $record
    } finally { $key.Dispose() }
}

function Save-PsrBackup {
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)]$Record)
    $key = $script:RegistryRoot.CreateSubKey((Get-PsrBackupPath $Adapter))
    try {
        $key.SetValue('Record', ($Record | ConvertTo-Json -Depth 6 -Compress), [Microsoft.Win32.RegistryValueKind]::String)
        $key.Flush()
    } finally { $key.Dispose() }
}

function Write-PsrValue {
    param([Parameter(Mandatory)]$Adapter, [Parameter(Mandatory)]$Snapshot)
    $key = $script:RegistryRoot.OpenSubKey($Adapter.RegistryPath, $true)
    if (!$key) { throw 'The display adapter registry key is unavailable for writing.' }
    try {
        if (!$Snapshot.Exists) {
            $key.DeleteValue($script:ValueName, $false)
        } else {
            $value = $Snapshot.Value
            switch ($Snapshot.Kind) {
                'DWord' { $value = [int]$value }
                'QWord' { $value = [long]$value }
                'Binary' { $value = [byte[]]@($value) }
                'None' { $value = [byte[]]@($value) }
                'MultiString' { $value = [string[]]@($value) }
                'String' { $value = [string]$value }
                'ExpandString' { $value = [string]$value }
                default { throw "Unsupported saved registry type $($Snapshot.Kind)." }
            }
            $key.SetValue($script:ValueName, $value, [Microsoft.Win32.RegistryValueKind]$Snapshot.Kind)
        }
        $key.Flush()
    } finally { $key.Dispose() }
}

function Set-PsrPolicy {
    param(
        [Parameter(Mandatory)]$Adapter,
        [Parameter(Mandatory)][ValidateSet('Apply', 'Restore', 'Default')][string]$Action
    )
    # One machine-wide transaction protects the original value from concurrent launches.
    $mutex = [Threading.Mutex]::new($false, 'Global\AMDPSRCursorFix')
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(10000) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (!$locked) { throw 'Another fix operation is running. Try again when it finishes.' }
        $current = Get-PsrValue $Adapter
        $record = Get-PsrBackup $Adapter
        if ($Action -eq 'Restore') {
            if (!$record -or $record.State -eq 'Restored') {
                return [pscustomobject]@{ Changed = $false; Message = 'No pending backup for this adapter and driver key. Use Default only if you intend to remove the override.' }
            }
            Write-PsrValue $Adapter $record.Original
            $restored = Get-PsrValue $Adapter
            if ($restored.Exists -ne $record.Original.Exists -or $restored.Kind -ne $record.Original.Kind -or
                ($restored.Value | ConvertTo-Json -Compress) -ne ($record.Original.Value | ConvertTo-Json -Compress)) {
                throw 'Restore verification failed. The original backup is retained for another attempt.'
            }
            $record.State = 'Restored'
            Save-PsrBackup $Adapter $record
            return [pscustomobject]@{ Changed = $true; Message = 'The original registry value and type have been restored.' }
        }
        if (!$record -or $record.State -eq 'Restored') {
            $record = [pscustomobject]@{
                Schema = 1
                InstanceId = $Adapter.InstanceId
                RegistryPath = $Adapter.RegistryPath
                DriverVersion = $Adapter.DriverVersion
                CreatedUtc = [DateTime]::UtcNow.ToString('o')
                Original = $current
                State = 'Prepared'
            }
            Save-PsrBackup $Adapter $record
        }
        if ($Action -eq 'Apply') {
            Write-PsrValue $Adapter ([pscustomobject]@{ Exists = $true; Kind = 'DWord'; Value = 0 })
            $actual = Get-PsrValue $Adapter
            if (!$actual.Exists -or $actual.Kind -ne 'DWord' -or $actual.Value -ne 0) { throw 'Registry verification failed. The original backup is available for Restore.' }
            $message = 'PSR-disable override is set. Activate it with a display-device restart or Windows restart.'
        } else {
            Write-PsrValue $Adapter ([pscustomobject]@{ Exists = $false; Kind = $null; Value = $null })
            if ((Get-PsrValue $Adapter).Exists) { throw 'The override could not be removed. The original backup is retained.' }
            $message = 'The override is removed. Activate the driver default with a display-device restart or Windows restart.'
        }
        $record.State = 'Applied'
        Save-PsrBackup $Adapter $record
        return [pscustomobject]@{ Changed = $true; Message = $message }
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Restart-PsrAdapter {
    param([Parameter(Mandatory)]$Adapter)
    & "$env:SystemRoot\System32\pnputil.exe" /restart-device $Adapter.InstanceId | Out-Host
    if ($LASTEXITCODE -eq 3010) { return 'Windows requires a restart to finish activating the setting.' }
    if ($LASTEXITCODE -ne 0) { throw "PnPUtil returned $LASTEXITCODE. The setting and backup are saved. Restart Windows to activate it." }
    return 'Display-device restart completed. Test the original cursor with the affected mouse.'
}

function Get-PsrStatus {
    foreach ($adapter in Get-AmdAdapter) {
        $value = Get-PsrValue $adapter
        $policy = 'Driver default (value absent)'
        if ($value.Exists) {
            $policy = "Existing $($value.Kind) value $($value.Value)"
            if ($value.Kind -eq 'DWord' -and $value.Value -eq 0) { $policy = 'PSR-disable override set' }
        }
        $record = Get-PsrBackup $adapter
        $backupState = 'None'
        if ($record) { $backupState = $record.State }
        [pscustomobject]@{ GPU = $adapter.Name; Driver = $adapter.DriverVersion; DeviceStatus = $adapter.Status; Policy = $policy; Backup = $backupState; AdapterId = $adapter.InstanceId }
    }
}

Export-ModuleMember -Function Get-AmdAdapter, Get-PsrStatus, Get-PsrValue, Get-PsrBackup, Set-PsrPolicy, Restart-PsrAdapter
