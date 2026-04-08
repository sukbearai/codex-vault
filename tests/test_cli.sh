#!/bin/bash
set -eo pipefail

# CLI-only test suite — fast, no install.sh dependency
# Run: npm run test:cli  or  bash tests/test_cli.sh

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$REPO_DIR/bin/cli.js"
PASS=0
FAIL=0
ERRORS=()

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { ((PASS++)); echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { ((FAIL++)); ERRORS+=("$1: $2"); echo -e "  ${RED}FAIL${NC} $1 — $2"; }

echo "=== CLI Tests ==="
echo ""

# --- Version ---
echo "--- version ---"
VER=$(node "$CLI" --version 2>&1)
if echo "$VER" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+'; then
  pass "--version outputs semver ($VER)"
else
  fail "--version" "unexpected: $VER"
fi

VER2=$(node "$CLI" -v 2>&1)
if [ "$VER" = "$VER2" ]; then
  pass "-v matches --version"
else
  fail "-v" "mismatch: $VER2 vs $VER"
fi

# --- Help ---
echo "--- help ---"
HELP=$(node "$CLI" --help 2>&1)
for cmd in init upgrade uninstall; do
  if echo "$HELP" | grep -q "$cmd"; then
    pass "--help mentions $cmd"
  else
    fail "--help $cmd" "not found"
  fi
done

HELP2=$(node "$CLI" -h 2>&1)
if [ "$HELP" = "$HELP2" ]; then
  pass "-h matches --help"
else
  fail "-h" "output differs from --help"
fi

# --- Unknown command ---
echo "--- error handling ---"
if ! node "$CLI" bogus 2>/dev/null; then
  pass "unknown command exits non-zero"
else
  fail "unknown command" "expected non-zero exit"
fi

BOGUS_OUT=$(node "$CLI" bogus 2>&1 || true)
if echo "$BOGUS_OUT" | grep -qi "unknown\|usage"; then
  pass "unknown command shows error or usage"
else
  fail "unknown command message" "no error message"
fi

# --- Init ---
echo "--- init ---"
DIR=$(mktemp -d)
cd "$DIR" && git init -q

OUT=$(node "$CLI" init 2>&1)
if echo "$OUT" | grep -q "installed successfully"; then
  pass "init succeeds in fresh dir"
else
  fail "init" "unexpected: $OUT"
fi

if [ -f "$DIR/.vault/.codex-vault/version" ]; then
  pass "init writes version file"
else
  fail "init version file" "not found"
fi

if [ -f "$DIR/.vault/Home.md" ]; then
  pass "init creates .vault/Home.md"
else
  fail "init Home.md" "not found"
fi

if [ -f "$DIR/CLAUDE.md" ] || [ -f "$DIR/.vault/CLAUDE.md" ]; then
  pass "init creates CLAUDE.md"
else
  fail "init CLAUDE.md" "not found at root or .vault/"
fi

# --- Init again (idempotent) ---
OUT=$(node "$CLI" init 2>&1)
if echo "$OUT" | grep -q "already installed"; then
  pass "init detects existing install"
else
  fail "init re-run" "did not detect existing"
fi

# --- Upgrade at same version ---
echo "--- upgrade ---"
OUT=$(node "$CLI" upgrade 2>&1)
if echo "$OUT" | grep -q "Already at"; then
  pass "upgrade at same version"
else
  fail "upgrade same version" "$OUT"
fi

# --- Simulate older version for upgrade ---
echo "0.0.1" > "$DIR/.vault/.codex-vault/version"
OUT=$(node "$CLI" upgrade 2>&1)
if echo "$OUT" | grep -q "Upgrading"; then
  pass "upgrade from older version"
else
  fail "upgrade older" "$OUT"
fi

# --- Upgrade migration: vault/ → .vault/ ---
echo "--- upgrade migration ---"
# Simulate old layout: rename .vault back to vault
mv "$DIR/.vault" "$DIR/vault"
echo "0.7.0" > "$DIR/vault/.codex-vault/version"

OUT=$(node "$CLI" upgrade 2>&1)
if echo "$OUT" | grep -q "Migrating vault/"; then
  pass "upgrade migrates vault/ → .vault/"
else
  fail "upgrade migration" "migration not triggered: $OUT"
fi

if [ -d "$DIR/.vault" ] && [ ! -d "$DIR/vault" ]; then
  pass "upgrade moves data to .vault/"
else
  fail "upgrade migration data" ".vault/ not created or vault/ still exists"
fi

if [ -f "$DIR/.vault/Home.md" ]; then
  pass "upgrade preserves vault data in .vault/"
else
  fail "upgrade migration data" "Home.md missing after migration"
fi

if grep -q "\.vault/" "$DIR/.gitignore" 2>/dev/null; then
  pass "upgrade adds .vault/ to .gitignore"
else
  fail "upgrade .gitignore" ".vault/ not in .gitignore"
fi

# --- Uninstall ---
echo "--- uninstall ---"
OUT=$(node "$CLI" uninstall 2>&1)
if echo "$OUT" | grep -q "has been uninstalled"; then
  pass "uninstall succeeds"
else
  fail "uninstall" "$OUT"
fi

if [ ! -d "$DIR/.vault" ]; then
  pass "uninstall removes .vault/"
else
  fail "uninstall cleanup" ".vault/ still exists"
fi

# --- Uninstall again ---
if ! node "$CLI" uninstall 2>/dev/null; then
  pass "uninstall when not installed exits non-zero"
else
  fail "uninstall re-run" "expected non-zero"
fi

# --- Legacy codex-mem detection ---
echo "--- legacy detection ---"
mkdir -p "$DIR/.vault/.codex-mem"
echo "0.0.1" > "$DIR/.vault/.codex-mem/version"

OUT=$(node "$CLI" init 2>&1)
if echo "$OUT" | grep -q "Legacy codex-mem"; then
  pass "init detects legacy codex-mem"
else
  fail "init legacy" "not detected"
fi

if ! node "$CLI" upgrade 2>/dev/null; then
  pass "upgrade rejects legacy codex-mem"
else
  fail "upgrade legacy" "should reject"
fi

OUT=$(node "$CLI" uninstall 2>&1)
if [ ! -d "$DIR/.vault/.codex-mem" ]; then
  pass "uninstall removes legacy .codex-mem/"
else
  fail "uninstall legacy" ".codex-mem/ still exists"
fi

rm -rf "$DIR"

echo ""
echo "=== Results ==="
echo -e "${GREEN}PASS: $PASS${NC}"
echo -e "${RED}FAIL: $FAIL${NC}"

if [ $FAIL -gt 0 ]; then
  echo ""
  echo "Failures:"
  for err in "${ERRORS[@]}"; do
    echo -e "  ${RED}✗${NC} $err"
  done
fi

echo ""
[ $FAIL -eq 0 ] && echo -e "${GREEN}All CLI tests passed.${NC}" && exit 0
echo -e "${RED}$FAIL test(s) failed.${NC}" && exit 1
