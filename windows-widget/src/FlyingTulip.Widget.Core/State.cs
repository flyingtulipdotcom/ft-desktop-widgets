using System.Text.Json;

namespace FlyingTulip.Widget;

/// <summary>What one widget instance remembers: its wallets, the wallet shown and the active tab.</summary>
public sealed class WidgetState
{
    public List<string> Wallets { get; set; } = new();
    public string Cur { get; set; } = "";
    public long ShownAt { get; set; }
    public string Tab { get; set; } = "market";
    public int PriceChain { get; set; } = 1;
    public bool Customizing { get; set; }
    public string Notice { get; set; } = "";

    public static readonly string[] Tabs = { "market", "account", "positions" };

    public void Normalize()
    {
        if (!Tabs.Contains(Tab)) Tab = "market";
        if (PriceChain != 146) PriceChain = 1;
        Wallets = Wallets.Select(Fmt.NormalizeWallet).Where(w => w.Length > 0).Distinct().ToList();
        if (!Wallets.Contains(Cur)) Cur = Wallets.FirstOrDefault() ?? "";
    }
}

public sealed class AppState
{
    public bool StatsOn { get; set; } = true;
    public StatCounters Counters { get; set; } = new();
    public Dictionary<string, WidgetState> Widgets { get; set; } = new();
}

/// <summary>The state file (JSON in the user's local app data). Missing or damaged files start empty.</summary>
public sealed class StateStore
{
    readonly string _path;
    readonly object _lock = new();
    public AppState State { get; private set; } = new();

    public StateStore(string path)
    {
        _path = path;
        try { if (File.Exists(path)) State = JsonSerializer.Deserialize<AppState>(File.ReadAllText(path)) ?? new(); }
        catch { State = new(); }
        foreach (var w in State.Widgets.Values) w.Normalize();
    }

    public WidgetState Widget(string id)
    {
        lock (_lock)
        {
            if (!State.Widgets.TryGetValue(id, out var w)) State.Widgets[id] = w = new WidgetState();
            return w;
        }
    }

    public void Remove(string id) { lock (_lock) State.Widgets.Remove(id); Save(); }

    public void Save()
    {
        lock (_lock)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
                var tmp = _path + ".tmp";
                File.WriteAllText(tmp, JsonSerializer.Serialize(State));
                File.Move(tmp, _path, true);
            }
            catch { /* the state is a convenience */ }
        }
    }
}
