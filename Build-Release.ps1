#Requires -Version 5.1
[CmdletBinding()]
param([ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version = '0.1.0')
$ErrorActionPreference = 'Stop'
$destination = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$name = "amd-psr-cursor-fix-$Version"
$zip = Join-Path $destination "$name.zip"
$files = foreach ($item in 'Start.cmd','Fix-Cursor.ps1','LICENSE') { Join-Path $PSScriptRoot $item }
Compress-Archive -LiteralPath $files -DestinationPath $zip -Force
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $name.zip" | Set-Content -LiteralPath (Join-Path $destination 'SHA256SUMS.txt') -Encoding ASCII
Write-Host "Created $zip"
