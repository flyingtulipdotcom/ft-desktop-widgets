# Builds the MSIX of the Windows 11 widget from a published folder (makeappx + signtool, both in the Windows SDK).
#   -Publish   folder made by `dotnet publish` of FlyingTulip.Widget.Provider
#   -Shot      PNG used as the widget's picker screenshot
#   -OutDir    where FlyingTulipWidget.msix (and, for the test certificate, the .cer) go
#   -Pfx / -PfxPassword   sign with this certificate; its subject becomes the package publisher.
#                         Without them a self-signed test certificate is made (CN=Flying Tulip widget test) and its .cer is
#                         written next to the package so testers can trust it.
param(
  [Parameter(Mandatory)][string]$Publish,
  [Parameter(Mandatory)][string]$Shot,
  [Parameter(Mandatory)][string]$OutDir,
  [string]$Version = "1.0.0.0",
  [string]$Pfx = "",
  [string]$PfxPassword = "",
  [string]$MsixName = "FlyingTulipWidget.msix"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# --- signing certificate -------------------------------------------------------------------------------------------
if ($Pfx) {
  $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($Pfx, $PfxPassword)
  $publisher = $cert.Subject
  $pfxPath = $Pfx; $pfxPass = $PfxPassword
} else {
  $publisher = "CN=Flying Tulip widget test"
  $cert = New-SelfSignedCertificate -Type Custom -Subject $publisher -KeyUsage DigitalSignature -KeyAlgorithm RSA -KeyLength 2048 `
    -FriendlyName "Flying Tulip widget test" -CertStoreLocation "Cert:\CurrentUser\My" -NotAfter (Get-Date).AddYears(2) `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")
  $pfxPass = [guid]::NewGuid().ToString("N")
  $pfxPath = Join-Path $env:RUNNER_TEMP "ft-widget-test.pfx"
  if (-not $env:RUNNER_TEMP) { $pfxPath = Join-Path ([IO.Path]::GetTempPath()) "ft-widget-test.pfx" }
  Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password (ConvertTo-SecureString $pfxPass -AsPlainText -Force) | Out-Null
  Export-Certificate -Cert $cert -FilePath (Join-Path $OutDir "FlyingTulipWidget-test.cer") | Out-Null
}

# --- layout --------------------------------------------------------------------------------------------------------
$layout = Join-Path ([IO.Path]::GetTempPath()) ("ftw-layout-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $layout | Out-Null
Copy-Item -Path (Join-Path $Publish "*") -Destination $layout -Recurse -Force
New-Item -ItemType Directory -Force -Path (Join-Path $layout "Assets"), (Join-Path $layout "ProviderAssets") | Out-Null

Add-Type -AssemblyName System.Drawing
$logo = [System.Drawing.Image]::FromFile((Join-Path $root "src\FlyingTulip.Widget.Core\Assets\logo.png"))
function Save-Scaled($img, $size, $path) {
  $bmp = New-Object System.Drawing.Bitmap $size, $size
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($img, 0, 0, $size, $size); $g.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}
Save-Scaled $logo 50 (Join-Path $layout "Assets\StoreLogo.png")
Save-Scaled $logo 150 (Join-Path $layout "Assets\Square150x150Logo.png")
Save-Scaled $logo 44 (Join-Path $layout "Assets\Square44x44Logo.png")
Save-Scaled $logo 64 (Join-Path $layout "ProviderAssets\Icon.png")
$logo.Dispose()
Copy-Item $Shot (Join-Path $layout "ProviderAssets\Screenshot.png")

$manifest = Get-Content (Join-Path $root "package\AppxManifest.xml") -Raw
$manifest = $manifest.Replace("{{PUBLISHER}}", [System.Security.SecurityElement]::Escape($publisher)).Replace("{{VERSION}}", $Version)
[IO.File]::WriteAllText((Join-Path $layout "AppxManifest.xml"), $manifest, (New-Object System.Text.UTF8Encoding($false)))

# --- pack and sign ---------------------------------------------------------------------------------------------------
$kit = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin\10.*\x64\makeappx.exe" -ErrorAction SilentlyContinue |
  Sort-Object { [version]($_.Directory.Parent.Name) } -Descending | Select-Object -First 1
if (-not $kit) { throw "makeappx.exe not found (Windows SDK)" }
$makeappx = $kit.FullName; $signtool = Join-Path $kit.DirectoryName "signtool.exe"
$msix = Join-Path $OutDir $MsixName
if (Test-Path $msix) { Remove-Item $msix }
& $makeappx pack /d $layout /p $msix /o | Write-Host
if ($LASTEXITCODE -ne 0) { throw "makeappx failed ($LASTEXITCODE)" }
& $signtool sign /fd SHA256 /f $pfxPath /p $pfxPass $msix | Write-Host
if ($LASTEXITCODE -ne 0) { throw "signtool failed ($LASTEXITCODE)" }
Remove-Item -Recurse -Force $layout
if (-not $Pfx) { Remove-Item -Force $pfxPath -ErrorAction SilentlyContinue }
Write-Host "wrote $msix (publisher $publisher)"
