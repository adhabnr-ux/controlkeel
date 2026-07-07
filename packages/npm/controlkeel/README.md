# @aryaminus/controlkeel

This package is a bootstrap installer for the native ControlKeel CLI.

Both npmjs and GitHub Packages publish the same bootstrap package. The native binary is downloaded from GitHub Releases on first use, not during installation.

## Install

```bash
npm i -g @aryaminus/controlkeel
# or: pnpm add -g @aryaminus/controlkeel
# or: yarn global add @aryaminus/controlkeel

# one-off run
npx @aryaminus/controlkeel@latest
```

The package installs the `controlkeel` command. The native binary is automatically downloaded on first use.

Published companion packages that tie into the main CLI:

- [`@aryaminus/controlkeel-opencode`](https://www.npmjs.com/package/@aryaminus/controlkeel-opencode) for OpenCode plugin installs
- [`@aryaminus/controlkeel-pi-extension`](https://www.npmjs.com/package/@aryaminus/controlkeel-pi-extension) for Pi extension installs

Main project docs:

- [Repository README](https://github.com/aryaminus/controlkeel#readme)
- [Getting started](https://github.com/aryaminus/controlkeel/blob/main/docs/getting-started.md)
- [Agent integrations](https://github.com/aryaminus/controlkeel/blob/main/docs/agent-integrations.md)
- [Support matrix](https://github.com/aryaminus/controlkeel/blob/main/docs/support-matrix.md)

You can also install the same bootstrap package from GitHub Packages:

```bash
echo "@aryaminus:registry=https://npm.pkg.github.com" >> ~/.npmrc
echo "//npm.pkg.github.com/:_authToken=YOUR_GITHUB_TOKEN_WITH_READ_PACKAGES" >> ~/.npmrc
npm i -g @aryaminus/controlkeel --registry=https://npm.pkg.github.com
```

## Security

This package uses a lazy download model for maximum security:

- No install scripts (removed postinstall)
- No environment variable access (hardcoded configuration)
- Plain GitHub Release URLs for transparent scanner and reviewer visibility
- SHA-256 checksum verification for all downloads

The native binary is downloaded on first use rather than during installation. For detailed information about security practices, see [SECURITY.md](SECURITY.md).

For manual installation, download the binary from [GitHub Releases](https://github.com/aryaminus/controlkeel/releases/latest) and place it in the `vendor/` directory.

<!-- mcp-name: io.github.aryaminus/controlkeel -->
