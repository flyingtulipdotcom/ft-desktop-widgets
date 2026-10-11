using System.Text.Json.Nodes;

namespace FlyingTulip.Widget;

public enum WidgetSize { Small, Medium, Large }

/// <summary>Small builders for Adaptive Card JSON (schema 1.5, the subset the Windows widget host renders).</summary>
static class Ac
{
    static JsonArray Arr(IEnumerable<JsonNode?> items) => new(items.Where(i => i is not null).Select(i => i!).ToArray());

    public static JsonObject Card(params JsonNode?[] body) => new()
    {
        ["type"] = "AdaptiveCard",
        ["$schema"] = "http://adaptivecards.io/schemas/adaptive-card.json",
        ["version"] = "1.5",
        ["body"] = Arr(body),
    };

    public static JsonObject Text(string text, string? size = null, string? weight = null, string? color = null,
        bool subtle = false, bool wrap = false, string? align = null, int? maxLines = null, string? spacing = null)
    {
        var o = new JsonObject { ["type"] = "TextBlock", ["text"] = text };
        if (size is not null) o["size"] = size;
        if (weight is not null) o["weight"] = weight;
        if (color is not null) o["color"] = color;
        if (subtle) o["isSubtle"] = true;
        if (wrap) o["wrap"] = true;
        if (align is not null) o["horizontalAlignment"] = align;
        if (maxLines is not null) o["maxLines"] = maxLines;
        if (spacing is not null) o["spacing"] = spacing;
        return o;
    }

    /// <summary>Small grey capital label above a value.</summary>
    public static JsonObject Cap(string text, string? align = null, string? spacing = null) =>
        Text(text, size: "small", subtle: true, align: align, spacing: spacing, maxLines: 1);

    public static JsonObject Col(string width, params JsonNode?[] items)
    {
        // a card inside a column fills the column, so the cards of a row are as tall as the tallest
        foreach (var i in items) if (i is JsonObject o && o["type"]?.GetValue<string>() == "Container" && o["style"] is not null) o["height"] = "stretch";
        return new JsonObject { ["type"] = "Column", ["width"] = width, ["items"] = Arr(items) };
    }

    public static JsonObject Cols(params JsonNode?[] columns) => new() { ["type"] = "ColumnSet", ["columns"] = Arr(columns) };

    public static JsonObject Box(JsonNode?[] items, JsonObject? select = null, string style = "emphasis", string spacing = "small")
    {
        var o = new JsonObject
        {
            ["type"] = "Container", ["style"] = style, ["roundedCorners"] = true, ["spacing"] = spacing,
            ["items"] = Arr(items),
        };
        if (select is not null) o["selectAction"] = select;
        return o;
    }

    public static JsonObject Image(string url, string size = "stretch", string alt = "", string? align = null, string? width = null, string? height = null)
    {
        var o = new JsonObject { ["type"] = "Image", ["url"] = url, ["size"] = size, ["altText"] = alt };
        if (align is not null) o["horizontalAlignment"] = align;
        if (width is not null) o["width"] = width;
        if (height is not null) o["height"] = height;
        return o;
    }

    public static JsonObject Exec(string title, string verb, JsonObject? data = null, string? style = null, string? tooltip = null)
    {
        var o = new JsonObject { ["type"] = "Action.Execute", ["title"] = title, ["verb"] = verb };
        if (data is not null) o["data"] = data;
        if (style is not null) o["style"] = style;
        if (tooltip is not null) o["tooltip"] = tooltip;
        return o;
    }

    /// <summary>An element that opens a flyingtulip.com page: the provider counts the click, then opens it.</summary>
    public static JsonObject Open(string element, string urlExpr) =>
        Exec("", "open", new JsonObject { ["element"] = element, ["url"] = urlExpr });

    public static JsonObject Actions(params JsonNode?[] actions) => new() { ["type"] = "ActionSet", ["actions"] = Arr(actions) };

    public static T When<T>(this T node, string expr) where T : JsonNode { node["$when"] = expr; return node; }
    public static T Each<T>(this T node, string listExpr) where T : JsonNode { node["$data"] = listExpr; return node; }
    public static T Sel<T>(this T node, JsonObject action) where T : JsonNode { node["selectAction"] = action; return node; }
    public static T Pad<T>(this T node, string spacing) where T : JsonNode { node["spacing"] = spacing; return node; }
    public static T Mid<T>(this T node) where T : JsonNode { node["verticalContentAlignment"] = "Center"; return node; }
}
