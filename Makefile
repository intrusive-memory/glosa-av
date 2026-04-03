# glosa-av Makefile
# Build and install the glosa CLI for Apple Silicon

SCHEME = glosa
PACKAGE_SCHEME = glosa-av-Package
BINARY = glosa
RESOURCE_BUNDLE = glosa-av_GlosaDirector.bundle
BIN_DIR = ./bin
DESTINATION = platform=macOS,arch=arm64
DERIVED_DATA = $(HOME)/Library/Developer/Xcode/DerivedData

.PHONY: all build release install clean test resolve help

all: install

# Resolve all SPM package dependencies via xcodebuild
resolve:
	xcodebuild -resolvePackageDependencies -scheme $(PACKAGE_SCHEME) -destination '$(DESTINATION)'
	@echo "Package dependencies resolved."

# Development build with xcodebuild
build:
	xcodebuild build -scheme $(PACKAGE_SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO

# Release build with xcodebuild + copy to bin
release: resolve
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' -configuration Release build
	@mkdir -p $(BIN_DIR)
	@PRODUCT_DIR=$$(find $(DERIVED_DATA)/glosa-av-*/Build/Products/Release -name $(BINARY) -type f 2>/dev/null | head -1 | xargs dirname); \
	if [ -n "$$PRODUCT_DIR" ]; then \
		cp "$$PRODUCT_DIR/$(BINARY)" $(BIN_DIR)/; \
		for BUNDLE in $(RESOURCE_BUNDLE) mlx-swift_Cmlx.bundle; do \
			if [ -d "$$PRODUCT_DIR/$$BUNDLE" ]; then \
				rm -rf $(BIN_DIR)/$$BUNDLE; \
				cp -R "$$PRODUCT_DIR/$$BUNDLE" $(BIN_DIR)/; \
			fi; \
		done; \
		echo "Installed $(BINARY) to $(BIN_DIR)/ (Release)"; \
	else \
		echo "Error: Could not find $(BINARY) in DerivedData"; \
		exit 1; \
	fi

# Debug build with xcodebuild + copy to bin (default)
install: resolve
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' build
	@mkdir -p $(BIN_DIR)
	@PRODUCT_DIR=$$(find $(DERIVED_DATA)/glosa-av-*/Build/Products/Debug -name $(BINARY) -type f 2>/dev/null | head -1 | xargs dirname); \
	if [ -n "$$PRODUCT_DIR" ]; then \
		cp "$$PRODUCT_DIR/$(BINARY)" $(BIN_DIR)/; \
		for BUNDLE in $(RESOURCE_BUNDLE) mlx-swift_Cmlx.bundle; do \
			if [ -d "$$PRODUCT_DIR/$$BUNDLE" ]; then \
				rm -rf $(BIN_DIR)/$$BUNDLE; \
				cp -R "$$PRODUCT_DIR/$$BUNDLE" $(BIN_DIR)/; \
			fi; \
		done; \
		echo "Installed $(BINARY) to $(BIN_DIR)/ (Debug)"; \
	else \
		echo "Error: Could not find $(BINARY) in DerivedData"; \
		exit 1; \
	fi

# Run tests
test:
	xcodebuild test -scheme $(PACKAGE_SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO

# Clean build artifacts
clean:
	swift package clean
	rm -rf $(BIN_DIR)
	rm -rf $(DERIVED_DATA)/glosa-av-*

help:
	@echo "glosa-av Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  resolve  - Resolve all SPM package dependencies"
	@echo "  build    - Development build (all targets)"
	@echo "  install  - Debug build + copy glosa binary to ./bin (default)"
	@echo "  release  - Release build + copy glosa binary to ./bin"
	@echo "  test     - Run tests"
	@echo "  clean    - Clean build artifacts"
	@echo "  help     - Show this help"
	@echo ""
	@echo "All builds target Apple Silicon: -destination '$(DESTINATION)'"
