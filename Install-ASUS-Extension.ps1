#Requires -Version 5.1
[CmdletBinding()]
param([string]$PackageFolder, [switch]$Install)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src\PsrFix.psm1') -Force

try {
    if (!$PackageFolder) { $PackageFolder = Read-Host 'Folder containing the original ASUS amduw23e.inf and its amdpcibridge subfolder' }
    $folder = (Resolve-Path -LiteralPath $PackageFolder).ProviderPath
    $inf = Join-Path $folder 'amduw23e.inf'
    $catalog = Join-Path $folder 'amduw23e.cat'
    $dependency = Join-Path $folder 'amdpcibridge\amdpcibridgeextension.inf'
    $dependencyCatalog = Join-Path $folder 'amdpcibridge\amdpcibridgeextension.cat'
    foreach ($file in $inf,$catalog,$dependency,$dependencyCatalog) {
        if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing original package file $file" }
    }
    $text = Get-Content -LiteralPath $inf -Raw
    if ($text -notmatch '(?im)^\s*Class\s*=\s*Extension\s*$' -or
        $text -notmatch '(?im)^\s*ExtensionId\s*=\s*\{07A2A561-D001-4503-B239-EF2FE0379EFB\}\s*$') {
        throw 'This helper supports the ASUS amduw23e display extension identified in the report.'
    }
    foreach ($file in $catalog,$dependencyCatalog) {
        $signature = Get-AuthenticodeSignature -LiteralPath $file
        if ($signature.Status -ne 'Valid') { throw "Windows could not validate the catalog signature for $file. Status $($signature.Status)." }
    }
    $modelIds = @([regex]::Matches($text, '(?im)^\s*[^;\r\n][^=\r\n]*=\s*[^,\r\n]+,\s*(PCI\\VEN_1002&[^,;\s]+)') | ForEach-Object { $_.Groups[1].Value })
    $matching = @(foreach ($adapter in Get-AmdAdapter) {
        $hardwareIds = (Get-PnpDeviceProperty -InstanceId $adapter.InstanceId -KeyName DEVPKEY_Device_HardwareIds -ErrorAction Stop).Data
        if (@($hardwareIds | Where-Object { $_ -match '&SUBSYS_[0-9A-F]{4}1043' -and $_ -in $modelIds }).Count -gt 0) { $adapter }
    })
    if ($matching.Count -eq 0) { throw 'This package has no matching present ASUS AMD display adapter. Obtain the original package for the laptop model.' }
    $matching | Select-Object Name,DriverVersion | Format-Table | Out-Host
    Write-Host 'Both catalog signatures are valid. Windows verifies package membership and applicability during installation.'
    if (!$Install) { Write-Host 'Package check completed. Use -Install to stage and apply the signed extension.'; exit 0 }

    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $scriptPath = $PSCommandPath.Replace("'", "''")
        $safeFolder = $folder.Replace("'", "''")
        $command = "& '$scriptPath' -PackageFolder '$safeFolder' -Install; " + '$result = $LASTEXITCODE; Read-Host ''Press Enter to close''; exit $result'
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $process = Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) -Wait -PassThru
        exit $process.ExitCode
    }
    $restartRequired = $false
    # The display extension references this dependency through CopyINF.
    foreach ($package in $dependency,$inf) {
        & "$env:SystemRoot\System32\pnputil.exe" /add-driver $package /install | Out-Host
        if ($LASTEXITCODE -eq 3010) { $restartRequired = $true }
        elseif ($LASTEXITCODE -ne 0) { throw "PnPUtil returned $LASTEXITCODE for $package. Earlier successful staging may remain. Review the displayed result." }
    }
    $after = @(Get-AmdAdapter)
    foreach ($adapter in $matching) {
        $current = @($after | Where-Object InstanceId -eq $adapter.InstanceId)
        if ($current.Count -ne 1 -or $current[0].DriverVersion -ne $adapter.DriverVersion) {
            throw 'The base display driver changed during installation. Review the device and driver state.'
        }
        Write-Host "Extension association for $($adapter.Name)"
        & "$env:SystemRoot\System32\pnputil.exe" /enum-devices /instanceid $adapter.InstanceId /drivers | Out-Host
    }
    Write-Host 'Check Extension Driver Names in the output. A staged package can lose selection to a newer extension.'
    if ($restartRequired) { Write-Host 'Windows requests a restart to finish installation.' }
    Write-Host 'After installation, check the PSR setting again with Start.cmd.'
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
