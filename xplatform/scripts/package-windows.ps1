# Build the Windows desktop release and produce an Inno Setup installer.
# Run from anywhere; works against the xplatform tree this script lives in.
#
# Usage:
#   .\scripts\package-windows.ps1                 # uses version from pubspec
#   .\scripts\package-windows.ps1 -Version 1.2.0  # override

[CmdletBinding()]
param(
  [string]$Version
)

$ErrorActionPreference = "Stop"
function Say($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

$xplatform = Resolve-Path (Join-Path $PSScriptRoot "..")
$flutter   = Join-Path $env:USERPROFILE "flutter\bin\flutter.bat"
$iscc      = Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"

if (-not (Test-Path $flutter)) { throw "Flutter not found at $flutter. Run scripts\setup-windows-vm.ps1 first." }
if (-not (Test-Path $iscc))    { throw "Inno Setup not found at $iscc. Install with: winget install JRSoftware.InnoSetup" }

if (-not $Version) {
  $pubspec = Get-Content (Join-Path $xplatform "pubspec.yaml") -Raw
  if ($pubspec -match '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
    $Version = $matches[1]
  } else {
    throw "Could not read version from pubspec.yaml. Pass -Version explicitly."
  }
}

Say "Building Palimpsest $Version for Windows x64"
& $flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build failed" }

$dist = Join-Path $xplatform "dist"
New-Item -ItemType Directory -Force $dist | Out-Null

Say "Compiling installer with Inno Setup"
$iss = Join-Path $xplatform "installer\palimpsest.iss"
& $iscc "/DAppVersion=$Version" $iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compile failed" }

$output = Join-Path $dist "palimpsest-$Version-windows-x64.exe"
if (-not (Test-Path $output)) { throw "Expected installer not found: $output" }

Say "Done"
Write-Host "Installer: $output" -ForegroundColor Green
Write-Host "Size:      $([math]::Round((Get-Item $output).Length / 1MB, 1)) MB" -ForegroundColor Green
