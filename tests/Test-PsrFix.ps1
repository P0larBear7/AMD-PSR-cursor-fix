# Tests use an isolated HKCU subtree. Display hardware is never restarted.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\PsrFix.psm1') -Force
$testPath = 'Software\AMDPSRCursorFix-Tests-' + [guid]::NewGuid().ToString('N')
$root = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($testPath)
$module = Get-Module PsrFix
& $module { param($Root) $script:RegistryRoot = $Root } $root
$adapter = [pscustomobject]@{ Name='Test AMD'; InstanceId='PCI\VEN_1002&DEV_TEST\ONE'; RegistryPath='TestDisplay\0001'; DriverVersion='1.0' }
$key = $root.CreateSubKey($adapter.RegistryPath)
$key.Dispose()
$count = 0
function Assert-True($Condition, $Message) {
    if (!$Condition) { throw $Message }
    $script:count++
}
try {
    Set-PsrPolicy $adapter Apply | Out-Null
    Assert-True ((Get-PsrValue $adapter).Value -eq 0) 'Apply did not write zero.'
    Set-PsrPolicy $adapter Apply | Out-Null
    Assert-True (!(Get-PsrBackup $adapter).Original.Exists) 'Repeated Apply replaced the original absent-value backup.'
    Set-PsrPolicy $adapter Restore | Out-Null
    Assert-True (!(Get-PsrValue $adapter).Exists) 'Restore did not remove a previously absent value.'
    Assert-True (!(Set-PsrPolicy $adapter Restore).Changed) 'Repeated Restore should be a no-op.'

    $cases = @(
        @{ Kind='DWord'; Value=7 },
        @{ Kind='DWord'; Value=0 },
        @{ Kind='QWord'; Value=[long]9223372036854775806 },
        @{ Kind='Binary'; Value=[byte[]](0,127,255) },
        @{ Kind='Binary'; Value=[byte[]]@() },
        @{ Kind='String'; Value='original' },
        @{ Kind='ExpandString'; Value='%SystemRoot%\literal' },
        @{ Kind='MultiString'; Value=[string[]]('a','b') }
    )
    foreach ($case in $cases) {
        $key = $root.OpenSubKey($adapter.RegistryPath,$true)
        $key.SetValue('DalPSRFeatureEnable',$case.Value,[Microsoft.Win32.RegistryValueKind]$case.Kind)
        $key.Dispose()
        Set-PsrPolicy $adapter Apply | Out-Null
        Set-PsrPolicy $adapter Restore | Out-Null
        $result = Get-PsrValue $adapter
        Assert-True ($result.Kind -eq $case.Kind) "Wrong restored type for $($case.Kind)."
        Assert-True (($result.Value | ConvertTo-Json -Compress) -eq ($case.Value | ConvertTo-Json -Compress)) "Wrong restored data for $($case.Kind)."
    }
    Set-PsrPolicy $adapter Default | Out-Null
    Assert-True (!(Get-PsrValue $adapter).Exists) 'Default failed to remove override.'
    Set-PsrPolicy $adapter Restore | Out-Null
    Assert-True ((Get-PsrValue $adapter).Kind -eq 'MultiString') 'Default could not be undone.'

    # Simulate a stopped process after journaling the original value.
    Set-PsrPolicy $adapter Apply | Out-Null
    & $module {
        param($Adapter)
        $record = Get-PsrBackup $Adapter
        $record.State = 'Prepared'
        Save-PsrBackup $Adapter $record
    } $adapter
    Set-PsrPolicy $adapter Apply | Out-Null
    Set-PsrPolicy $adapter Restore | Out-Null
    Assert-True ((Get-PsrValue $adapter).Kind -eq 'MultiString') 'Retry after interruption overwrote original data.'

    $second = [pscustomobject]@{ Name='Other'; InstanceId='PCI\VEN_1002&DEV_TEST\TWO'; RegistryPath='TestDisplay\0002'; DriverVersion='2.0' }
    $key = $root.CreateSubKey($second.RegistryPath)
    $key.Dispose()
    Assert-True ($null -eq (Get-PsrBackup $second)) 'Backup leaked across adapters.'
    Set-PsrPolicy $second Apply | Out-Null
    Assert-True ((Get-PsrValue $adapter).Kind -eq 'MultiString') 'Applying another adapter changed the first.'
    Write-Host "Passed $count registry lifecycle assertions."
} finally {
    & $module { $script:RegistryRoot = [Microsoft.Win32.Registry]::LocalMachine }
    $root.Dispose()
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($testPath,$false)
}
