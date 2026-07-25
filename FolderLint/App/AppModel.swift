import Foundation
import Observation

/// Root dependency container. Grows LicenseManager, FolderAccessManager,
/// ScanCoordinator, UpdaterService, and ScanStore across Phases 8–12.
@Observable
@MainActor
final class AppModel {
    var needsOnboarding = true
}
