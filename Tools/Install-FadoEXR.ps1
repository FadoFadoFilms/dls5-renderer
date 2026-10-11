param([Parameter(Mandatory=$true)][string]$UnityProject)
$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'Assets\FadoEXR'
$project = [IO.Path]::GetFullPath($UnityProject)
if(-not (Test-Path (Join-Path $project 'Assets'))) { throw 'This is not a Unity project: Assets folder missing.' }
if(-not (Test-Path (Join-Path $project 'ProjectSettings'))) { throw 'This is not a Unity project: ProjectSettings missing.' }
$destination = Join-Path $project 'Assets\FadoEXR'
if(Test-Path $destination) { throw 'FadoEXR is already present; refusing to overwrite existing scripts. Back up or remove that folder first.' }
Copy-Item -LiteralPath $source -Destination $destination -Recurse
Write-Host "Copied scripts into $destination"
Write-Host 'Open Unity; use Tools > Fado Fado > EXR Roundtrip after compilation.'
