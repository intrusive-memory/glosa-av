# Claude-Specific Agent Instructions

**Read [AGENTS.md](AGENTS.md) first** for universal project documentation.

This file contains instructions specific to Claude Code agents working on glosa-av.

## Build Preferences

- **ALWAYS use `xcodebuild`** for building and testing — never use `swift build` or `swift test`
- Use XcodeBuildMCP tools when available (`swift_package_build`, `swift_package_test`)
- Build command: `xcodebuild build -scheme glosa-av-Package -destination 'platform=macOS'`
- Test command: `xcodebuild test -scheme glosa-av-Package -destination 'platform=macOS'`

## Formatting

Format all Swift source files before committing:

```bash
swift format -i -r Sources/ Tests/
```

## MCP Server Configuration

### XcodeBuildMCP

When XcodeBuildMCP is available, prefer its structured tools over raw xcodebuild commands:

- **Build**: `swift_package_build` or `build_macos`
- **Test**: `swift_package_test` or `test_macos`
- **Discover**: `discover_projs`, `list_schemes`
- **Clean**: `clean`, `swift_package_clean`

## App Group configuration

See [AGENTS.md](./AGENTS.md) § App Group configuration (required).

## Claude-Specific Critical Rules

1. ALWAYS use XcodeBuildMCP tools when available
2. NEVER use `swift build` or `swift test`
3. Follow global `~/.claude/CLAUDE.md` patterns (communication style, security, CI/CD)
4. Format Swift source with `swift format` before committing
