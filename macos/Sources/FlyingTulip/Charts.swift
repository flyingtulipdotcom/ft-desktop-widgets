import Charts
import FTWidgetCore
import SwiftUI

private func mmdd(_ d: String) -> String { String(d.dropFirst(5).prefix(5)) }

/// Daily bars; the last bar (today so far, or the latest day) is lighter.
struct BarChart: View {
    let values: [DayValue]
    var barColor = Theme.tulip
    var lastColor = Theme.tulip300
    var maxLabel: String

    var body: some View {
        let maxV = max(values.map { $0.value }.max() ?? 0, 0.000001)
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Chart {
                    ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                        BarMark(x: .value("Day", String(i)), y: .value("Value", v.value), width: .ratio(0.72))
                            .foregroundStyle(i == values.count - 1 ? lastColor : barColor)
                            .cornerRadius(1.5)
                    }
                }
                .chartXScale(domain: values.indices.map { String($0) })
                .chartYScale(domain: 0...(maxV * 1.04))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, maxV / 2, maxV]) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.07))
                    }
                }
                Text(maxLabel).font(.system(size: 9)).foregroundColor(Theme.faint)
            }
            .frame(height: 78)
            HStack {
                Text(values.first.map { mmdd($0.date) } ?? "")
                Spacer()
                Text(values.last.map { mmdd($0.date) } ?? "")
            }
            .font(.system(size: 9)).foregroundColor(Theme.faint)
        }
    }
}

/// A line with a soft area under it and a dot on the last value.
struct LineArea: View {
    let values: [DayValue]
    var lineColor = Theme.tulip400
    var format: (Double) -> String

    var body: some View {
        let lo = values.map { $0.value }.min() ?? 0, hi = values.map { $0.value }.max() ?? 1
        let pad = max((hi - lo) * 0.08, 1e-9)
        let dLo = lo - pad, dHi = hi + pad
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                Chart {
                    ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                        AreaMark(x: .value("Day", i), yStart: .value("Base", dLo), yEnd: .value("Value", v.value))
                            .foregroundStyle(LinearGradient(colors: [lineColor.opacity(0.35), lineColor.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Day", i), y: .value("Value", v.value))
                            .foregroundStyle(lineColor)
                            .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    }
                    if let last = values.last {
                        PointMark(x: .value("Day", values.count - 1), y: .value("Value", last.value))
                            .foregroundStyle(Theme.tulip300).symbolSize(26)
                    }
                }
                .chartXScale(domain: 0...Double(max(values.count - 1, 1)))
                .chartYScale(domain: dLo...dHi)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [(dLo + dHi) / 2]) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3])).foregroundStyle(Color.white.opacity(0.08))
                    }
                }
                VStack {
                    Text(format(hi))
                    Spacer()
                    Text(format(lo))
                }
                .font(.system(size: 9)).foregroundColor(Theme.faint).padding(.vertical, 2)
            }
            .frame(height: 78)
            HStack {
                Text(values.first.map { mmdd($0.date) } ?? "")
                Spacer()
                Text(values.last.map { mmdd($0.date) } ?? "")
            }
            .font(.system(size: 9)).foregroundColor(Theme.faint)
        }
    }
}
