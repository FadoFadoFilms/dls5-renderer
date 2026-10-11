# Backward-compatible command line installer wrapper. Prefer the manager GUI.
# Run: .\Tools\Install-FadoEXR.ps1 -UnityProject 'D:\MyUnityFilm' -Role Export
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$UnityProject,
    [ValidateSet('Export','Import')][string]$Role='Export'
)
$ErrorActionPreference='Stop'
$root = Split-Path $PSScriptRoot -Parent
$manager = Join-Path $root 'Manager\fadoexr_manager.py'
if(-not (Test-Path -LiteralPath $manager -PathType Leaf)) { throw 'Manager source missing from repository.' }
$python = Get-Command py -ErrorAction SilentlyContinue
if($null -ne $python) {
    & $python.Source -3 $manager install $Role.ToLowerInvariant() $UnityProject
} else {
    $python = Get-Command python -ErrorAction Stop
    & $python.Source $manager install $Role.ToLowerInvariant() $UnityProject
}
if($LASTEXITCODE -ne 0) { throw 'Unity package update failed; read manager output.' }
