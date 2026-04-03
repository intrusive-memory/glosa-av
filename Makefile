# glosa-av Makefile
# Build and install the glosa CLI for Apple Silicon

SCHEME = glosa
PACKAGE_SCHEME = glosa-av-Package
BINARY = glosa
RESOURCE_BUNDLE = glosa-av_GlosaDirector.bundle
BIN_DIR = ./bin
DESTINATION = platform=macOS,arch=arm64
DERIVED_DATA = $(HOME)/Library/Developer/Xcode/DerivedData

.PHONY: all build release install clean test resolve dist format help

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
		chmod +x $(BIN_DIR)/$(BINARY); \
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
		chmod +x $(BIN_DIR)/$(BINARY); \
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

# Create distributable tarball for Homebrew
dist: release
	@echo "Creating distribution tarball..."
	@mkdir -p dist
	@VERSION=$$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0"); \
	PRODUCT_DIR=$$(find $(DERIVED_DATA)/glosa-av-*/Build/Products/Release -name $(BINARY) -type f 2>/dev/null | head -1 | xargs dirname); \
	if [ -z "$$PRODUCT_DIR" ] || [ ! -f "$$PRODUCT_DIR/$(BINARY)" ]; then \
		echo "Error: Could not find $(BINARY) in DerivedData"; \
		exit 1; \
	fi; \
	mkdir -p $(BIN_DIR); \
	cp "$$PRODUCT_DIR/$(BINARY)" $(BIN_DIR)/; \
	chmod +x $(BIN_DIR)/$(BINARY); \
	TARBALL_CONTENTS="$(BINARY)"; \
	if [ -d "$$PRODUCT_DIR/$(RESOURCE_BUNDLE)" ]; then \
		rm -rf $(BIN_DIR)/$(RESOURCE_BUNDLE); \
		cp -R "$$PRODUCT_DIR/$(RESOURCE_BUNDLE)" $(BIN_DIR)/; \
		TARBALL_CONTENTS="$$TARBALL_CONTENTS $(RESOURCE_BUNDLE)"; \
	fi; \
	tar -C $(BIN_DIR) -czvf dist/$(BINARY)-$$VERSION-arm64-macos.tar.gz $$TARBALL_CONTENTS; \
	SHA256=$$(shasum -a 256 dist/$(BINARY)-$$VERSION-arm64-macos.tar.gz | cut -d' ' -f1); \
	echo ""; \
	echo "=== Distribution Package ==="; \
	echo "Tarball: dist/$(BINARY)-$$VERSION-arm64-macos.tar.gz"; \
	echo "SHA256:  $$SHA256"; \
	ls -lh dist/$(BINARY)-$$VERSION-arm64-macos.tar.gz

# Format Swift source files
format:
	swift format -i -r Sources/ Tests/

# Clean build artifacts
clean:
	swift package clean
	rm -rf $(BIN_DIR)
	rm -rf dist
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
	@echo "  dist     - Create distributable tarball for Homebrew"
	@echo "  test     - Run tests"
	@echo "  format   - Format Swift source files with swift-format"
	@echo "  clean    - Clean build artifacts"
	@echo "  help     - Show this help"
	@echo ""
	@echo "All builds target Apple Silicon: -destination '$(DESTINATION)'"
