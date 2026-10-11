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

# The skin's own window, drawn by PrintWindow (works for layered windows even when the desktop capture is blank).
Add-Type -ReferencedAssemblies System.Drawing, System.Windows.Forms -TypeDefinition @"
using System; using System.Text; using System.Drawing; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class Win {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static List<string> List() {
    var o = new List<string>();
    EnumWindows((h, l) => { if (IsWindowVisible(h)) { var c = new StringBuilder(256); var t = new StringBuilder(256); GetClassName(h, c, 256); GetWindowText(h, t, 256); RECT r; GetWindowRect(h, out r);
      o.Add(c + " | " + t + " | " + r.L + "," + r.T + " " + (r.R - r.L) + "x" + (r.B - r.T)); } return true; }, IntPtr.Zero);
    return o;
  }
  public static Bitmap Skin() {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => { var c = new StringBuilder(256); GetClassName(h, c, 256); if (c.ToString() == "RainmeterMeterWindow" && IsWindowVisible(h)) { found = h; return false; } return true; }, IntPtr.Zero);
    if (found == IntPtr.Zero) return null;
    RECT r; GetWindowRect(found, out r);
    var bmp = new Bitmap(Math.Max(1, r.R - r.L), Math.Max(1, r.B - r.T), System.Drawing.Imaging.PixelFormat.Format32bppArgb);
    var clear = Color.FromArgb(255, 32, 36, 44);
    using (var g = Graphics.FromImage(bmp)) { g.Clear(clear); var dc = g.GetHdc(); PrintWindow(found, dc, 2); g.ReleaseHdc(dc); }
    // the window keeps the tallest tab's height: crop the empty rows under the panel
    int last = bmp.Height - 1;
    while (last > 10 && bmp.GetPixel(bmp.Width / 2, last).ToArgb() == clear.ToArgb()) last--;
    if (last < bmp.Height - 1) { var c = bmp.Clone(new Rectangle(0, 0, bmp.Width, last + 2), bmp.PixelFormat); bmp.Dispose(); return c; }
    return bmp;
  }
}
"@
[Win]::List() | Set-Content (Join-Path $out "windows.txt")

function Shot($name) {
  $skin = [Win]::Skin()
  if ($skin) { $skin.Save((Join-Path $out "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png); $skin.Dispose(); Log "shot $name (skin window)" }
  else { Log "FAIL: no skin window found"; exit 1 }
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
