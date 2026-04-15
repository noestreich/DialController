APP         = DialController
BUNDLE      = $(APP).app
BINARY_DIR  = .build/release
ENTITLEMENTS = $(APP).entitlements

.PHONY: build bundle run clean

## Compile
build:
	swift build -c release

## Assemble .app bundle and sign ad-hoc
bundle: build
	@echo "→ Assembling $(BUNDLE)…"
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS
	@mkdir -p $(BUNDLE)/Contents/Resources
	@cp $(BINARY_DIR)/$(APP) $(BUNDLE)/Contents/MacOS/$(APP)
	@cp Info.plist $(BUNDLE)/Contents/Info.plist
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
	@rm -rf .build $(BUNDLE)
