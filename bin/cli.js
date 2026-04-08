#!/usr/bin/env node
'use strict';

const { spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const PKG_ROOT = path.resolve(__dirname, '..');
const INSTALL_SH = path.join(PKG_ROOT, 'plugin', 'install.sh');
const VERSION = JSON.parse(fs.readFileSync(path.join(PKG_ROOT, 'package.json'), 'utf8')).version;

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
    cmdUpgrade();
    break;

  case 'uninstall':
    cmdUninstall();
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
  codex-vault upgrade       Upgrade existing vault to latest version
  codex-vault uninstall     Remove vault integration (preserves vault data)
  codex-vault -v, --version Print version
  codex-vault -h, --help    Print this help`);
}

function assertBash() {
  const bashCheck = spawnSync('bash', ['--version'], { stdio: 'ignore' });
  if (bashCheck.error) {
    console.error('Error: bash is not available.');
    console.error('On Windows, please install Git Bash or WSL.');
    process.exit(1);
  }
}

function findVersionFile() {
  // Check .vault first (new default), then vault (legacy)
  for (const dir of ['.vault', 'vault']) {
    const f = path.join(process.cwd(), dir, '.codex-vault', 'version');
    if (fs.existsSync(f)) return f;
  }
  return null;
}

function findLegacyVersionFile() {
  for (const dir of ['.vault', 'vault']) {
    const f = path.join(process.cwd(), dir, '.codex-mem', 'version');
    if (fs.existsSync(f)) return f;
  }
  return null;
}

function defaultVersionFile() {
  return path.join(process.cwd(), '.vault', '.codex-vault', 'version');
}

function runInit() {
  assertBash();

  // Check if already installed (including legacy codex-mem)
  const versionFile = findVersionFile();
  const legacyVersionFile = findLegacyVersionFile();
  if (versionFile) {
    const installed = fs.readFileSync(versionFile, 'utf8').trim();
    console.log(`codex-vault v${installed} is already installed in this directory.`);
    console.log('Run "codex-vault upgrade" to update, or remove .vault/.codex-vault/version to reinstall.');
    return;
  }
  if (legacyVersionFile) {
    const installed = fs.readFileSync(legacyVersionFile, 'utf8').trim();
    console.log(`Legacy codex-mem v${installed} detected.`);
    console.log('Run "codex-vault uninstall" first, then "codex-vault init".');
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
  const targetVersionFile = defaultVersionFile();
  const versionDir = path.dirname(targetVersionFile);
  fs.mkdirSync(versionDir, { recursive: true });
  fs.writeFileSync(targetVersionFile, VERSION + '\n');
  console.log(`\ncodex-vault v${VERSION} installed successfully.`);
}

/**
 * Detect if this is a standalone install (inside the codex-vault repo itself).
 * Mirrors the logic in install.sh.
 */
function isStandaloneMode() {
  const cwd = process.cwd();
  // Check if install.sh exists relative to cwd (i.e. we're inside the repo)
  const installSh = path.join(cwd, 'plugin', 'install.sh');
  if (!fs.existsSync(installSh)) return false;
  // Standalone if vault/ exists at repo root alongside plugin/
  const vaultInRepo = path.join(cwd, 'vault', 'Home.md');
  return fs.existsSync(vaultInRepo);
}

/**
 * Migrate vault/ → .vault/ for integrated installs.
 * Moves user data, removes old agent configs, updates .gitignore.
 * Returns true if migration happened.
 */
function migrateVaultDir() {
  const cwd = process.cwd();
  const oldDir = path.join(cwd, 'vault');
  const newDir = path.join(cwd, '.vault');

  // Only migrate if: old vault/ exists, .vault/ does NOT exist, and NOT standalone mode
  if (!fs.existsSync(oldDir) || fs.existsSync(newDir) || isStandaloneMode()) {
    return false;
  }

  // Must have Home.md to confirm it's a real vault
  if (!fs.existsSync(path.join(oldDir, 'Home.md'))) {
    return false;
  }

  console.log('  [*] Migrating vault/ → .vault/ ...');
  fs.renameSync(oldDir, newDir);
  console.log('  [+] Moved vault data to .vault/');

  // Remove old agent configs (install.sh will regenerate at project root)
  for (const sub of ['.claude', '.codex', 'CLAUDE.md', 'AGENTS.md']) {
    const p = path.join(newDir, sub);
    if (fs.existsSync(p)) {
      fs.rmSync(p, { recursive: true, force: true });
    }
  }

  // Add .vault/ to .gitignore
  const gitignorePath = path.join(cwd, '.gitignore');
  if (fs.existsSync(gitignorePath)) {
    const content = fs.readFileSync(gitignorePath, 'utf8');
    if (!content.includes('.vault/') && !content.match(/^\.vault$/m)) {
      fs.appendFileSync(gitignorePath, '\n# Codex-Vault — local knowledge base (per-user, not shared)\n.vault/\n');
      console.log('  [+] Added .vault/ to .gitignore');
    }
  } else {
    fs.writeFileSync(gitignorePath, '# Codex-Vault — local knowledge base (per-user, not shared)\n.vault/\n');
    console.log('  [+] Created .gitignore with .vault/');
  }

  console.log('  [+] Migration complete — vault data preserved in .vault/');
  return true;
}

function cmdUpgrade() {
  assertBash();

  // Check if installed (including legacy codex-mem)
  const versionFile = findVersionFile();
  const legacyVersionFile = findLegacyVersionFile();
  if (!versionFile && !legacyVersionFile) {
    console.error('codex-vault is not installed in this directory.');
    console.error('Run "codex-vault init" first.');
    process.exit(1);
  }
  if (!versionFile && legacyVersionFile) {
    console.error('Legacy codex-mem installation detected.');
    console.error('Run "codex-vault uninstall" first, then "codex-vault init".');
    process.exit(1);
  }

  const installedVersion = fs.readFileSync(versionFile, 'utf8').trim();

  // Already up to date?
  if (installedVersion === VERSION) {
    console.log(`Already at v${VERSION}.`);
    return;
  }

  console.log(`Upgrading: v${installedVersion} → v${VERSION}`);

  // Migrate vault/ → .vault/ if this is an integrated install with old layout
  const migrated = migrateVaultDir();

  // Run install.sh (hooks + skills are regenerated)
  const result = spawnSync('bash', [INSTALL_SH], {
    cwd: process.cwd(),
    stdio: 'inherit',
  });

  if (result.error) {
    console.error('Failed to run install.sh:', result.error.message);
    process.exit(1);
  }

  if (result.status !== 0) {
    console.error('install.sh exited with errors.');
    process.exit(result.status);
  }

  // Update version file at new location
  const targetVersionFile = migrated ? defaultVersionFile() : versionFile;
  const versionDir = path.dirname(targetVersionFile);
  fs.mkdirSync(versionDir, { recursive: true });
  fs.writeFileSync(targetVersionFile, VERSION + '\n');

  if (migrated) {
    console.log('\n  Note: vault/ has been renamed to .vault/ (gitignored, per-user).');
    console.log('  Your data is preserved. Other team members need their own .vault/.');
  }

  console.log(`\nUpgraded to v${VERSION} successfully.`);
}

// ---------------------------------------------------------------------------
// uninstall
// ---------------------------------------------------------------------------

function cmdUninstall() {
  const cwd = process.cwd();
  const versionFile = findVersionFile();
  const legacyVersionFile = findLegacyVersionFile();

  // 1. Check installation
  if (!versionFile && !legacyVersionFile) {
    console.error('codex-vault is not installed in this directory.');
    console.error('Nothing to uninstall.');
    process.exit(1);
  }

  const activeVersionFile = versionFile || legacyVersionFile;
  const installedVersion = fs.readFileSync(activeVersionFile, 'utf8').trim();
  console.log(`Uninstalling codex-vault v${installedVersion}...`);

  // 2. Remove vault directories (.vault and/or vault)
  for (const dir of ['.vault', 'vault']) {
    const vaultDir = path.join(cwd, dir);
    if (fs.existsSync(vaultDir)) {
      fs.rmSync(vaultDir, { recursive: true, force: true });
      console.log(`  [x] Removed ${dir}/ (all data deleted)`);
    }
  }

  // 3. Clean .claude/settings.json
  cleanHooksJson(path.join(cwd, '.claude', 'settings.json'), '.claude/settings.json');

  // 4. Clean .codex/hooks.json
  cleanHooksJson(path.join(cwd, '.codex', 'hooks.json'), '.codex/hooks.json');

  // 5. Clean .codex/config.toml
  cleanCodexConfigToml(cwd);

  // 6. Remove skills
  const SKILL_NAMES = ['dump', 'ingest', 'lint', 'recall', 'wrap-up'];
  removeSkills(path.join(cwd, '.claude'), '.claude', SKILL_NAMES);
  removeSkills(path.join(cwd, '.codex'), '.codex', SKILL_NAMES);

  // 7. Clean CLAUDE.md
  cleanInstructionFile(path.join(cwd, 'CLAUDE.md'), 'CLAUDE.md');

  // 8. AGENTS.md — leave untouched (may contain user's own agent instructions)

  // Summary
  console.log('\ncodex-vault has been uninstalled.');
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

/**
 * Remove codex-vault hook entries from a JSON hooks file
 * (.claude/settings.json or .codex/hooks.json).
 */
function cleanHooksJson(filePath, label) {
  if (!fs.existsSync(filePath)) return;

  let data;
  try {
    data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (e) {
    console.log(`  [!] Could not parse ${label} — skipping (${e.message})`);
    return;
  }

  if (!data.hooks || typeof data.hooks !== 'object') return;

  let changed = false;
  for (const event of Object.keys(data.hooks)) {
    const entries = data.hooks[event];
    if (!Array.isArray(entries)) continue;

    const filtered = entries.filter((entry) => {
      const hooks = entry.hooks || [];
      // Keep the entry only if none of its hook commands belong to codex-vault
      const isVaultEntry = hooks.some(
        (h) => typeof h.command === 'string' &&
          (h.command.includes('codex-vault/hooks/') || h.command.includes('codex-mem/hooks/') || h.command.includes('.vault/'))
      );
      return !isVaultEntry;
    });

    if (filtered.length !== entries.length) {
      changed = true;
      if (filtered.length === 0) {
        delete data.hooks[event];
      } else {
        data.hooks[event] = filtered;
      }
    }
  }

  if (!changed) return;

  // If hooks object is now empty, remove it
  if (Object.keys(data.hooks).length === 0) {
    delete data.hooks;
  }

  // If entire JSON is now empty, delete the file
  if (Object.keys(data).length === 0) {
    fs.unlinkSync(filePath);
    console.log(`  [x] Removed ${label} (empty after cleanup)`);
  } else {
    fs.writeFileSync(filePath, JSON.stringify(data, null, 2) + '\n');
    console.log(`  [x] Cleaned codex-vault hooks from ${label}`);
  }
}

/**
 * Remove codex_hooks feature flag from .codex/config.toml.
 */
function cleanCodexConfigToml(cwd) {
  const filePath = path.join(cwd, '.codex', 'config.toml');
  if (!fs.existsSync(filePath)) return;

  let content = fs.readFileSync(filePath, 'utf8');
  const original = content;

  // Remove lines containing codex_hooks
  content = content.replace(/^.*codex_hooks.*\n?/gm, '');

  // Remove empty [features] section (only whitespace/empty lines after header until next section or EOF)
  content = content.replace(/^\[features\]\s*\n(?=\[|$)/gm, '');
  // Also handle [features] at very end of file with nothing after it
  content = content.replace(/^\[features\]\s*$/gm, '');

  // Trim trailing whitespace
  content = content.replace(/\n+$/, content.trim() === '' ? '' : '\n');

  if (content === original) return;

  if (content.trim() === '') {
    fs.unlinkSync(filePath);
    console.log('  [x] Removed .codex/config.toml (empty after cleanup)');
  } else {
    fs.writeFileSync(filePath, content);
    console.log('  [x] Cleaned codex_hooks from .codex/config.toml');
  }
}

/**
 * Remove codex-vault skill directories from an agent config dir.
 */
function removeSkills(agentDir, label, skillNames) {
  const skillsDir = path.join(agentDir, 'skills');
  if (!fs.existsSync(skillsDir)) return;

  let removed = 0;
  for (const name of skillNames) {
    const skillDir = path.join(skillsDir, name);
    if (fs.existsSync(skillDir)) {
      fs.rmSync(skillDir, { recursive: true, force: true });
      removed++;
    }
  }

  if (removed === 0) return;

  console.log(`  [x] Removed ${removed} skills from ${label}/skills/`);

  // Clean up empty skills/ directory only — never delete the agent dir itself
  if (isDirEmpty(skillsDir)) {
    fs.rmdirSync(skillsDir);
  }
}

/**
 * Remove the # Codex-Vault section from CLAUDE.md.
 * The section may be preceded by a --- separator (appended by install.sh).
 * Removes from the separator (or heading) through EOF or the next --- + # heading.
 */
function cleanInstructionFile(filePath, label) {
  if (!fs.existsSync(filePath)) return;

  const content = fs.readFileSync(filePath, 'utf8');
  const lines = content.split('\n');

  // Find the "# Codex-Vault" heading
  let sectionStart = -1;
  for (let i = 0; i < lines.length; i++) {
    if (/^# Codex-Vault/.test(lines[i])) {
      sectionStart = i;
      break;
    }
  }

  if (sectionStart === -1) return;

  // Check if preceded by --- separator (possibly with blank lines between)
  let cutStart = sectionStart;
  for (let i = sectionStart - 1; i >= 0; i--) {
    if (lines[i].trim() === '') continue;
    if (lines[i].trim() === '---') {
      cutStart = i;
    }
    break;
  }

  // Find the end: next --- followed by # heading, or EOF
  let cutEnd = lines.length;
  for (let i = sectionStart + 1; i < lines.length; i++) {
    if (lines[i].trim() === '---' && i + 1 < lines.length && /^# /.test(lines[i + 1])) {
      cutEnd = i;
      break;
    }
  }

  // Build remaining content
  const before = lines.slice(0, cutStart);
  const after = lines.slice(cutEnd);
  let remaining = before.concat(after).join('\n');

  // Trim trailing whitespace/newlines
  remaining = remaining.replace(/\s+$/, '');

  if (remaining === '') {
    fs.unlinkSync(filePath);
    console.log(`  [x] Removed ${label} (empty after cleanup)`);
  } else {
    fs.writeFileSync(filePath, remaining + '\n');
    console.log(`  [x] Cleaned codex-vault section from ${label}`);
  }
}


/**
 * Check if a directory is empty.
 */
function isDirEmpty(dirPath) {
  try {
    const entries = fs.readdirSync(dirPath);
    return entries.length === 0;
  } catch (e) {
    return false;
  }
}

