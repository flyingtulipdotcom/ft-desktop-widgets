# Shows one Windows toast. Called by the Flying Tulip skin with the path of a 3-line text file:
# title, body, level (normal or critical). Windows PowerShell 5.1 or later, no extra modules.
param([Parameter(Mandatory = $true)][string]$File)

$ErrorActionPreference = 'Stop'
try {
    $lines = @(Get-Content -LiteralPath $File -Encoding UTF8)
    $title = if ($lines.Count -gt 0) { $lines[0] } else { 'Flying Tulip' }
    $body = if ($lines.Count -gt 1) { $lines[1] } else { '' }
    $level = if ($lines.Count -gt 2) { $lines[2] } else { 'normal' }

    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $duration = if ($level -eq 'critical') { 'long' } else { 'short' }
    $xml.LoadXml("<toast duration='$duration'><visual><binding template='ToastGeneric'><text/><text/></binding></visual></toast>")
    $texts = $xml.GetElementsByTagName('text')
    $texts.Item(0).AppendChild($xml.CreateTextNode($title)) | Out-Null
    $texts.Item(1).AppendChild($xml.CreateTextNode($body)) | Out-Null

    # Windows PowerShell's own AppUserModelID: the toast works without registering an app of our own.
    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
}
catch {
    exit 1
}
