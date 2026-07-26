import Foundation
import Observation
import Sparkle

/// Owns the single `SPUStandardUpdaterController` for the process.
/// Created once from `AppModel.init` — Sparkle forbids multiple updaters.
@Observable
@MainActor
final class UpdaterService {
    private let controller: SPUStandardUpdaterController
    private var canCheckObservation: NSKeyValueObservation?

    private(set) var canCheckForUpdates = false
    private(set) var lastError: String?

    /// Feed URL from Info.plist (`SUFeedURL`) — surfaced in Privacy settings.
    var feedURL: URL? {
        guard let string = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String else {
            return nil
        }
        return URL(string: string)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var updateCheckInterval: TimeInterval {
        get { controller.updater.updateCheckInterval }
        set { controller.updater.updateCheckInterval = newValue }
    }

    /// - Parameter startingUpdater: Pass `false` in unit tests / previews so
    ///   Sparkle does not schedule network checks or show misconfiguration alerts.
    init(startingUpdater: Bool = true) {
        controller = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        canCheckForUpdates = controller.updater.canCheckForUpdates
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in
                self?.canCheckForUpdates = value
            }
        }
    }

    func checkForUpdates() {
        lastError = nil
        guard canCheckForUpdates else {
            lastError = "Sparkle is not ready to check for updates yet."
            return
        }
        controller.checkForUpdates(nil)
    }
}
