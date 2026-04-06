#!/usr/bin/env node
'use strict';

const { spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const PKG_ROOT = path.resolve(__dirname, '..');
const INSTALL_SH = path.join(PKG_ROOT, 'plugin', 'install.sh');
const VERSION = fs.readFileSync(path.join(PKG_ROOT, 'plugin', 'VERSION'), 'utf8').trim();

const args = process.argv.slice(2);
const cmd = args[0] || 'init';

switch (cmd) {
  case '--version':
  case '-v':
    console.log(VERSION);
    break;

  case '--help':
  case '-h':
    printHelp();
    break;

  case 'init':
    runInit();
    break;

  case 'upgrade':
  case 'uninstall':
    console.log(`"${cmd}" is coming in v0.2.0.`);
    break;

  default:
    console.error(`Unknown command: ${cmd}\n`);
    printHelp();
    process.exit(1);
}

function printHelp() {
  console.log(`codex-vault v${VERSION}

Usage:
  codex-vault init          Install vault into current directory (default)
  codex-vault upgrade       Upgrade vault (coming in v0.2.0)
  codex-vault uninstall     Remove vault  (coming in v0.2.0)
  codex-vault -v, --version Print version
  codex-vault -h, --help    Print this help`);
}

function runInit() {
  // Check bash availability
  const bashCheck = spawnSync('bash', ['--version'], { stdio: 'ignore' });
  if (bashCheck.error) {
    console.error('Error: bash is not available.');
    console.error('On Windows, please install Git Bash or WSL.');
    process.exit(1);
  }

  // Check if already installed
  const versionFile = path.join(process.cwd(), 'vault', '.codex-vault', 'version');
  if (fs.existsSync(versionFile)) {
    const installed = fs.readFileSync(versionFile, 'utf8').trim();
    console.log(`codex-vault v${installed} is already installed in this directory.`);
    console.log('To reinstall, remove vault/.codex-vault/version first.');
    return;
  }

  // Run install.sh
  const result = spawnSync('bash', [INSTALL_SH], {
    cwd: process.cwd(),
    stdio: 'inherit',
  });

  if (result.error) {
    console.error('Failed to run install.sh:', result.error.message);
    process.exit(1);
  }

  if (result.status !== 0) {
    process.exit(result.status);
  }

  // Write version file on success
  const versionDir = path.dirname(versionFile);
  fs.mkdirSync(versionDir, { recursive: true });
  fs.writeFileSync(versionFile, VERSION + '\n');
  console.log(`\ncodex-vault v${VERSION} installed successfully.`);
}
