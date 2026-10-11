import Foundation
import XCTest
@testable import FTWidgetCore

func fixture(_ name: String) throws -> Any {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"), "missing fixture \(name)")
    return try JSONSerialization.jsonObject(with: Data(contentsOf: url), options: [.fragmentsAllowed])
}

func json(_ s: String) -> Any {
    try! JSONSerialization.jsonObject(with: Data(s.utf8), options: [.fragmentsAllowed])
}

final class CaptureTransport: StatsTransport {
    var bodies: [Data] = []
    func post(_ body: Data) { bodies.append(body) }
    var events: [[String: Any]] { bodies.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
    var names: [String] { events.compactMap { $0["name"] as? String } }
}

let testWallet = "0x38A564A38Be5DFb6eF2AB765dA1e4397d03C2D62"

func freshSettings(_ file: String = #function) -> SettingsStore {
    let name = "ft-tests-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return SettingsStore(defaults: d)
}
