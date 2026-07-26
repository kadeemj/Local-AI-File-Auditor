# FolderLint build automation.

XCODEPROJ := FolderLint.xcodeproj
SCHEME    := FolderLint

.PHONY: generate build test test-app clean verify release keys help

help:
	@echo "Targets:"
	@echo "  make generate          Regenerate Xcode project from project.yml"
	@echo "  make build             Debug build"
	@echo "  make test              Engine tests"
	@echo "  make test-app          App unit tests"
	@echo "  make keys              Generate/print Sparkle EdDSA keys (backup private key!)"
	@echo "  make release VERSION=x.y.z   Archive → export → notarize → DMG → appcast"
	@echo "  make verify APP=… [DMG=…]    Gatekeeper / codesign / stapler checks"

# Regenerate FolderLint.xcodeproj from project.yml (requires: brew install xcodegen)
generate:
	xcodegen generate

# Debug build of the app (ad-hoc signed, sandboxed)
build:
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Debug build

# Engine test suite (headless, no Xcode project needed)
test:
	cd Packages/AuditorCore && swift test

# App unit tests (bookmarks, session, license, updater)
test-app:
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Debug test -only-testing:FolderLintTests

clean:
	rm -rf build dist
	cd Packages/AuditorCore && swift package clean

# Sparkle EdDSA keypair — private key never enters the repo
keys:
	Scripts/generate_sparkle_keys.sh

# Full release pipeline. Requires Developer ID + notary-profile in Keychain.
release:
	@test -n "$(VERSION)" || (echo "usage: make release VERSION=x.y.z" >&2; exit 1)
	VERSION=$(VERSION) Scripts/release.sh

# Signing/notarization verification for release artifacts
verify:
	@test -n "$(APP)" || (echo "usage: make verify APP=path/to/FolderLint.app [DMG=path/to.dmg]" >&2; exit 1)
	Scripts/verify.sh "$(APP)" $(if $(DMG),"$(DMG)",)
