# Security Policy

## Postinstall Script

This package uses a `postinstall` script to download the native ControlKeel binary from GitHub Releases. This is intentional and necessary for the following reasons:

### Why the postinstall script exists

ControlKeel is a native CLI tool written in Rust/Elixir that needs to be distributed as platform-specific binaries. Rather than requiring users to manually download the correct binary for their platform, this npm package serves as a bootstrap installer that:

1. Detects the user's platform (OS and architecture)
2. Downloads the appropriate pre-compiled binary from GitHub Releases
3. Makes it available as the `controlkeel` command

### What the postinstall script does

The `postinstall` script (`lib/postinstall.js`) performs the following actions:

- Calls `ensureBinary()` to download the platform-specific binary
- Downloads from official GitHub Releases: `https://github.com/aryaminus/controlkeel/releases/latest`
- Verifies the download and places the binary in the appropriate location
- Can be skipped by setting the environment variable `CONTROLKEEL_SKIP_DOWNLOAD=1`

### Security considerations

- **Source**: Binaries are downloaded exclusively from official GitHub Releases
- **Checksum verification**: After download, the installer fetches `SHASUMS256.txt` from the same release and verifies the SHA-256 digest of the downloaded binary before installing it. A mismatch causes the install to fail and the partial download is removed.
- **Transparency**: The source code for the bootstrap installer is fully visible in this repository
- **Opt-out**: Users can skip automatic download by setting `CONTROLKEEL_SKIP_DOWNLOAD=1`
- **No external dependencies**: The bootstrap installer has no runtime dependencies beyond Node.js built-ins

### Manual verification

Users who prefer manual verification can:

1. Set `CONTROLKEEL_SKIP_DOWNLOAD=1` to prevent automatic download
2. Download the binary directly from [GitHub Releases](https://github.com/aryaminus/controlkeel/releases/latest)
3. Verify the checksums provided in the release notes
4. Place the binary in their PATH manually

## Reporting Security Issues

If you discover a security vulnerability, please report it responsibly:

1. Do not open a public issue
2. Email security details to: [security contact to be added]
3. Include steps to reproduce and expected impact
4. Allow time for the issue to be investigated and fixed before disclosure

## Supported Versions

Security updates are provided for the latest version of the package. Users are encouraged to keep their installation up to date.

## Supply Chain Security

This package is designed with supply chain security in mind:

- **Minimal attack surface**: The bootstrap installer has no external dependencies
- **Reproducible builds**: Native binaries are built from source in CI/CD
- **Signed releases**: GitHub Releases provide cryptographic verification
- **Transparent source**: All installer code is open and auditable

For detailed information about the native binary build process and security practices, see the main repository's [security documentation](https://github.com/aryaminus/controlkeel/blob/main/SECURITY.md).
