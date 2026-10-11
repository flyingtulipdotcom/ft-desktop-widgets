# CI only: install Rainmeter on the Windows runner, load the skin with a public wallet, and screenshot each tab.
$ErrorActionPreference = "Continue"
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$out = Join-Path $root "out"
New-Item -ItemType Directory -Force -Path $out | Out-Null
function Log($m) { Write-Host "[ci] $m" }
$wallet = $env:FT_CI_WALLET

# Usage stats stay off in CI: the setting below, and the Plausible host does not resolve.
Add-Content -Path "$env:windir\System32\drivers\etc\hosts" -Value "`n127.0.0.1 plausible.io" -ErrorAction SilentlyContinue

# A larger desktop than the default 1024x768, when the runner allows it.
try { Set-DisplayResolution -Width 1920 -Height 1080 -Force -ErrorAction Stop; Log "resolution 1920x1080" } catch { Log "resolution unchanged: $_" }
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
Log "screen $($screen.Width)x$($screen.Height)"

# ---- Rainmeter
$rm = "$env:ProgramFiles\Rainmeter\Rainmeter.exe"
if (-not (Test-Path $rm)) {
  $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/rainmeter/rainmeter/releases/latest" -Headers @{ "User-Agent" = "ft-desktop-widgets-ci" }
  $asset = $rel.assets | Where-Object { $_.name -match '^Rainmeter-[\d.]+\.exe$' } | Select-Object -First 1
  Log "installing $($asset.name)"
  $setup = Join-Path $env:TEMP $asset.name
  Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $setup -UseBasicParsing
  Start-Process -FilePath $setup -ArgumentList "/S" -Wait
}
if (-not (Test-Path $rm)) { Log "FAIL: Rainmeter.exe not found after install"; exit 1 }
Log ("Rainmeter " + (Get-Item $rm).VersionInfo.ProductVersion)
Stop-Process -Name Rainmeter -ErrorAction SilentlyContinue

# ---- the skin, with a wallet, usage stats off, the Account tab first
$skins = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Rainmeter\Skins"
New-Item -ItemType Directory -Force -Path $skins | Out-Null
Remove-Item -Recurse -Force (Join-Path $skins "FlyingTulip") -ErrorAction SilentlyContinue
Copy-Item -Recurse (Join-Path $root "rainmeter\Skins\FlyingTulip") $skins
$settings = Join-Path $skins "FlyingTulip\@Resources\Settings.inc"
$s = Get-Content $settings -Raw
$s = $s -replace "(?m)^Wallets=.*$", "Wallets=$wallet" -replace "(?m)^Analytics=.*$", "Analytics=0" -replace "(?m)^Tab=.*$", "Tab=account" -replace "(?m)^Notifications=.*$", "Notifications=0"
Set-Content -Path $settings -Value $s -NoNewline

$appdata = Join-Path $env:APPDATA "Rainmeter"
New-Item -ItemType Directory -Force -Path $appdata | Out-Null
@"
[Rainmeter]
SkinPath=$skins\
Logging=1
Debug=1

[FlyingTulip]
Active=1
WindowX=20
WindowY=20
AlwaysOnTop=1
"@ | Set-Content -Path (Join-Path $appdata "Rainmeter.ini")

Start-Process -FilePath $rm
Log "waiting for the data"
Start-Sleep -Seconds 35

function Shot($name) {
  $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  # CaptureBlt: Rainmeter skins are layered windows, which a plain copy leaves out
  $op = [System.Drawing.CopyPixelOperation]::SourceCopy -bor [System.Drawing.CopyPixelOperation]::CaptureBlt
  $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size, $op)
  $w = [Math]::Min(460, $b.Width - 10); $h = [Math]::Min(900, $b.Height - 10)
  $crop = $bmp.Clone((New-Object System.Drawing.Rectangle 10, 10, $w, $h), $bmp.PixelFormat)
  $crop.Save((Join-Path $out "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose(); $crop.Dispose()
  Log "shot $name"
}
Shot "rainmeter-account"
foreach ($tab in @("market", "positions")) {
  & $rm "!CommandMeasure" "MeasureScript" "ShowTab('$tab')" "FlyingTulip"
  Start-Sleep -Seconds 3
  Shot "rainmeter-$tab"
}
& $rm "!CommandMeasure" "MeasureScript" "ShowTab('account')" "FlyingTulip"

$logFile = Join-Path $appdata "Rainmeter.log"
if (Test-Path $logFile) { Copy-Item $logFile (Join-Path $out "Rainmeter.log") }
Stop-Process -Name Rainmeter -ErrorAction SilentlyContinue
$errors = @()
if (Test-Path $logFile) { $errors = Select-String -Path $logFile -Pattern "ERRO|Error" | Where-Object { $_.Line -match "FlyingTulip|Script|WebParser" } }
if ($errors.Count -gt 0) { Log "FAIL: errors in the Rainmeter log"; $errors | ForEach-Object { Write-Host $_.Line }; exit 1 }
Log "no skin errors in the Rainmeter log"
