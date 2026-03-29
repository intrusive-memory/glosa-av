# Gemini-Specific Agent Instructions

**Read [AGENTS.md](AGENTS.md) first** for universal project documentation.

This file contains instructions specific to Google Gemini agents working on glosa-av.

## Build and Test Commands

Use standard xcodebuild commands (no MCP access):

```bash
# Build
xcodebuild build -scheme glosa-av-Package -destination 'platform=macOS'

# Test
xcodebuild test -scheme glosa-av-Package -destination 'platform=macOS'

# Resolve dependencies
xcodebuild -resolvePackageDependencies -scheme glosa-av-Package -destination 'platform=macOS'
```

## Formatting

Format all Swift source files before committing:

```bash
swift format -i -r Sources/ Tests/
```

## Gemini-Specific Critical Rules

1. Use standard CLI tools (`xcodebuild`, `git`, `swift format`)
2. NEVER use `swift build` or `swift test` — always use `xcodebuild`
3. Follow the testing requirements in AGENTS.md before committing
