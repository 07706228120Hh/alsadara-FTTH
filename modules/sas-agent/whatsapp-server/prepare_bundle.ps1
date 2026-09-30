# ============================================================
#  prepare_bundle.ps1 - prepares the WhatsApp server to ship with the installer.
#
#  What it does (run ONCE on the build machine, not the user's machine):
#   1) Downloads portable Node (win-x64) into whatsapp-server\runtime\ if missing.
#   2) Installs production dependencies, skipping the Chromium download
#      (we use the system Edge/Chrome at runtime instead).
#
#  Afterwards the whatsapp-server folder is ready to be packaged by aluklaa.iss.
#  Run:  powershell -ExecutionPolicy Bypass -File prepare_bundle.ps1
#
#  NOTE: keep this file ASCII-only (Windows PowerShell 5.1 reads .ps1 as ANSI).
# ============================================================
param([string]$NodeVersion = "v20.18.0")

$ErrorActionPreference = "Stop"
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtime = Join-Path $here "runtime"
$nodeExe = Join-Path $runtime "node.exe"

if (-not (Test-Path $nodeExe)) {
  $zipName = "node-$NodeVersion-win-x64"
  $url     = "https://nodejs.org/dist/$NodeVersion/$zipName.zip"
  $tmpZip  = Join-Path $env:TEMP "$zipName.zip"
  $tmpDir  = Join-Path $env:TEMP "aluklaa-node"

  Write-Host "[1/2] Downloading portable Node $NodeVersion ..."
  Invoke-WebRequest -Uri $url -OutFile $tmpZip
  if (Test-Path $tmpDir) { Remove-Item -Recurse -Force $tmpDir }
  Expand-Archive -Path $tmpZip -DestinationPath $tmpDir
  New-Item -ItemType Directory -Force -Path $runtime | Out-Null
  Copy-Item -Recurse -Force (Join-Path $tmpDir "$zipName\*") $runtime
  Remove-Item -Force $tmpZip
  Write-Host "      Node runtime ready at $runtime"
} else {
  Write-Host "[1/2] Portable Node already present - skipping download."
}

Write-Host "[2/2] Installing production dependencies (Chromium download skipped) ..."
$env:PUPPETEER_SKIP_DOWNLOAD = "true"
$env:PUPPETEER_SKIP_CHROMIUM_DOWNLOAD = "true"
$npmCli = Join-Path $runtime "node_modules\npm\bin\npm-cli.js"
Push-Location $here
try {
  & $nodeExe $npmCli install --omit=dev --no-audit --no-fund
} finally {
  Pop-Location
}

Write-Host ""
Write-Host "Bundle ready. The whatsapp-server folder can now be shipped by the installer."
Write-Host "It uses the system Edge/Chrome at runtime (no Chromium download)."
