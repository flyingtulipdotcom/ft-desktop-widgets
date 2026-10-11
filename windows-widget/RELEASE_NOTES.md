Flying Tulip widget for the Windows 11 Widgets Board (Win+W): one widget with Market, Account and Positions tabs, in small, medium and large sizes.

This is a test build signed with a self-signed certificate (`FlyingTulipWidget-test.cer`), so Windows has to be told to trust it once.

**Install, the quick way** (PowerShell, Windows 11):

```powershell
irm https://raw.githubusercontent.com/flyingtulipdotcom/ft-desktop-widgets/main/windows-widget/install.ps1 -OutFile install.ps1
.\install.ps1
```

It downloads this release, trusts the certificate for the machine (one administrator prompt), installs the Windows App Runtime 1.8 if it is missing and installs the package.

**Install by hand**

1. Download `FlyingTulipWidget.msix` and `FlyingTulipWidget-test.cer`.
2. Trust the certificate: open an administrator PowerShell and run
   `Import-Certificate -FilePath .\FlyingTulipWidget-test.cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople`
   (or turn on Settings > System > For developers > Developer Mode, which allows sideloading without it).
3. Install the Windows App Runtime 1.8 if you do not have it: https://aka.ms/windowsappsdk/1.8/latest/windowsappruntimeinstall-x64.exe
4. Double-click the `.msix` (or `Add-AppxPackage .\FlyingTulipWidget.msix`).
5. Press Win+W, choose **+**, pick **Flying Tulip**. Wallets: the three dots of the widget, **Customize widget**.

Windows 11 only (build 22000 or newer), x64. The Rainmeter skin, xbar plugin and Omarchy plugin are unchanged.
