# Installs the Flying Tulip Rainmeter skin on Windows.
# Usage (PowerShell): irm https://raw.githubusercontent.com/flyingtulipdotcom/ft-desktop-widgets/main/rainmeter/install.ps1 | iex
$ErrorActionPreference = "Stop"
$url = "https://github.com/flyingtulipdotcom/ft-desktop-widgets/releases/download/v1.0.0/FlyingTulip-1.0.0.rmskin"
$rainmeter = @("$env:ProgramFiles\Rainmeter\Rainmeter.exe", "${env:ProgramFiles(x86)}\Rainmeter\Rainmeter.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $rainmeter) {
  Write-Host "Rainmeter not found. Install it first from https://www.rainmeter.net, then run this again."
  return
}
$file = Join-Path $env:TEMP "FlyingTulip-1.0.0.rmskin"
Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing
Start-Process $file
Write-Host "Opened the Rainmeter skin installer. Click Install, then right-click the skin to set your wallet."
