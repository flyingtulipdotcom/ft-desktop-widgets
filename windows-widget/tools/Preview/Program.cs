using FlyingTulip.Widget;

// CI/preview tool: runs the widget's real controller against the live public API and writes, for every tab and size,
// the Adaptive Card template and the data JSON the Widgets Board would bind it to. Usage stats stay off.
// Usage: Preview <outDir> <wallet>[,<wallet>...]
var outDir = args.Length > 0 ? args[0] : "out";
var wallets = args.Length > 1 ? args[1] : "";
Directory.CreateDirectory(outDir);
var tmp = Path.Combine(Path.GetTempPath(), "ftw-preview-" + Guid.NewGuid().ToString("N") + ".json");
var store = new StateStore(tmp);
store.State.StatsOn = false;
var http = new HttpClient();
var hub = new DataHub(new HttpFetcher(http), () => DateTimeOffset.UtcNow);
var stats = new UsageStats(new HttpEventSink(http), () => false, () => DateTimeOffset.UtcNow);
var ctl = new WidgetController(store, hub, stats, "Windows 11", () => DateTimeOffset.UtcNow, _ => { });
var st = store.Widget("preview");
st.Wallets = Fmt.ParseWallets(wallets).List; st.Normalize();

async Task Dump(string name, Rendered r)
{
    await File.WriteAllTextAsync(Path.Combine(outDir, name + ".template.json"), r.Template);
    await File.WriteAllTextAsync(Path.Combine(outDir, name + ".data.json"), r.Data);
    Console.WriteLine($"{name}: template {r.Template.Length} bytes, data {r.Data.Length} bytes");
}

var sizes = new[] { (WidgetSize.Small, "small"), (WidgetSize.Medium, "medium"), (WidgetSize.Large, "large") };
await ctl.RenderAsync("preview", WidgetSize.Large, force: true);
foreach (var tab in WidgetState.Tabs)
{
    await ctl.ActionAsync("preview", WidgetSize.Large, "tab_" + tab, null);
    foreach (var (size, label) in sizes)
    {
        if (size == WidgetSize.Small && tab != "market") continue;
        await Dump(label == "small" ? "small" : tab + "-" + label, await ctl.RenderAsync("preview", size));
    }
}
st.Customizing = true;
await Dump("customize", await ctl.RenderAsync("preview", WidgetSize.Large, fetch: false));
File.Delete(tmp);
