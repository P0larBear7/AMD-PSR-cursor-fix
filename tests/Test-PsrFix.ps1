# Tests use an isolated HKCU subtree and do not restart display devices.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\Fix-Cursor.ps1')
$testPath = 'Software\AMDPSRCursorFix-Tests-' + [guid]::NewGuid().ToString('N')
$root = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($testPath)
$script:RegistryRoot = $root
$rx = [pscustomobject]@{ Name='RX'; InstanceId='PCI\VEN_1002&DEV_7480&SUBSYS_15131043&REV_C1\ONE'; RegistryPath='Display\0001' }
$igpu = [pscustomobject]@{ Name='iGPU'; InstanceId='PCI\VEN_1002&DEV_1681&SUBSYS_15131043&REV_0A\TWO'; RegistryPath='Display\0000' }
$rxKey = $root.CreateSubKey($rx.RegistryPath)
$iGpuKey = $root.CreateSubKey($igpu.RegistryPath)

function Assert-True($Condition, $Message) { if (!$Condition) { throw $Message } }
function Get-CimInstance { param($ClassName, $ErrorAction) [pscustomobject]@{ Model='ASUS TUF Gaming A16 FA617NT_FA617NT' } }
function Get-Saved($Adapter) {
    $journal = $root.OpenSubKey((Get-BackupPath $Adapter))
    try { Read-Backup $Adapter $journal } finally { if ($journal) { $journal.Dispose() } }
}

try {
    Assert-True ((Select-Adapter @($igpu, $rx) '' Apply) -eq $rx) 'Apply must select only the RX 7700S on this A16.'
    $refused = $false
    try { Select-Adapter @($igpu, $rx) $igpu.InstanceId Apply | Out-Null } catch { $refused = $true }
    Assert-True $refused 'The integrated GPU should be unavailable for Apply.'
    Assert-True ((Select-Adapter @($igpu, $rx) $igpu.InstanceId Restore) -eq $igpu) 'Restore must still allow repair of the integrated GPU.'

    Set-PsrPolicy $rx Apply | Out-Null
    Assert-True ((Get-PsrValue $rxKey).Value -eq 0) 'Apply did not write zero.'
    Set-PsrPolicy $rx Apply | Out-Null
    Assert-True (!(Get-Saved $rx).Original.Exists) 'Repeat Apply replaced the backup.'
    Assert-True (!(Get-PsrValue $iGpuKey).Exists) 'Apply changed the other adapter.'
    Set-PsrPolicy $rx Restore | Out-Null
    Assert-True (!(Get-PsrValue $rxKey).Exists) 'Restore must delete a previously absent value.'
    Assert-True ((Get-Saved $rx).State -eq 'Restored') 'Restore should close the transaction.'

    $rxKey.SetValue('DalPSRFeatureEnable', 7, [Microsoft.Win32.RegistryValueKind]::DWord)
    Set-PsrPolicy $rx Apply | Out-Null
    $journal = $root.OpenSubKey((Get-BackupPath $rx), $true)
    $backup = Read-Backup $rx $journal
    $backup.State = 'Prepared'
    $journal.SetValue('Record', ($backup | ConvertTo-Json -Compress -Depth 4))
    $journal.Dispose()
    Set-PsrPolicy $rx Apply | Out-Null
    Set-PsrPolicy $rx Restore | Out-Null
    Assert-True ((Get-PsrValue $rxKey).Value -eq 7) 'Retry from Prepared lost the original DWORD.'

    $rxKey.SetValue('DalPSRFeatureEnable', 'unexpected')
    $refused = $false
    try { Set-PsrPolicy $rx Apply | Out-Null } catch { $refused = $true }
    Assert-True ($refused -and (Get-PsrValue $rxKey).Value -eq 'unexpected') 'Apply must preserve an unexpected existing type.'

    # An existing v1 backup must remain usable after replacing the old tool.
    $iGpuKey.SetValue('DalPSRFeatureEnable', 0, [Microsoft.Win32.RegistryValueKind]::DWord)
    $journal = $root.CreateSubKey((Get-BackupPath $igpu))
    $legacy = @{ Schema=1; InstanceId=$igpu.InstanceId; RegistryPath=$igpu.RegistryPath; State='Applied'; Original=@{ Exists=$true; Kind='Binary'; Value=@(0,127,255) } }
    $journal.SetValue('Record', ($legacy | ConvertTo-Json -Compress -Depth 4))
    $journal.Dispose()
    Set-PsrPolicy $igpu Restore | Out-Null
    $value = Get-PsrValue $iGpuKey
    Assert-True ($value.Kind -eq 'Binary' -and ($value.Value -join ',') -eq '0,127,255') 'The v1 backup was not restored.'
    Write-Host 'Adapter selection and registry restore checks passed.'
} finally {
    $iGpuKey.Dispose()
    $rxKey.Dispose()
    $root.Dispose()
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($testPath, $false)
}
