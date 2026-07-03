# glosa-av Makefile
# Build, test, and format the GlosaCore Swift library (Apple Silicon)

PACKAGE_SCHEME = glosa-av
DESTINATION = platform=macOS,arch=arm64
DERIVED_DATA = $(HOME)/Library/Developer/Xcode/DerivedData

.PHONY: all build clean test resolve format help

all: build

# Resolve all SPM package dependencies via xcodebuild
resolve:
	xcodebuild -resolvePackageDependencies -scheme $(PACKAGE_SCHEME) -destination '$(DESTINATION)'
	@echo "Package dependencies resolved."

# Development build with xcodebuild
build:
	xcodebuild build -scheme $(PACKAGE_SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO

# Run tests
test:
	xcodebuild test -scheme $(PACKAGE_SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO

# Format Swift source files
format:
	swift format -i -r Sources/ Tests/

# Clean build artifacts
clean:
	swift package clean
	rm -rf $(DERIVED_DATA)/glosa-av-*

help:
	@echo "glosa-av Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  resolve  - Resolve all SPM package dependencies"
	@echo "  build    - Development build (default)"
	@echo "  test     - Run tests"
	@echo "  format   - Format Swift source files with swift-format"
	@echo "  clean    - Clean build artifacts"
	@echo "  help     - Show this help"
	@echo ""
	@echo "GlosaCore is a Foundation-only library; there is no CLI binary."
	@echo "All builds target Apple Silicon: -destination '$(DESTINATION)'"
