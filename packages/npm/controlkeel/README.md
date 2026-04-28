# @aryaminus/controlkeel

This package is a bootstrap installer for the native ControlKeel CLI.

Both npmjs and GitHub Packages publish the same bootstrap package. In both cases, installation downloads the matching native ControlKeel binary from GitHub Releases.

## Install

```bash
npm i -g @aryaminus/controlkeel
# or: pnpm add -g @aryaminus/controlkeel
# or: yarn global add @aryaminus/controlkeel

# one-off run
npx @aryaminus/controlkeel@latest
```

The package installs and exposes the `controlkeel` command.

Published companion packages that tie into the main CLI:

- [`@aryaminus/controlkeel-opencode`](https://www.npmjs.com/package/@aryaminus/controlkeel-opencode) for OpenCode plugin installs
- [`@aryaminus/controlkeel-pi-extension`](https://www.npmjs.com/package/@aryaminus/controlkeel-pi-extension) for Pi extension installs

Main project docs:

- [Repository README](https://github.com/aryaminus/controlkeel#readme)
- [Getting started](https://github.com/aryaminus/controlkeel/blob/main/docs/getting-started.md)
- [Direct host installs](https://github.com/aryaminus/controlkeel/blob/main/docs/direct-host-installs.md)
- [Support matrix](https://github.com/aryaminus/controlkeel/blob/main/docs/support-matrix.md)

You can also install the same bootstrap package from GitHub Packages:

```bash
echo "@aryaminus:registry=https://npm.pkg.github.com" >> ~/.npmrc
echo "//npm.pkg.github.com/:_authToken=YOUR_GITHUB_TOKEN_WITH_READ_PACKAGES" >> ~/.npmrc
npm i -g @aryaminus/controlkeel --registry=https://npm.pkg.github.com
```

## Security

This package uses a postinstall script to download the native ControlKeel binary from GitHub Releases. This is intentional and necessary for cross-platform distribution. For detailed information about security practices and how the postinstall script works, see [SECURITY.md](SECURITY.md).

To skip automatic binary download, set the environment variable:

```bash
CONTROLKEEL_SKIP_DOWNLOAD=1 npm i -g @aryaminus/controlkeel
```

<!-- mcp-name: io.github.aryaminus/controlkeel -->
