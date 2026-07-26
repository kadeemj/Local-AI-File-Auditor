import Foundation
import Testing
@testable import FolderLint

@Suite("UpdaterService")
@MainActor
struct UpdaterServiceTests {
    @Test("constructs without starting the updater scheduler")
    func constructsIdle() {
        let updater = UpdaterService(startingUpdater: false)
        #expect(updater.feedURL?.host() == "folderlint.com" || updater.feedURL == nil)
        // When Info.plist is present in the test host, feed is folderlint.com.
        if let host = updater.feedURL?.host() {
            #expect(host == "folderlint.com")
        }
    }
}

@Suite("Sparkle sandbox configuration")
struct SparkleSandboxConfigurationTests {
    @Test("entitlements declare installer mach-lookup names")
    func entitlementsHaveMachLookup() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // FolderLintTests
            .deletingLastPathComponent() // repo root
        let entsURL = root.appending(path: "FolderLint/FolderLint.entitlements")
        let data = try Data(contentsOf: entsURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let dict = try #require(plist as? [String: Any])
        let names = try #require(dict["com.apple.security.temporary-exception.mach-lookup.global-name"] as? [String])
        #expect(names.contains("$(PRODUCT_BUNDLE_IDENTIFIER)-spks"))
        #expect(names.contains("$(PRODUCT_BUNDLE_IDENTIFIER)-spki"))
        #expect(dict["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(dict["com.apple.security.network.client"] as? Bool == true)
    }

    @Test("Info.plist enables installer XPC and disables system profiling")
    func infoPlistSparkleKeys() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoURL = root.appending(path: "FolderLint/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let dict = try #require(plist as? [String: Any])
        #expect(dict["SUEnableInstallerLauncherService"] as? Bool == true)
        #expect(dict["SUEnableSystemProfiling"] as? Bool == false)
        #expect(dict["SUFeedURL"] as? String == "https://folderlint.com/appcast.xml")
        let publicKey = try #require(dict["SUPublicEDKey"] as? String)
        #expect(!publicKey.isEmpty)
        #expect(dict["SUEnableDownloaderService"] == nil)
    }
}
