#!/usr/bin/env node

/**
 * ControlKeel Bootstrap Installer
 * 
 * This is a bootstrap package for the ControlKeel native CLI.
 * The main entry point re-exports the binary functionality.
 * 
 * For programmatic use, the package downloads and manages the native
 * ControlKeel binary from GitHub Releases.
 */

const { ensureBinary } = require("./lib/install");

/**
 * Ensure the ControlKeel binary is downloaded and available.
 * @param {Object} options - Options for binary download
 * @param {boolean} options.forceDownload - Force re-download even if binary exists
 * @returns {Promise<string>} Path to the downloaded binary
 */
async function getBinaryPath(options = {}) {
  return await ensureBinary(options);
}

/**
 * Main entry point for when this package is required programmatically.
 */
module.exports = {
  getBinaryPath,
  ensureBinary
};

// If run directly, execute the CLI
if (require.main === module) {
  const { spawn } = require("node:child_process");
  
  getBinaryPath({ forceDownload: false }).then((binaryPath) => {
    const child = spawn(binaryPath, process.argv.slice(2), { stdio: "inherit" });
    
    child.on("exit", (code, signal) => {
      if (signal) {
        process.kill(process.pid, signal);
        return;
      }
      process.exit(code ?? 0);
    });
  }).catch((error) => {
    console.error(error.message || error);
    process.exit(1);
  });
}