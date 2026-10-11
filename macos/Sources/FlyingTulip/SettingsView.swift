import AppKit
import FTWidgetCore
import ServiceManagement
import SwiftUI

/// A plain AppKit window, so it opens reliably from a menu bar panel.
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    @MainActor func show(model: AppModel) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView().environmentObject(model)))
            w.title = "Flying Tulip"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 460, height: 560))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var newWallet = ""
    @State private var error = ""
    @State private var warn = ""
    @State private var crit = ""
    @State private var cooldown = ""
    @State private var notify = true
    @State private var chain = 1
    @State private var statsOn = true
    @State private var login = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section("Wallets") {
                if model.wallets.isEmpty { Text("Public wallet addresses to show (0x...), comma separated.").foregroundColor(.secondary).font(.caption) }
                ForEach(model.wallets, id: \.self) { w in
                    HStack {
                        Text(w).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        Spacer()
                        Button("Remove") { model.removeWallet(w) }
                    }
                }
                HStack {
                    TextField("0x...", text: $newWallet).onSubmit(add)
                    Button("Add a wallet…", action: add)
                }
                if !error.isEmpty { Text(error).foregroundColor(.red).font(.caption) }
            }
            Section("Alerts") {
                TextField("Warning at or below HF", text: $warn).onSubmit(save)
                TextField("Critical at or below HF", text: $crit).onSubmit(save)
                Toggle("Show a macOS notification when health factor crosses a threshold.", isOn: $notify)
                    .onChange(of: notify) { _ in save() }
                TextField("Minimum minutes between two notifications of the same level", text: $cooldown).onSubmit(save)
                Text("Liquidation starts below 1.25.").foregroundColor(.secondary).font(.caption)
            }
            Section("Market") {
                Picker("Chain whose FT-ftUSD market price is shown.", selection: $chain) {
                    Text("Ethereum").tag(1)
                    Text("Sonic").tag(146)
                }
                .onChange(of: chain) { _ in save() }
            }
            Section("General") {
                Toggle("Launch at login", isOn: $login)
                    .onChange(of: login) { on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { login = SMAppService.mainApp.status == .enabled }
                    }
            }
            Section {
                DisclosureGroup("Advanced") {
                    Toggle("Anonymous usage stats", isOn: $statsOn)
                        .onChange(of: statsOn) { on in model.stats.setEnabled(on) }
                    Text("No wallet or account data, see the README.").foregroundColor(.secondary).font(.caption)
                }
            }
            HStack { Spacer(); Button("Save") { save() }.keyboardShortcut(.defaultAction) }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let s = model.settings
            warn = String(format: "%.2f", s.hfWarn); crit = String(format: "%.2f", s.hfCritical)
            cooldown = String(Int(s.cooldownMin)); notify = s.notifications; chain = s.priceChain
            statsOn = s.analytics; login = SMAppService.mainApp.status == .enabled
        }
    }

    func add() {
        if let e = model.addWallet(newWallet) { error = e } else { error = ""; newWallet = "" }
    }

    func save() {
        let s = model.settings
        if let w = Double(warn.replacingOccurrences(of: ",", with: ".")), w > 1 { s.hfWarn = w }
        if let c = Double(crit.replacingOccurrences(of: ",", with: ".")), c > 1 { s.hfCritical = min(c, s.hfWarn) }
        if let m = Double(cooldown), m >= 1 { s.cooldownMin = m }
        s.notifications = notify
        s.priceChain = chain
        warn = String(format: "%.2f", s.hfWarn); crit = String(format: "%.2f", s.hfCritical)
        model.settingsChanged()
    }
}
