# Bootstrap a Windows 10/11 VM for building Ink and Echo (Flutter Windows
# desktop). Idempotent. Run from an *elevated* PowerShell prompt inside
# the VM (right-click PowerShell -> Run as administrator).
#
# Usage:
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   .\setup-windows-vm.ps1

$ErrorActionPreference = "Stop"

function Say($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

# --- winget bootstrap (App Installer ships with Win11; on Win10 install
# manually from the Store if missing). -----------------------------------
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  throw "winget not found. Install 'App Installer' from the Microsoft Store, then re-run."
}

Say "Installing Git, ffmpeg, Visual Studio Build Tools (C++ workload)"
winget install --silent --accept-source-agreements --accept-package-agreements -e --id Git.Git
winget install --silent --accept-source-agreements --accept-package-agreements -e --id Gyan.FFmpeg
winget install --silent --accept-source-agreements --accept-package-agreements -e --id Microsoft.VisualStudio.2022.BuildTools `
  --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"

# --- Flutter SDK ---------------------------------------------------------
$flutterRoot = "$env:USERPROFILE\flutter"
if (-not (Test-Path $flutterRoot)) {
  Say "Cloning Flutter stable into $flutterRoot"
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git $flutterRoot
} else {
  Say "Flutter already present at $flutterRoot - pulling latest"
  git -C $flutterRoot pull --ff-only
}

# --- PATH ---------------------------------------------------------------
$flutterBin = "$flutterRoot\bin"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$flutterBin*") {
  Say "Adding Flutter to user PATH"
  [Environment]::SetEnvironmentVariable("Path", "$userPath;$flutterBin", "User")
}
$env:Path = "$env:Path;$flutterBin"

# --- Enable Windows desktop & verify ------------------------------------
Say "Enabling Windows desktop"
flutter config --enable-windows-desktop --no-analytics

Say "Running flutter doctor"
flutter doctor -v

Write-Host @"

Setup complete. Next:

  1) Get the source into the VM. Either:
       git clone <repo>
     or use the UTM shared-folder feature.
  2) cd into the xplatform directory.
  3) flutter pub get
  4) flutter run -d windows            # interactive
       or
     flutter build windows             # produces build\windows\runner\Release\

If 'flutter doctor' flags Visual Studio as missing, reboot the VM once
(the installer registers Build Tools system-wide after a restart).
"@ -ForegroundColor Green
