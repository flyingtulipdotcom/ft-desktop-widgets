import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in AppModel.shared.start() }
        reportStatusItemFrame()
    }

    /// CI only: with FT_CI_FRAME_FILE set, write where the menu bar item is ("<centre x> <screen height>", in points),
    /// so the screenshot script knows where to click.
    private func reportStatusItemFrame() {
        guard let path = ProcessInfo.processInfo.environment["FT_CI_FRAME_FILE"], !path.isEmpty else { return }
        for delay in [5.0, 10.0, 15.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let win = NSApp.windows.first { String(describing: type(of: $0)).contains("StatusBar") }
                let screenH = NSScreen.screens.first?.frame.height ?? 1080
                if let f = win?.frame {
                    try? "\(Int(f.midX)) \(Int(screenH)) \(Int(f.width))\n".write(toFile: path, atomically: true, encoding: .utf8)
                } else {
                    let names = NSApp.windows.map { String(describing: type(of: $0)) }.joined(separator: ",")
                    try? "none \(names)\n".write(toFile: path + ".debug", atomically: true, encoding: .utf8)
                }
            }
        }
    }
}

@main
struct FlyingTulipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(model)
        } label: {
            TitleLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct TitleLabel: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Image(nsImage: model.titleImage).renderingMode(.original)
    }
}
