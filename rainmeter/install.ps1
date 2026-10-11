# Installs the Flying Tulip Rainmeter skin on Windows (the .rmskin of the latest release).
# Usage (PowerShell): irm https://raw.githubusercontent.com/flyingtulipdotcom/ft-desktop-widgets/main/rainmeter/install.ps1 | iex
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$repo = "flyingtulipdotcom/ft-desktop-widgets"
$fallback = "https://github.com/$repo/releases/download/v1.4.0/FlyingTulip-1.4.0.rmskin"
$rainmeter = @("$env:ProgramFiles\Rainmeter\Rainmeter.exe", "${env:ProgramFiles(x86)}\Rainmeter\Rainmeter.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $rainmeter) {
  Write-Host "Rainmeter not found. Install it first from https://www.rainmeter.net, then run this again."
  return
}
$url = $fallback
try {
  $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ "User-Agent" = "ft-desktop-widgets-installer" } -UseBasicParsing
  $asset = $release.assets | Where-Object { $_.name -like "*.rmskin" } | Select-Object -First 1
  if ($asset) { $url = $asset.browser_download_url }
} catch {
  Write-Host "Could not look up the latest release, using v1.4.0."
}
$file = Join-Path $env:TEMP ([IO.Path]::GetFileName(([Uri]$url).AbsolutePath))
Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing
Start-Process $file
Write-Host "Opened the Rainmeter skin installer for $([IO.Path]::GetFileName($file)). Click Install, then click the cog on the skin to add your wallets."
