using System.Runtime.InteropServices;
using Microsoft.Windows.Widgets.Providers;
using WinRT;

namespace FlyingTulip.Widget.Provider;

static class Program
{
    // The COM class the Widgets Board starts this process for (see AppxManifest.xml).
    public const string ProviderClsid = "7c1b3f0e-5d2a-4a6e-9a77-2f1d6e4b8c10";

    [DllImport("ole32.dll")]
    static extern int CoRegisterClassObject(ref Guid rclsid, IntPtr pUnk, uint dwClsContext, uint flags, out uint cookie);
    [DllImport("ole32.dll")]
    static extern int CoRevokeClassObject(uint cookie);

    [MTAThread]
    static int Main(string[] args)
    {
        ComWrappersSupport.InitializeComWrappers();
        if (args.Length == 0 || args[0] != "-RegisterProcessAsComServer")
        {
            // started by hand: nothing to do, the Widgets Board starts it with the argument above
            return 0;
        }
        var provider = new WidgetProvider();
        var factory = new ProviderFactory(provider);
        var clsid = new Guid(ProviderClsid);
        var unk = Marshal.GetIUnknownForObject(factory);
        int hr = CoRegisterClassObject(ref clsid, unk, 4 /* CLSCTX_LOCAL_SERVER */, 1 /* REGCLS_MULTIPLEUSE */, out var cookie);
        Marshal.Release(unk);
        if (hr != 0) return hr;
        provider.Exited.WaitOne();
        CoRevokeClassObject(cookie);
        return 0;
    }
}

[ComImport, Guid("00000001-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IClassFactory
{
    [PreserveSig] int CreateInstance(IntPtr pUnkOuter, ref Guid riid, out IntPtr ppvObject);
    [PreserveSig] int LockServer(bool fLock);
}

[ComVisible(true), ClassInterface(ClassInterfaceType.None)]
sealed class ProviderFactory : IClassFactory
{
    readonly WidgetProvider _provider;
    public ProviderFactory(WidgetProvider provider) { _provider = provider; }

    public int CreateInstance(IntPtr pUnkOuter, ref Guid riid, out IntPtr ppvObject)
    {
        ppvObject = IntPtr.Zero;
        if (pUnkOuter != IntPtr.Zero) return unchecked((int)0x80040110);   // CLASS_E_NOAGGREGATION
        var unk = MarshalInterface<IWidgetProvider>.FromManaged(_provider);
        try { return Marshal.QueryInterface(unk, ref riid, out ppvObject); }
        finally { Marshal.Release(unk); }
    }

    public int LockServer(bool fLock) => 0;
}
