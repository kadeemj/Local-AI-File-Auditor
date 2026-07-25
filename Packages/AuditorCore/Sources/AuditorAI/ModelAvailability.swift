import AuditorModels
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reports whether on-device Apple Intelligence is usable for semantic judgments.
/// Checked per scan (not per launch): the model can become available mid-session
/// after a download, or unavailable if the user disables Apple Intelligence.
public enum ModelAvailability {
    case available
    case unavailable(reason: String)

    public static func current() -> ModelAvailability {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(reason: String(describing: reason))
        @unknown default:
            return .unavailable(reason: "unknown availability state")
        }
        #else
        return .unavailable(reason: "FoundationModels framework not present")
        #endif
    }
}
