#Requires -Version 5.1
[CmdletBinding()]
param([ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version = '0.1.0')
$ErrorActionPreference = 'Stop'
$destination = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$name = "amd-psr-cursor-fix-$Version"
$zip = Join-Path $destination "$name.zip"
$staging = Join-Path ([IO.Path]::GetTempPath()) ('amd-psr-release-' + [guid]::NewGuid().ToString('N'))
$package = Join-Path $staging $name
New-Item -ItemType Directory -Path $package -Force | Out-Null
try {
    foreach ($item in 'Start.cmd','Fix-Cursor.ps1','ASUS-Extension.cmd','Install-ASUS-Extension.ps1','README.md','LICENSE','CONTRIBUTING.md','src','docs','tests') {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $item) -Destination $package -Recurse
    }
    Compress-Archive -LiteralPath $package -DestinationPath $zip -Force
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $name.zip" | Set-Content -LiteralPath (Join-Path $destination 'SHA256SUMS.txt') -Encoding ASCII
    Write-Host "Created $zip"
} finally {
    $resolved = [IO.Path]::GetFullPath($staging)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (!$resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^amd-psr-release-[0-9a-f]{32}$') { throw 'Unexpected release staging path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
