; Flying Tulip settings. Advanced settings are at the end. Use the cog on the skin (or right-click the skin > Wallets and settings) for the wallets,
; or edit this file (right-click > Edit the settings file). Rainmeter keeps these values when a newer version is installed.
[Variables]
; Public wallet addresses to show, comma separated (0x + 40 hex characters each). Empty: market data only.
; With more than one, the skin shows them in turn (see RotateSeconds) and the switch icon next to the address
; jumps to the next one. A wallet whose health factor is low is shown at once and stays shown while it is low.
Wallets=
; The single wallet of version 1.0.x. Still read; the skin keeps it equal to the first wallet above.
Wallet=
; Seconds each wallet is shown before the next one (minimum 10).
RotateSeconds=60
; Warning notification at or below this health factor. Liquidation starts below 1.25.
HfWarn=1.40
; Critical notification at or below this health factor. Keep it above 1.25.
HfCritical=1.30
; Minimum minutes between two notifications of the same level, per wallet.
NotifyCooldownMin=30
; 1 shows a Windows toast notification on a crossing, 0 only shows the warning colours on the skin.
Notifications=1
; Chain whose FT-ftUSD market price is shown: 1 (Ethereum) or 146 (Sonic).
PriceChainId=1
; Seconds between refreshes (minimum 15).
RefreshSeconds=60
; Last tab shown: market, account or positions (the skin writes it when you click a tab).
Tab=
; ---- Advanced settings
; 1 sends anonymous usage stats (platform, version, Windows and Rainmeter version, which tab or link was used). Never a
; wallet, balance or position. 0 turns them off (also right-click the skin > Advanced: anonymous usage stats).
Analytics=1
