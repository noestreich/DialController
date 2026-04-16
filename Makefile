APP          = DialController
BUNDLE       = $(APP).app
BINARY_DIR   = .build/release
ENTITLEMENTS = $(APP).entitlements
ICON         = Resources/AppIcon.icns

# Developer-ID signing config (override via environment or `make VAR=… target`)
#   make notarize DEV_ID="Developer ID Application: Jane Doe (ABCDE12345)" \
#                 KEYCHAIN_PROFILE=DialControllerNotary
DEV_ID           ?=
KEYCHAIN_PROFILE ?= DialControllerNotary

.PHONY: build bundle run clean sign-release zip notarize staple release

## Compile
build:
	swift build -c release

## Assemble .app bundle and sign ad-hoc (default – good for local runs)
bundle: build
	@echo "→ Assembling $(BUNDLE)…"
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS
	@mkdir -p $(BUNDLE)/Contents/Resources
	@cp $(BINARY_DIR)/$(APP) $(BUNDLE)/Contents/MacOS/$(APP)
	@cp Info.plist $(BUNDLE)/Contents/Info.plist
	@cp $(ICON) $(BUNDLE)/Contents/Resources/AppIcon.icns
	@echo "→ Signing (ad-hoc)…"
	@codesign --sign - \
	           --entitlements $(ENTITLEMENTS) \
	           --force \
	           --deep \
	           $(BUNDLE)
	@echo "✓ $(BUNDLE) ready."

## Build, bundle, and launch
run: bundle
	@echo "→ Launching $(BUNDLE)…"
	@open $(BUNDLE)

## Remove build artifacts
clean:
	@rm -rf .build $(BUNDLE) $(APP).zip

# ──────────────────────────────────────────────────────────────────────
# Release pipeline (requires a paid Apple Developer account)
#
# One-time setup:
#   1. Install your "Developer ID Application" certificate in the login keychain.
#      Verify with: security find-identity -v -p codesigning
#   2. Store notary credentials in the keychain once:
#      xcrun notarytool store-credentials DialControllerNotary \
#          --apple-id "you@example.com" \
#          --team-id  "ABCDE12345" \
#          --password "xxxx-xxxx-xxxx-xxxx"   # app-specific password
#
# Then build a signed, notarised, stapled app with a single command:
#   make release DEV_ID="Developer ID Application: Your Name (ABCDE12345)"
# ──────────────────────────────────────────────────────────────────────

## Re-sign an already-bundled .app with the Developer ID identity
sign-release: bundle
	@if [ -z "$(DEV_ID)" ]; then \
		echo "✗ DEV_ID is not set. Example:"; \
		echo "    make sign-release DEV_ID=\"Developer ID Application: Your Name (ABCDE12345)\""; \
		exit 1; \
	fi
	@echo "→ Re-signing with Developer ID: $(DEV_ID)"
	@codesign --sign "$(DEV_ID)" \
	           --entitlements $(ENTITLEMENTS) \
	           --options runtime \
	           --timestamp \
	           --force \
	           --deep \
	           $(BUNDLE)
	@codesign --verify --deep --strict --verbose=2 $(BUNDLE)

## Zip the signed bundle for notarisation upload
zip: sign-release
	@echo "→ Creating $(APP).zip…"
	@rm -f $(APP).zip
	@/usr/bin/ditto -c -k --keepParent $(BUNDLE) $(APP).zip

## Submit to Apple's notary service and wait for the verdict
notarize: zip
	@echo "→ Submitting $(APP).zip to notary service (keychain profile: $(KEYCHAIN_PROFILE))…"
	@xcrun notarytool submit $(APP).zip \
	       --keychain-profile "$(KEYCHAIN_PROFILE)" \
	       --wait

## Staple the notarisation ticket onto the app bundle
staple:
	@echo "→ Stapling notarisation ticket…"
	@xcrun stapler staple $(BUNDLE)
	@xcrun stapler validate $(BUNDLE)
	@spctl --assess --type execute --verbose=4 $(BUNDLE) || true

## Full release: sign → zip → notarize → staple
release: notarize staple
	@echo "✓ $(BUNDLE) is signed, notarised, and stapled."
