import Foundation
import ServiceManagement

/// Wraps `SMAppService` to toggle Cadence as a login item (start at login,
/// running in the background as a menu-bar app).
@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var isEnabled: Bool

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("Cadence: failed to update login item: \(error.localizedDescription)")
        }
        // Reflect whatever the system actually reports back.
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
