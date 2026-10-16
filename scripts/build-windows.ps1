# Build Pasty for Windows (release).
# Usage: .\scripts\build-windows.ps1 [version]
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Version = $args[0]
if (-not $Version) {
    $Version = "1.2.0"
}

Write-Host "Building Pasty $Version (Windows x64)…"
cargo build --release -p pasty --manifest-path windows/Cargo.toml

$Dist = Join-Path $Root "dist"
New-Item -ItemType Directory -Force -Path $Dist | Out-Null
$Src = Join-Path $Root "windows\target\release\pasty.exe"
$Dst = Join-Path $Dist "Pasty-$Version-windows-x64.exe"
Copy-Item -Force $Src $Dst
Write-Host "Built $Dst"
