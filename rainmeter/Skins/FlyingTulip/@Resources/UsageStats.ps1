# Anonymous usage stats for the Flying Tulip skin: one Plausible event, fire and forget.
# Usage: UsageStats.ps1 <event name> <skin version> <path of Rainmeter.exe> [key=value ...]
# Sends only the event name, the platform, the skin version and the key=value pairs the skin passes (tab, element,
# url, level, endpoint, walletsConfigured). For the launch pageview it adds the Windows and Rainmeter versions.
# The skin never passes a wallet address, balance or position, and only calls this while Analytics=1.
param([string]$Name, [string]$Version, [string]$RainmeterExe)
$ErrorActionPreference = "SilentlyContinue"
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  $props = [ordered]@{ platform = "windows"; version = $Version }
  foreach ($a in $args) {
    $i = "$a".IndexOf("=")
    if ($i -gt 0) {
      # belt and braces: no wallet address ever leaves, even inside a URL
      $props["$a".Substring(0, $i)] = ("$a".Substring($i + 1) -replace "0x[0-9a-fA-F]{40}", ":address")
    }
  }
  if ($Name -eq "pageview") {
    $os = "Windows"
    try {
      $caption = (Get-CimInstance Win32_OperatingSystem).Caption
      if ($caption -match "Windows (Server )?(\d+)") { $os = "Windows " + $Matches[1] + $Matches[2] }
    } catch {}
    $props["os"] = $os
    try {
      $exe = $RainmeterExe
      $v = (Get-Item $exe).VersionInfo.ProductVersion
      if ($v) { $props["host"] = "Rainmeter " + (($v -split "[ ,]")[0]) }
    } catch {}
  }
  $body = [ordered]@{ name = $Name; url = "app://widget/windows"; domain = "widget"; props = $props } | ConvertTo-Json -Compress
  $ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) FlyingTulipWidget/" + $Version
  $r = Invoke-WebRequest -Uri "https://plausible.io/api/event" -Method Post -Body $body -ContentType "application/json" `
    -UserAgent $ua -TimeoutSec 10 -UseBasicParsing
  if ($env:FT_USAGE_DEBUG) { Write-Output ("{0} {1}" -f [int]$r.StatusCode, $body) }
} catch {
  if ($env:FT_USAGE_DEBUG) { Write-Output ("error {0}" -f $_) }
}
