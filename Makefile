# FolderLint build automation. Release pipeline scripts land in Phase 12.

XCODEPROJ := FolderLint.xcodeproj
SCHEME    := FolderLint

.PHONY: generate build test test-app clean verify

# Regenerate FolderLint.xcodeproj from project.yml (requires: brew install xcodegen)
generate:
	xcodegen generate

# Debug build of the app (ad-hoc signed, sandboxed)
build:
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Debug build

# Engine test suite (headless, no Xcode project needed)
test:
	cd Packages/AuditorCore && swift test

# App unit tests (bookmark round-trip + ScanSessionModel mock stream)
test-app:
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Debug test -only-testing:FolderLintTests

clean:
	rm -rf build
	cd Packages/AuditorCore && swift package clean

# Signing/notarization verification for release artifacts (fully wired in Phase 12)
verify:
	@echo "Phase 12: spctl -a -vv, codesign --verify --strict, stapler validate"
