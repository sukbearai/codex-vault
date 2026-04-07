#!/bin/bash
set -eo pipefail

# Codex-Vault End-to-End Test Suite
# Simulates a real user: install → session-start → classify → validate → full cycle
# Run from repo root: bash tests/test_e2e.sh

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d)
PASS=0
FAIL=0
ERRORS=()

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { ((PASS++)); echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { ((FAIL++)); ERRORS+=("$1: $2"); echo -e "  ${RED}FAIL${NC} $1 — $2"; }

echo "=== Codex-Vault E2E Tests ==="
echo "Repo:     $REPO_DIR"
echo "Test dir: $TEST_DIR"
echo ""

# ============================================================
echo "--- 1. Install ---"
# ============================================================

# Copy repo to test dir (simulate git clone)
cp -r "$REPO_DIR"/{plugin,vault,docs,README.md,LICENSE,.gitignore} "$TEST_DIR/"
cd "$TEST_DIR"
git init -q && git add -A && git commit -q -m "init"

# Run installer
OUTPUT=$(bash plugin/install.sh 2>&1)

# Check Claude Code config generated
if [ -f "vault/.claude/settings.json" ]; then
  pass "Claude Code settings.json generated"
else
  fail "Claude Code settings.json" "file not found"
fi

# Check Codex CLI config generated (only if codex is installed)
if command -v codex &>/dev/null; then
  if [ -f "vault/.codex/hooks.json" ]; then
    pass "Codex CLI hooks.json generated"
  else
    fail "Codex CLI hooks.json" "file not found"
  fi
  # Check Codex skills installed
  if [ -f "vault/.codex/skills/dump/SKILL.md" ]; then
    pass "Codex CLI skills installed"
  else
    fail "Codex CLI skills" "not found in vault/.codex/skills/"
  fi
  # Check hooks feature flag enabled
  if [ -f "vault/.codex/config.toml" ] && grep -q "codex_hooks = true" "vault/.codex/config.toml"; then
    pass "Codex CLI hooks feature flag enabled"
  else
    fail "Codex CLI config.toml" "hooks feature flag not set"
  fi
else
  echo -e "  ${YELLOW}SKIP${NC} Codex CLI hooks.json (codex not installed)"
fi

# Check CLAUDE.md generated
if [ -f "vault/CLAUDE.md" ]; then
  pass "CLAUDE.md generated"
  LINES=$(wc -l < vault/CLAUDE.md | tr -d ' ')
  if [ "$LINES" -gt 50 ]; then
    pass "CLAUDE.md has content ($LINES lines)"
  else
    fail "CLAUDE.md content" "only $LINES lines"
  fi
else
  fail "CLAUDE.md" "file not found"
fi

# Check commands copied
for cmd in dump wrap-up ingest recall; do
  if [ -f "vault/.claude/skills/$cmd/SKILL.md" ]; then
    pass "Skill /$cmd installed"
  else
    fail "Skill /$cmd" "not found in vault/.claude/skills/$cmd/SKILL.md"
  fi
done

# Check settings.json is valid JSON
if python3 -m json.tool vault/.claude/settings.json > /dev/null 2>&1; then
  pass "settings.json is valid JSON"
else
  fail "settings.json" "invalid JSON"
fi

echo ""

# ============================================================
echo "--- 2. SessionStart Hook ---"
# ============================================================

cd "$TEST_DIR/vault"

# Export vars that session-start.sh expects
export CLAUDE_PROJECT_DIR="$TEST_DIR/vault"

OUTPUT=$(bash ../plugin/hooks/session-start.sh 2>&1)

# Check sections exist
for section in "### Date" "### North Star" "### Recent Changes" "### Recent Operations" "### Active Work" "### Vault Files"; do
  if echo "$OUTPUT" | grep -q "$section"; then
    pass "session-start: $section present"
  else
    fail "session-start: $section" "section missing from output"
  fi
done

# Check North Star content injected
if echo "$OUTPUT" | grep -q "living document"; then
  pass "session-start: North Star content injected"
else
  fail "session-start: North Star" "content not found"
fi

# Check log.md entries shown
if echo "$OUTPUT" | grep -q "Initial vault setup"; then
  pass "session-start: log.md entries shown"
else
  fail "session-start: log.md" "entries not found"
fi

# Check vault files listed
if echo "$OUTPUT" | grep -q "Home.md"; then
  pass "session-start: vault files listed"
else
  fail "session-start: vault files" "Home.md not in listing"
fi

echo ""

# ============================================================
echo "--- 3. Classify Message Hook ---"
# ============================================================

cd "$TEST_DIR"

# Test DECISION signal
OUT=$(echo '{"prompt":"we decided to use PostgreSQL"}' | python3 plugin/hooks/classify-message.py)
if echo "$OUT" | grep -q "DECISION"; then
  pass "classify: DECISION signal triggers"
else
  fail "classify: DECISION" "signal not triggered"
fi

# Test WIN signal
OUT=$(echo '{"prompt":"kudos to the team, great feedback from users"}' | python3 plugin/hooks/classify-message.py)
if echo "$OUT" | grep -q "WIN"; then
  pass "classify: WIN signal triggers"
else
  fail "classify: WIN" "signal not triggered"
fi

# Test PROJECT UPDATE signal
OUT=$(echo '{"prompt":"sprint milestone reached"}' | python3 plugin/hooks/classify-message.py)
if echo "$OUT" | grep -q "PROJECT UPDATE"; then
  pass "classify: PROJECT UPDATE signal triggers"
else
  fail "classify: PROJECT UPDATE" "signal not triggered"
fi

# Test QUERY signal
OUT=$(echo '{"prompt":"how does the auth system work?"}' | python3 plugin/hooks/classify-message.py)
if echo "$OUT" | grep -q "QUERY"; then
  pass "classify: QUERY signal triggers"
else
  fail "classify: QUERY" "signal not triggered"
fi

# Test INGEST signal
OUT=$(echo '{"prompt":"ingest this article about databases"}' | python3 plugin/hooks/classify-message.py)
if echo "$OUT" | grep -q "INGEST"; then
  pass "classify: INGEST signal triggers"
else
  fail "classify: INGEST" "signal not triggered"
fi

# Test hints suggest skills, not auto-execution
OUT=$(echo '{"prompt":"we decided to use PostgreSQL"}' | python3 plugin/hooks/classify-message.py)
if echo "$OUT" | grep -q "suggest the user run /dump"; then
  pass "classify: DECISION hint points to /dump skill"
else
  fail "classify: DECISION skill hint" "expected '/dump' skill suggestion"
fi
if echo "$OUT" | grep -q "do NOT auto-execute"; then
  pass "classify: hints include no-auto-execute guard"
else
  fail "classify: no-auto-execute guard" "missing guard in output"
fi

# Test no false positive on normal message
OUT=$(echo '{"prompt":"fix the typo in line 42"}' | python3 plugin/hooks/classify-message.py)
if [ -z "$OUT" ]; then
  pass "classify: no false positive on normal message"
else
  fail "classify: false positive" "triggered on 'fix the typo in line 42': $OUT"
fi

# Test empty/malformed input
OUT=$(echo '{}' | python3 plugin/hooks/classify-message.py 2>&1); RC=$?
if [ $RC -eq 0 ]; then
  pass "classify: handles empty input gracefully"
else
  fail "classify: empty input" "exit code $RC"
fi

OUT=$(echo 'not json' | python3 plugin/hooks/classify-message.py 2>&1); RC=$?
if [ $RC -eq 0 ]; then
  pass "classify: handles malformed JSON gracefully"
else
  fail "classify: malformed JSON" "exit code $RC"
fi

echo ""

# ============================================================
echo "--- 4. Validate Write Hook ---"
# ============================================================

cd "$TEST_DIR"

# Test: valid vault note (should pass silently)
VALID_NOTE="$TEST_DIR/vault/work/active/Test Project.md"
mkdir -p "$TEST_DIR/vault/work/active"
cat > "$VALID_NOTE" << 'EOF'
---
date: "2026-04-06"
description: "Test project for E2E validation"
status: active
tags:
  - work-note
---

# Test Project

## Context

Testing the [[Codex-Vault]] vault system.

## Related

- [[Key Decisions]]
EOF

OUT=$(echo "{\"tool_input\":{\"file_path\":\"$VALID_NOTE\"}}" | python3 plugin/hooks/validate-write.py)
if [ -z "$OUT" ]; then
  pass "validate: valid note passes silently"
else
  fail "validate: valid note" "unexpected warnings: $OUT"
fi

# Test: note missing frontmatter
BAD_NOTE="$TEST_DIR/vault/work/active/Bad Note.md"
cat > "$BAD_NOTE" << 'EOF'
# No Frontmatter

This note has no YAML frontmatter and no wikilinks. It should trigger warnings.
It needs to be longer than 300 chars to trigger the wikilink check.
Here is some padding text to make it long enough for the validator to check.
More padding here to ensure we cross the 300 character threshold easily.
EOF

OUT=$(echo "{\"tool_input\":{\"file_path\":\"$BAD_NOTE\"}}" | python3 plugin/hooks/validate-write.py)
if echo "$OUT" | grep -q "Missing YAML frontmatter"; then
  pass "validate: detects missing frontmatter"
else
  fail "validate: missing frontmatter" "warning not generated"
fi
if echo "$OUT" | grep -q "wikilinks"; then
  pass "validate: detects missing wikilinks"
else
  fail "validate: missing wikilinks" "warning not generated"
fi

# Test: skips non-vault files
OUT=$(echo "{\"tool_input\":{\"file_path\":\"$TEST_DIR/vault/README.md\"}}" | python3 plugin/hooks/validate-write.py)
if [ -z "$OUT" ]; then
  pass "validate: skips README.md"
else
  fail "validate: skip README" "should have been skipped"
fi

OUT=$(echo "{\"tool_input\":{\"file_path\":\"$TEST_DIR/vault/templates/Work Note.md\"}}" | python3 plugin/hooks/validate-write.py)
if [ -z "$OUT" ]; then
  pass "validate: skips templates/"
else
  fail "validate: skip templates" "should have been skipped"
fi

# Test: handles missing file_path gracefully
OUT=$(echo '{"tool_input":{}}' | python3 plugin/hooks/validate-write.py 2>&1); RC=$?
if [ $RC -eq 0 ]; then
  pass "validate: handles missing file_path"
else
  fail "validate: missing file_path" "exit code $RC"
fi

echo ""

# ============================================================
echo "--- 5. Vault Structure Integrity ---"
# ============================================================

cd "$TEST_DIR/vault"

# Check all expected files exist
for f in Home.md log.md brain/North\ Star.md brain/Memories.md brain/Key\ Decisions.md brain/Patterns.md work/Index.md; do
  if [ -f "$f" ]; then
    pass "vault: $f exists"
  else
    fail "vault: $f" "file missing"
  fi
done

# Check all expected directories exist
for d in brain work/active work/archive templates thinking sources reference; do
  if [ -d "$d" ]; then
    pass "vault: $d/ exists"
  else
    fail "vault: $d/" "directory missing"
  fi
done

# Check frontmatter on vault notes
for f in Home.md brain/North\ Star.md brain/Memories.md brain/Key\ Decisions.md brain/Patterns.md work/Index.md log.md; do
  if head -1 "$f" | grep -q "^---"; then
    pass "vault: $f has frontmatter"
  else
    fail "vault: $f frontmatter" "missing YAML frontmatter"
  fi
done

# Check wikilinks exist in key files
for f in Home.md brain/Memories.md; do
  if grep -q "\[\[" "$f"; then
    pass "vault: $f has wikilinks"
  else
    fail "vault: $f wikilinks" "no [[wikilinks]] found"
  fi
done

# Check templates have placeholders
for f in templates/*.md; do
  if grep -q "{{" "$f"; then
    pass "vault: $(basename "$f") has placeholders"
  else
    fail "vault: $(basename "$f")" "no {{placeholders}} found"
  fi
done

echo ""

# ============================================================
echo "--- 6. Cross-File Consistency ---"
# ============================================================

# Check instructions.md mentions all directories that exist
INSTRUCTIONS="$TEST_DIR/plugin/instructions.md"
for dir in brain work sources reference thinking templates; do
  if grep -q "$dir" "$INSTRUCTIONS"; then
    pass "instructions.md: mentions $dir/"
  else
    fail "instructions.md: $dir/" "not mentioned"
  fi
done

# Check all 5 signals are in classify-message.py
CLASSIFY="$TEST_DIR/plugin/hooks/classify-message.py"
for signal in DECISION WIN "PROJECT UPDATE" QUERY INGEST; do
  if grep -q "\"$signal\"" "$CLASSIFY"; then
    pass "classify: signal $signal defined"
  else
    fail "classify: signal $signal" "not found in classify-message.py"
  fi
done

# Check README vault structure matches actual vault
README="$TEST_DIR/README.md"
for item in Home.md log.md brain work sources reference templates thinking; do
  if grep -q "$item" "$README"; then
    pass "README: mentions $item"
  else
    fail "README: $item" "not in vault structure section"
  fi
done

echo ""

# ============================================================
echo "--- 7. Integrated Mode Install ---"
# ============================================================

# Simulate a user project with existing config
INT_DIR=$(mktemp -d)
cd "$INT_DIR"
git init -q

# Pre-existing user config
mkdir -p .claude
echo '{"permissions":{"allow":["Read","Bash"]}}' > .claude/settings.json
echo "# My Cool Project" > CLAUDE.md
echo "Existing instructions here." >> CLAUDE.md

# Run installer from project root
OUTPUT=$(bash "$REPO_DIR/plugin/install.sh" 2>&1)

# 7a. Detect integrated mode
if echo "$OUTPUT" | grep -q "Integrated mode"; then
  pass "integrated: detected integrated mode"
else
  fail "integrated: mode detection" "did not detect integrated mode"
fi

# 7b. Vault template copied
if [ -f "$INT_DIR/vault/Home.md" ]; then
  pass "integrated: vault/Home.md created"
else
  fail "integrated: vault/Home.md" "not found"
fi

# 7c. Hooks merged into project root settings.json (not vault/)
if python3 -c "import json; d=json.load(open('$INT_DIR/.claude/settings.json')); assert 'hooks' in d" 2>/dev/null; then
  pass "integrated: hooks merged into project root settings.json"
else
  fail "integrated: settings.json merge" "hooks key missing"
fi

# 7d. Existing permissions preserved after merge
if python3 -c "import json; d=json.load(open('$INT_DIR/.claude/settings.json')); assert 'Read' in d['permissions']['allow']" 2>/dev/null; then
  pass "integrated: existing permissions preserved"
else
  fail "integrated: permissions" "existing config overwritten"
fi

# 7e. Hook paths use vault/ prefix
if grep -q "vault/.codex-vault/hooks" "$INT_DIR/.claude/settings.json"; then
  pass "integrated: hook paths use vault/.codex-vault/hooks/ prefix"
else
  fail "integrated: hook paths" "missing vault/ prefix"
fi

# 7f. CLAUDE.md has both original content and codex-vault section
if grep -q "My Cool Project" "$INT_DIR/CLAUDE.md" && grep -q "# Codex-Vault" "$INT_DIR/CLAUDE.md"; then
  pass "integrated: CLAUDE.md has original + codex-vault content"
else
  fail "integrated: CLAUDE.md" "content merge failed"
fi

# 7g. Idempotent re-run — no duplicate sections
bash "$REPO_DIR/plugin/install.sh" > /dev/null 2>&1
SECTION_COUNT=$(grep -c "^# Codex-Vault" "$INT_DIR/CLAUDE.md" 2>/dev/null || echo "0")
if [ "$SECTION_COUNT" -eq 1 ]; then
  pass "integrated: idempotent — no duplicate codex-vault section"
else
  fail "integrated: idempotent" "found $SECTION_COUNT sections"
fi

HOOK_COUNT=$(python3 -c "
import json
d = json.load(open('$INT_DIR/.claude/settings.json'))
count = sum(len(v) for v in d.get('hooks', {}).values())
print(count)
" 2>/dev/null)
if [ "$HOOK_COUNT" -eq 3 ]; then
  pass "integrated: idempotent — no duplicate hooks ($HOOK_COUNT entries)"
else
  fail "integrated: idempotent hooks" "expected 3 hook entries, got $HOOK_COUNT"
fi

# 7h. Vault has no agent configs (those live at project root)
if [ ! -f "$INT_DIR/vault/.claude/settings.json" ] && [ ! -f "$INT_DIR/vault/.codex/hooks.json" ]; then
  pass "integrated: vault has no agent configs (correct — they live at project root)"
else
  fail "integrated: vault agent configs" "should not exist in vault/"
fi

# 7i. session-start.sh works from project root (finds vault/ subdir)
SS_OUTPUT=$(CLAUDE_PROJECT_DIR="$INT_DIR" bash "$INT_DIR/vault/.codex-vault/hooks/session-start.sh" 2>&1) || true
if echo "$SS_OUTPUT" | grep -q "North Star"; then
  pass "integrated: session-start.sh finds vault/ from project root"
else
  fail "integrated: session-start.sh" "cannot find vault from project root"
fi

rm -rf "$INT_DIR"
cd "$TEST_DIR"

echo ""

# ============================================================
echo "--- 8. New Validations ---"
# ============================================================

# 8a. Placeholder detection
PLACEHOLDER_NOTE="$TEST_DIR/vault/work/active/Placeholder Test.md"
cat > "$PLACEHOLDER_NOTE" << 'EOF'
---
date: "2026-04-06"
description: "Testing placeholder detection"
tags:
  - test
---

# {{title}}

Content with [[wikilinks]] but unfilled {{author}} placeholder.
EOF

OUT=$(echo "{\"tool_input\":{\"file_path\":\"$PLACEHOLDER_NOTE\"}}" | python3 plugin/hooks/validate-write.py)
if echo "$OUT" | grep -q "Unfilled template placeholders"; then
  pass "validate: detects unfilled {{placeholders}}"
else
  fail "validate: placeholder detection" "not triggered"
fi
rm -f "$PLACEHOLDER_NOTE"

# 8b. Log format validation — good entry
LOG_GOOD="$TEST_DIR/vault/log.md"
cat > "$LOG_GOOD" << 'EOF'
---
description: "Operation log"
tags:
  - log
---

# Operation Log

## [2026-04-06] session | Initial vault setup

- Created vault structure
EOF

OUT=$(echo "{\"tool_input\":{\"file_path\":\"$LOG_GOOD\"}}" | python3 plugin/hooks/validate-write.py)
if [ -z "$OUT" ]; then
  pass "validate: valid log.md passes"
else
  fail "validate: valid log.md" "unexpected warnings: $OUT"
fi

# 8c. Log format validation — bad entry
LOG_BAD="$TEST_DIR/vault/log.md"
cat > "$LOG_BAD" << 'EOF'
---
description: "Operation log"
tags:
  - log
---

# Operation Log

## session bad format
## [2026-04-06] session | Good entry
EOF

OUT=$(echo "{\"tool_input\":{\"file_path\":\"$LOG_BAD\"}}" | python3 plugin/hooks/validate-write.py)
if echo "$OUT" | grep -q "log entry missing date format"; then
  pass "validate: detects malformed log entry"
else
  fail "validate: log format" "bad format not detected"
fi

# 8d. Session-end integrity check
cd "$TEST_DIR/vault"
mkdir -p work/active
cat > work/active/Temp.md << 'EOF'
---
description: "temp"
tags: [test]
---
# Temp
We decided to use Redis for caching. [[North Star]]
EOF
git add -A && git commit -q -m "add temp note"
# Now create another note without committing — simulates uncommitted work
cat > work/active/New.md << 'EOF'
---
description: "new"
tags: [test]
---
# New
Some new content. [[Temp]]
EOF

OUT=$(echo '{"prompt":"wrap up"}' | python3 "$TEST_DIR/plugin/hooks/classify-message.py")
if echo "$OUT" | grep -q "SESSION END"; then
  pass "classify: SESSION END detected on wrap-up"
else
  fail "classify: SESSION END" "not triggered"
fi
if echo "$OUT" | grep -q "work/Index.md not updated"; then
  pass "classify: detects missing Index.md update"
else
  fail "classify: Index.md check" "gap not detected"
fi

rm -f work/active/Temp.md work/active/New.md

echo ""

# ============================================================
echo "--- 9. Session-Start Tiered Vault Listing ---"
# ============================================================

cd "$TEST_DIR/vault"
export CLAUDE_PROJECT_DIR="$TEST_DIR/vault"

# Current vault has ~15 files — should be Tier 1 (list all)
T1_OUTPUT=$(bash "$TEST_DIR/plugin/hooks/session-start.sh" 2>&1)
if echo "$T1_OUTPUT" | grep -q "./Home.md" && ! echo "$T1_OUTPUT" | grep -q "showing summary"; then
  pass "tier1: small vault lists all files"
else
  fail "tier1: small vault" "expected full listing without summary"
fi

# Tier 2: push past 20 files with sources
mkdir -p sources
for i in $(seq 1 15); do
  echo "---" > "sources/src-$i.md"
done
git add -A && git commit -q -m "add sources for tier2 test"

T2_OUTPUT=$(bash "$TEST_DIR/plugin/hooks/session-start.sh" 2>&1)
if echo "$T2_OUTPUT" | grep -q "/recall"; then
  pass "tier2: medium vault mentions /recall for cold storage"
else
  fail "tier2: medium vault" "/recall hint not found"
fi
if echo "$T2_OUTPUT" | grep -q "./brain/North Star.md"; then
  pass "tier2: hot folders still listed"
else
  fail "tier2: hot folders" "brain files not listed"
fi

# Tier 3: push past 50 files
for i in $(seq 16 50); do
  echo "---" > "sources/src-$i.md"
done
git add -A && git commit -q -m "add sources for tier3 test"

T3_OUTPUT=$(bash "$TEST_DIR/plugin/hooks/session-start.sh" 2>&1)
if echo "$T3_OUTPUT" | grep -q "showing summary"; then
  pass "tier3: large vault shows folder summary"
else
  fail "tier3: large vault" "folder summary not found"
fi
if echo "$T3_OUTPUT" | grep -q "Recently modified"; then
  pass "tier3: shows recently modified files"
else
  fail "tier3: recently modified" "section not found"
fi

# Cleanup tier test files
rm -f sources/src-*.md
git add -A && git commit -q -m "cleanup tier test files"

echo ""

# ============================================================
echo "--- 10. CLI Commands (bin/cli.js) ---"
# ============================================================

CLI="$REPO_DIR/bin/cli.js"

# 10a. --version
CLI_VER=$(node "$CLI" --version 2>&1)
if [ -n "$CLI_VER" ] && echo "$CLI_VER" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+'; then
  pass "cli: --version outputs semver ($CLI_VER)"
else
  fail "cli: --version" "unexpected output: $CLI_VER"
fi

# 10b. --help
CLI_HELP=$(node "$CLI" --help 2>&1)
if echo "$CLI_HELP" | grep -q "init" && echo "$CLI_HELP" | grep -q "upgrade" && echo "$CLI_HELP" | grep -q "uninstall"; then
  pass "cli: --help lists all commands"
else
  fail "cli: --help" "missing commands in help output"
fi

# 10c. unknown command
if ! node "$CLI" bogus-cmd >/dev/null 2>&1; then
  pass "cli: unknown command exits non-zero"
else
  fail "cli: unknown command" "expected non-zero exit"
fi

# 10d. init in a fresh directory
CLI_DIR=$(mktemp -d)
cd "$CLI_DIR"
git init -q
CLI_OUT=$(node "$CLI" init 2>&1)
if echo "$CLI_OUT" | grep -q "installed successfully" && [ -f "$CLI_DIR/vault/.codex-vault/version" ]; then
  pass "cli: init creates vault and writes version file"
else
  fail "cli: init" "install failed or version file missing"
fi

# 10e. init again (already installed)
CLI_OUT=$(node "$CLI" init 2>&1)
if echo "$CLI_OUT" | grep -q "already installed"; then
  pass "cli: init detects existing installation"
else
  fail "cli: init re-run" "did not detect existing install"
fi

# 10f. upgrade at same version
CLI_OUT=$(node "$CLI" upgrade 2>&1)
if echo "$CLI_OUT" | grep -q "Already at"; then
  pass "cli: upgrade at same version says 'Already at'"
else
  fail "cli: upgrade same version" "unexpected output: $CLI_OUT"
fi

# 10g. uninstall
CLI_OUT=$(node "$CLI" uninstall 2>&1)
if echo "$CLI_OUT" | grep -q "has been uninstalled" && [ ! -d "$CLI_DIR/vault/.codex-vault" ]; then
  pass "cli: uninstall removes .codex-vault/"
else
  fail "cli: uninstall" "cleanup incomplete"
fi

# 10h. uninstall preserves vault data
if [ -f "$CLI_DIR/vault/Home.md" ] && [ -d "$CLI_DIR/vault/brain" ]; then
  pass "cli: uninstall preserves vault data"
else
  fail "cli: uninstall data" "vault data was deleted"
fi

# 10i. uninstall again (already uninstalled)
if ! node "$CLI" uninstall >/dev/null 2>&1; then
  pass "cli: uninstall when not installed exits non-zero"
else
  fail "cli: uninstall re-run" "expected non-zero exit"
fi

# 10j. init detects legacy codex-mem
mkdir -p "$CLI_DIR/vault/.codex-mem"
echo "0.0.1" > "$CLI_DIR/vault/.codex-mem/version"
CLI_OUT=$(node "$CLI" init 2>&1)
if echo "$CLI_OUT" | grep -q "Legacy codex-mem"; then
  pass "cli: init detects legacy codex-mem"
else
  fail "cli: init legacy" "did not detect codex-mem"
fi

# 10k. upgrade detects legacy codex-mem
if ! node "$CLI" upgrade >/dev/null 2>&1; then
  pass "cli: upgrade rejects legacy codex-mem"
else
  fail "cli: upgrade legacy" "should have rejected"
fi

# 10l. uninstall cleans legacy codex-mem
CLI_OUT=$(node "$CLI" uninstall 2>&1)
if echo "$CLI_OUT" | grep -q ".codex-mem" && [ ! -d "$CLI_DIR/vault/.codex-mem" ]; then
  pass "cli: uninstall removes legacy .codex-mem/"
else
  fail "cli: uninstall legacy" ".codex-mem not removed"
fi

rm -rf "$CLI_DIR"
cd "$TEST_DIR"

echo ""

# ============================================================
echo "--- 11. Classify Dual Mode ---"
# ============================================================

cd "$TEST_DIR/vault"

# 11a. Default mode (no config) = suggest
OUT=$(echo '{"prompt":"we decided to use Redis"}' | CLAUDE_PROJECT_DIR="$TEST_DIR/vault" python3 "$TEST_DIR/plugin/hooks/classify-message.py")
if echo "$OUT" | grep -q "do NOT auto-execute"; then
  pass "dual-mode: default is suggest mode"
else
  fail "dual-mode: default" "not in suggest mode"
fi

# 11b. Auto mode with config
mkdir -p "$TEST_DIR/vault/.codex-vault"
echo '{"classify_mode":"auto"}' > "$TEST_DIR/vault/.codex-vault/config.json"
OUT=$(echo '{"prompt":"we decided to use Redis"}' | CLAUDE_PROJECT_DIR="$TEST_DIR/vault" python3 "$TEST_DIR/plugin/hooks/classify-message.py")
if echo "$OUT" | grep -q "Auto-execute"; then
  pass "dual-mode: auto mode activates with config"
else
  fail "dual-mode: auto mode" "not activated"
fi

# 11c. Auto mode — session end stays suggest
OUT=$(echo '{"prompt":"wrap up"}' | CLAUDE_PROJECT_DIR="$TEST_DIR/vault" python3 "$TEST_DIR/plugin/hooks/classify-message.py")
if echo "$OUT" | grep -q "SESSION END" && echo "$OUT" | grep -q "do NOT auto-execute\|suggest"; then
  pass "dual-mode: session end stays suggest in auto mode"
else
  fail "dual-mode: session end" "should stay suggest"
fi

# 11d. Invalid mode in config falls back to suggest
echo '{"classify_mode":"turbo"}' > "$TEST_DIR/vault/.codex-vault/config.json"
OUT=$(echo '{"prompt":"we decided to use Redis"}' | CLAUDE_PROJECT_DIR="$TEST_DIR/vault" python3 "$TEST_DIR/plugin/hooks/classify-message.py")
if echo "$OUT" | grep -q "do NOT auto-execute"; then
  pass "dual-mode: invalid mode falls back to suggest"
else
  fail "dual-mode: invalid mode" "did not fall back"
fi

rm -rf "$TEST_DIR/vault/.codex-vault"
cd "$TEST_DIR"

echo ""

# ============================================================
echo "--- 12. Stderr Feedback (User-Visible) ---"
# ============================================================

cd "$TEST_DIR/vault"
export CLAUDE_PROJECT_DIR="$TEST_DIR/vault"

# 12a. session-start banner shows in stderr
SS_ERR=$(bash "$TEST_DIR/plugin/hooks/session-start.sh" 2>&1 1>/dev/null)
if echo "$SS_ERR" | grep -q "Codex-Vault"; then
  pass "stderr: session-start shows banner"
else
  fail "stderr: session-start banner" "banner not found in stderr"
fi

# 12b. session-start banner shows goal hint when North Star is template
if echo "$SS_ERR" | grep -q "set goals"; then
  pass "stderr: session-start shows 'set goals' hint"
else
  fail "stderr: session-start goal hint" "expected 'set goals' for template North Star"
fi

# 12c. classify stderr — DECISION signal
CL_ERR=$(echo '{"prompt":"we decided to use Redis"}' | CLAUDE_PROJECT_DIR="$TEST_DIR/vault" python3 "$TEST_DIR/plugin/hooks/classify-message.py" 2>&1 1>/dev/null)
if echo "$CL_ERR" | grep -q "DECISION detected"; then
  pass "stderr: classify shows DECISION detected"
else
  fail "stderr: classify DECISION" "feedback not in stderr"
fi

# 12d. classify stderr — suggest mode uses 💡
if echo "$CL_ERR" | grep -q "💡"; then
  pass "stderr: classify suggest mode uses 💡"
else
  fail "stderr: classify 💡" "wrong icon for suggest mode"
fi

# 12e. classify stderr — no signal = silent
CL_ERR_SILENT=$(echo '{"prompt":"fix the typo"}' | python3 "$TEST_DIR/plugin/hooks/classify-message.py" 2>&1 1>/dev/null)
if [ -z "$CL_ERR_SILENT" ]; then
  pass "stderr: classify silent when no signal"
else
  fail "stderr: classify silent" "unexpected stderr: $CL_ERR_SILENT"
fi

# 12f. classify stderr — auto mode uses 🔄
mkdir -p "$TEST_DIR/vault/.codex-vault"
echo '{"classify_mode":"auto"}' > "$TEST_DIR/vault/.codex-vault/config.json"
CL_ERR_AUTO=$(echo '{"prompt":"we decided to use Redis"}' | CLAUDE_PROJECT_DIR="$TEST_DIR/vault" python3 "$TEST_DIR/plugin/hooks/classify-message.py" 2>&1 1>/dev/null)
if echo "$CL_ERR_AUTO" | grep -q "🔄"; then
  pass "stderr: classify auto mode uses 🔄"
else
  fail "stderr: classify 🔄" "wrong icon for auto mode"
fi
rm -rf "$TEST_DIR/vault/.codex-vault"

# 12g. classify stderr — SESSION END
CL_ERR_END=$(echo '{"prompt":"wrap up"}' | CLAUDE_PROJECT_DIR="$TEST_DIR/vault" python3 "$TEST_DIR/plugin/hooks/classify-message.py" 2>&1 1>/dev/null)
if echo "$CL_ERR_END" | grep -q "SESSION END detected"; then
  pass "stderr: classify shows SESSION END detected"
else
  fail "stderr: classify SESSION END" "feedback not in stderr"
fi

# 12h. validate stderr — warnings shown
BAD_NOTE="$TEST_DIR/vault/work/active/Stderr Test.md"
mkdir -p "$TEST_DIR/vault/work/active"
echo "No frontmatter, no wikilinks, long enough to trigger checks. Padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding." > "$BAD_NOTE"
VW_ERR=$(echo "{\"tool_input\":{\"file_path\":\"$BAD_NOTE\"}}" | python3 "$TEST_DIR/plugin/hooks/validate-write.py" 2>&1 1>/dev/null)
if echo "$VW_ERR" | grep -q "warning(s)"; then
  pass "stderr: validate shows warning count"
else
  fail "stderr: validate warnings" "feedback not in stderr"
fi
rm -f "$BAD_NOTE"

# 12i. validate stderr — clean note = silent
GOOD_NOTE="$TEST_DIR/vault/work/active/Good Note.md"
cat > "$GOOD_NOTE" << 'EOF'
---
date: "2026-04-07"
description: "Good note for stderr test"
tags:
  - test
---

# Good Note

Content with [[wikilinks]].
EOF
VW_ERR_SILENT=$(echo "{\"tool_input\":{\"file_path\":\"$GOOD_NOTE\"}}" | python3 "$TEST_DIR/plugin/hooks/validate-write.py" 2>&1 1>/dev/null)
if [ -z "$VW_ERR_SILENT" ]; then
  pass "stderr: validate silent on clean note"
else
  fail "stderr: validate silent" "unexpected stderr: $VW_ERR_SILENT"
fi
rm -f "$GOOD_NOTE"

cd "$TEST_DIR"

echo ""

# ============================================================
# Summary
# ============================================================

echo "=== Results ==="
echo -e "${GREEN}PASS: $PASS${NC}"
echo -e "${RED}FAIL: $FAIL${NC}"
echo ""

if [ $FAIL -gt 0 ]; then
  echo "Failures:"
  for err in "${ERRORS[@]}"; do
    echo -e "  ${RED}✗${NC} $err"
  done
  echo ""
fi

# Cleanup
rm -rf "$TEST_DIR"

if [ $FAIL -eq 0 ]; then
  echo -e "${GREEN}All tests passed.${NC}"
  exit 0
else
  echo -e "${RED}$FAIL test(s) failed.${NC}"
  exit 1
fi
