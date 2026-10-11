# Installs the Flying Tulip widget on Windows.
#   Windows 11 with the Widgets Board: the native Widgets Board widget (newest windows-widget-v* release).
#   Anything else, or if any step fails: the Rainmeter skin (the .rmskin of the newest release that has one).
# Usage (PowerShell): irm https://raw.githubusercontent.com/flyingtulipdotcom/ft-desktop-widgets/main/rainmeter/install.ps1 | iex
# Choose by hand:     $env:FT_WIDGET = "native"  (or "rainmeter")  before running. Default is "auto".
#   native    force the Widgets Board widget, skip the detection, and fail instead of falling back.
#   rainmeter force the Rainmeter skin.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$repo = "flyingtulipdotcom/ft-desktop-widgets"
$releasesUrl = if ($env:FT_RELEASES_URL) { $env:FT_RELEASES_URL } else { "https://api.github.com/repos/$repo/releases?per_page=100" }
$ftWidget = if ($env:FT_WIDGET) { $env:FT_WIDGET.Trim().ToLower() } else { "auto" }
$headers = @{ "User-Agent" = "ft-desktop-widgets-installer" }

function Install-Rainmeter {
  $fallback = "https://github.com/$repo/releases/download/v1.4.0/FlyingTulip-1.4.0.rmskin"
  $rainmeter = @("$env:ProgramFiles\Rainmeter\Rainmeter.exe", "${env:ProgramFiles(x86)}\Rainmeter\Rainmeter.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $rainmeter) {
    Write-Host "Rainmeter not found. Install it first from https://www.rainmeter.net, then run this again."
    return
  }
  $url = $fallback
  try {
    # the newest release that carries a .rmskin (the repository also publishes other apps' releases)
    $releases = Invoke-RestMethod -Uri $releasesUrl -Headers $headers -UseBasicParsing
    foreach ($release in $releases) {
      if ($release.draft -or $release.prerelease) { continue }
      $asset = $release.assets | Where-Object { $_.name -like "*.rmskin" } | Select-Object -First 1
      if ($asset) { $url = $asset.browser_download_url; break }
    }
  } catch {
    Write-Host "Could not look up the latest release, using v1.4.0."
  }
  $file = Join-Path $env:TEMP ([IO.Path]::GetFileName(([Uri]$url).AbsolutePath))
  Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing
  Start-Process $file
  Write-Host "Opened the Rainmeter skin installer for $([IO.Path]::GetFileName($file)). Click Install, then click the cog on the skin to add your wallets."
}

# Why the native widget cannot be used here, or $null when it can.
function Get-NativeBlocker {
  $build = [Environment]::OSVersion.Version.Build
  if ($build -lt 22000) { return "this is Windows 10 or older (the Widgets Board needs Windows 11, build 22000+, this is build $build)" }
  $os = Get-CimInstance Win32_OperatingSystem
  if ($os.ProductType -ne 1) { return "this is Windows Server ($($os.Caption)), which has no Widgets Board" }
  if (-not (Get-AppxPackage -Name MicrosoftWindows.Client.WebExperience -ErrorAction SilentlyContinue)) { return "the Widgets Board is not installed (Windows Web Experience Pack missing)" }
  return $null
}

function Test-Admin {
  ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# A checksum mismatch is not a reason to fall back to anything: it stops the whole install.
function Stop-Mismatch([string]$what) {
  throw (New-Object System.Security.SecurityException "Checksum mismatch for $what. Nothing was installed. Try again later, and report it if it keeps happening.")
}

# Downloads the newest windows-widget-v* release, verifies it, and installs it. Throws a plain message when it cannot.
function Install-Native {
  $releases = Invoke-RestMethod -Uri $releasesUrl -Headers $headers -UseBasicParsing
  $rel = $releases |
    Where-Object { $_.tag_name -match '^windows-widget-v(\d+\.\d+\.\d+)$' -and -not $_.draft -and -not $_.prerelease -and
                   ($_.assets | Where-Object { $_.name -like "*.msix" }) -and ($_.assets | Where-Object { $_.name -like "*.cer" }) } |
    Sort-Object { [version]($_.tag_name -replace '^windows-widget-v', '') } -Descending | Select-Object -First 1
  if (-not $rel) { throw "no windows-widget release with an .msix and a .cer was found" }
  $ver = ($rel.tag_name -replace '^windows-widget-v', '')
  $msixAsset = $rel.assets | Where-Object { $_.name -like "*.msix" } | Select-Object -First 1
  $cerAsset = $rel.assets | Where-Object { $_.name -like "*.cer" } | Select-Object -First 1
  $sumsAsset = $rel.assets | Where-Object { $_.name -eq "SHA256SUMS" } | Select-Object -First 1
  Write-Host "Flying Tulip Widgets Board widget $ver ($($rel.tag_name))"

  $installed = Get-AppxPackage -Name FlyingTulip.WindowsWidget -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($installed -and ([version]$installed.Version) -ge ([version]"$ver.0")) {
    Write-Host "Already installed and up to date ($($installed.Version))."
    Write-Host "Add it with Win+W, Add widgets, Flying Tulip."
    return
  }

  $tmp = Join-Path $env:TEMP ("ft-widget-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
  New-Item -ItemType Directory -Force $tmp | Out-Null
  try {
    $msix = Join-Path $tmp $msixAsset.name
    $cer = Join-Path $tmp $cerAsset.name
    Invoke-WebRequest $msixAsset.browser_download_url -OutFile $msix -UseBasicParsing
    Invoke-WebRequest $cerAsset.browser_download_url -OutFile $cer -UseBasicParsing

    # Expected hashes: the release's SHA256SUMS, else the digest GitHub publishes for each asset.
    $expected = @{}
    if ($sumsAsset) {
      $sumsFile = Join-Path $tmp "SHA256SUMS"
      Invoke-WebRequest $sumsAsset.browser_download_url -OutFile $sumsFile -UseBasicParsing
      foreach ($line in Get-Content $sumsFile) {
        if ($line -match '^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$') { $expected[$Matches[2]] = $Matches[1].ToLower() }
      }
    } else {
      foreach ($a in @($msixAsset, $cerAsset)) {
        if ($a.digest -match '^sha256:([0-9a-fA-F]{64})$') { $expected[$a.name] = $Matches[1].ToLower() }
      }
    }
    foreach ($f in @($msix, $cer)) {
      $name = [IO.Path]::GetFileName($f)
      if (-not $expected.ContainsKey($name)) { throw "the release publishes no checksum for $name" }
      if ((Get-FileHash $f -Algorithm SHA256).Hash.ToLower() -ne $expected[$name]) { Stop-Mismatch $name }
    }
    Write-Host "Checksums verified (sha256)."

    # The package must be signed by the certificate we are about to trust.
    $cerObj = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $cer
    $sig = Get-AuthenticodeSignature -FilePath $msix -ErrorAction SilentlyContinue
    if ($sig -and $sig.SignerCertificate -and $sig.SignerCertificate.Thumbprint -ne $cerObj.Thumbprint) { Stop-Mismatch "the package signature (it is not signed by the published certificate)" }

    # Trust the self-signed test certificate (machine-wide Trusted People store, needs an administrator).
    if (-not (Test-Path "Cert:\LocalMachine\TrustedPeople\$($cerObj.Thumbprint)")) {
      Write-Host "This build is signed with a self-signed certificate. Trusting it needs ONE administrator prompt (it adds the certificate to this PC's Trusted People store, nothing else)."
      $imp = "Import-Certificate -FilePath '$cer' -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null"
      if (Test-Admin) {
        Invoke-Expression $imp
      } else {
        try {
          Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList "-NoProfile", "-Command", $imp
        } catch {
          throw "the administrator prompt was declined. To do it yourself, run in an administrator PowerShell: Import-Certificate -FilePath '$cer' -CertStoreLocation Cert:\LocalMachine\TrustedPeople"
        }
      }
      if (-not (Test-Path "Cert:\LocalMachine\TrustedPeople\$($cerObj.Thumbprint)")) { throw "the certificate was not trusted (no administrator rights)" }
    }

    # The Windows App Runtime the widget depends on.
    if (-not (Get-AppxPackage -Name "Microsoft.WindowsAppRuntime.1.8" -ErrorAction SilentlyContinue)) {
      Write-Host "Installing the Windows App Runtime 1.8 (from Microsoft)..."
      $rt = Join-Path $tmp "windowsappruntimeinstall-x64.exe"
      Invoke-WebRequest "https://aka.ms/windowsappsdk/1.8/latest/windowsappruntimeinstall-x64.exe" -OutFile $rt -UseBasicParsing
      $rs = Get-AuthenticodeSignature $rt
      if ($rs.Status -ne "Valid" -or $rs.SignerCertificate.Subject -notmatch "Microsoft Corporation") { throw "the Windows App Runtime installer is not validly signed by Microsoft" }
      $p = Start-Process $rt -ArgumentList "--quiet" -Wait -PassThru
      if ($p.ExitCode -ne 0) { throw "the Windows App Runtime installer failed (exit code $($p.ExitCode))" }
    }

    Add-AppxPackage -Path $msix -ForceApplicationShutdown
    $now = Get-AppxPackage -Name FlyingTulip.WindowsWidget -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $now) { throw "Add-AppxPackage finished but the package is not installed" }
    Write-Host "Installed $($now.PackageFullName)."
    Write-Host "Add it: press Win+W, Add widgets (+), Flying Tulip. Set your wallets from the widget's ... menu, Customize widget."
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }
}

if ($ftWidget -notin @("auto", "native", "rainmeter")) {
  Write-Host "FT_WIDGET must be auto, native or rainmeter (it is '$ftWidget')."
  return
}
if ($ftWidget -eq "rainmeter") { Install-Rainmeter; return }

$blocker = $null
if ($ftWidget -eq "auto") { $blocker = Get-NativeBlocker }
if ($blocker) {
  Write-Host "Using the Rainmeter skin instead of the Widgets Board widget: $blocker."
  Install-Rainmeter
  return
}
try {
  Install-Native
} catch [System.Security.SecurityException] {
  Write-Host $_.Exception.Message
  throw
} catch {
  $why = $_.Exception.Message
  if ($ftWidget -eq "native") { throw "The native widget could not be installed: $why" }
  Write-Host "Could not install the Widgets Board widget: $why."
  Write-Host "Using the Rainmeter skin instead (force the widget with `$env:FT_WIDGET = 'native' to see the error)."
  Install-Rainmeter
}
