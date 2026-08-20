import Foundation
import WidgetKit

/// Reads and writes `CadenceSessionState` in the App Group container shared by
/// the app and the widget extension. Writing also nudges WidgetKit to refresh.
enum SharedStore {
    static let appGroupID = "group.com.alexmathews.cadence"
    private static let stateKey = "sessionState"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func load() -> CadenceSessionState {
        guard
            let data = defaults?.data(forKey: stateKey),
            let state = try? JSONDecoder().decode(CadenceSessionState.self, from: data)
        else {
            return .placeholder
        }
        return state
    }

    static func save(_ state: CadenceSessionState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults?.set(data, forKey: stateKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
