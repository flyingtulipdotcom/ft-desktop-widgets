import AppKit
import FTWidgetCore
import SwiftUI

struct Cap: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 9)).tracking(0.8).foregroundColor(Theme.faint).lineLimit(1)
    }
}

struct SubText: View {
    let text: String
    var color: Color = Theme.sub
    var size: CGFloat = 11
    var body: some View {
        Text(text).font(.system(size: size)).foregroundColor(color).lineLimit(1).truncationMode(.tail)
    }
}

/// Translucent fill, 1px soft border, 12px radius. With a url the whole card opens that page.
struct Card<Content: View>: View {
    @EnvironmentObject var model: AppModel
    var url: String? = nil
    var element: String = ""
    var alignTop = true
    @ViewBuilder var content: () -> Content
    @State var hover = false

    var body: some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: alignTop ? .infinity : nil, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(url != nil && hover ? Theme.tulip.opacity(0.55) : Theme.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onHover { if url != nil { hover = $0 } }
            .onTapGesture { if let u = url { model.openLink(u, element) } }
    }
}

struct Stat: View {
    let label: String
    let value: String
    var sub: String = ""
    var valueColor: Color = Theme.text
    var subColor: Color = Theme.sub
    var valueSize: CGFloat = 16
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Cap(text: label)
            Text(value).font(.system(size: valueSize, weight: .bold)).foregroundColor(valueColor).lineLimit(1).minimumScaleFactor(0.7)
            if !sub.isEmpty {
                Text(sub).font(.system(size: 10)).foregroundColor(subColor).lineLimit(4).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Pill: View {
    let text: String
    let selected: Bool
    let action: () -> Void
    @State var hover = false
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? Theme.tulip300 : Theme.sub)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(selected ? Theme.tulip.opacity(0.22) : (hover ? Color.white.opacity(0.05) : .clear)))
                .overlay(Capsule().stroke(selected ? Theme.tulip : Theme.border, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct IconButton: View {
    let symbol: String
    let action: () -> Void
    @State var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(hover ? Theme.tulip300 : Theme.sub)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(hover ? Theme.tulip.opacity(0.16) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(hover ? Theme.tulip : Theme.border, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// One chain's HF: name, a bar with fill (green/amber/red), the 1.25 liquidation line, value.
struct HfGauge: View {
    let chain: ChainHealth
    let warn: Double
    let crit: Double
    let scaleMax = 3.0

    private func x(_ v: Double, _ w: CGFloat) -> CGFloat {
        CGFloat(max(0, min(1, (v - 1.0) / (scaleMax - 1.0)))) * w
    }
    private var fill: Color {
        guard let hf = chain.hf else { return Theme.sub }
        return hf <= crit ? Theme.red : (hf <= warn ? Theme.amber : Theme.green)
    }
    var body: some View {
        HStack(spacing: 0) {
            Text(chain.name).font(.system(size: 12)).foregroundColor(Theme.text).frame(width: 66, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07)).frame(height: 6)
                    if let hf = chain.hf {
                        Capsule().fill(fill).frame(width: x(min(scaleMax, hf), g.size.width), height: 6)
                    }
                    RoundedRectangle(cornerRadius: 1).fill(Theme.red).frame(width: 2, height: 14)
                        .offset(x: x(chain.liqHf, g.size.width) - 1)
                }
                .frame(height: g.size.height, alignment: .center)
            }
            .frame(height: 22)
            .padding(.trailing, 10)
            Text(chain.hf == nil ? "no debt" : Fmt.hf(chain.hf))
                .font(.system(size: chain.hf == nil ? 10 : 12, weight: chain.hf == nil ? .regular : .bold))
                .foregroundColor(chain.hf == nil ? Theme.sub : fill)
                .frame(width: 52, alignment: .trailing)
        }
        .frame(height: 22)
    }
}
