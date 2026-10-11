# Installs the Flying Tulip widget for the Windows 11 Widgets Board from a release of this repository.
#   .\install.ps1                      newest windows-widget release (downloads the .msix and the test certificate)
#   .\install.ps1 -Msix .\x.msix -Cer .\x.cer     use local files
# The test build is signed with a self-signed certificate: this script trusts it for the current machine (needs an
# administrator prompt) and then installs the package. A build signed with a real certificate needs no -Cer.
param([string]$Msix = "", [string]$Cer = "")
$ErrorActionPreference = "Stop"
$repo = "flyingtulipdotcom/ft-desktop-widgets"
if ([Environment]::OSVersion.Version.Build -lt 22000) { throw "The Widgets Board widget needs Windows 11 (build 22000 or newer)." }

if (-not $Msix) {
  $rel = (Invoke-RestMethod "https://api.github.com/repos/$repo/releases?per_page=30" -Headers @{ "User-Agent" = "ft-widget-install" }) |
    Where-Object { $_.tag_name -like "windows-widget-v*" -and -not $_.draft } | Select-Object -First 1
  if (-not $rel) { throw "No windows-widget release found." }
  $tmp = Join-Path $env:TEMP "ft-widget"; New-Item -ItemType Directory -Force $tmp | Out-Null
  foreach ($a in $rel.assets) {
    if ($a.name -like "*.msix") { $Msix = Join-Path $tmp $a.name; Invoke-WebRequest $a.browser_download_url -OutFile $Msix }
    if ($a.name -like "*.cer") { $Cer = Join-Path $tmp $a.name; Invoke-WebRequest $a.browser_download_url -OutFile $Cer }
  }
  Write-Host "Using $($rel.tag_name)"
}

if ($Cer) {
  $self = "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile','-Command',`"Import-Certificate -FilePath '$Cer' -CertStoreLocation Cert:\LocalMachine\TrustedPeople`""
  Write-Host "Trusting the test certificate (administrator prompt)..."
  Invoke-Expression $self
}

# The Windows App Runtime (framework package) the widget depends on
if (-not (Get-AppxPackage -Name "Microsoft.WindowsAppRuntime.1.8" -ErrorAction SilentlyContinue)) {
  Write-Host "Installing the Windows App Runtime 1.8..."
  $rt = Join-Path $env:TEMP "windowsappruntimeinstall-x64.exe"
  Invoke-WebRequest "https://aka.ms/windowsappsdk/1.8/latest/windowsappruntimeinstall-x64.exe" -OutFile $rt
  Start-Process $rt -ArgumentList "--quiet" -Wait
}

Add-AppxPackage -Path $Msix -ForceApplicationShutdown
Write-Host "Installed. Open the Widgets Board (Win+W), choose + and add Flying Tulip."
