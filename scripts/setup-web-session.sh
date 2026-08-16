#!/usr/bin/env bash
#
# Make a fresh session able to run the Godot gates.
#
# The Cursor Cloud VM snapshot ships Godot 4.7.1 on PATH (see AGENTS.md). Claude Code on
# the web does not: its container starts from a bare clone with no engine, no export
# templates, and no node_modules. Without this script the only suite that runs in such a
# session is whatever npm can execute -- which is how a session ends up "verifying" the
# product against something that is not the product.
#
# Everything here is idempotent and skips work that is already done, so it costs nothing
# on a machine that already has the engine.
#
# The engine URL and its SHA-512 are the same constants used by .github/workflows/ci.yml
# and pages.yml. Keep all three in step: scripts/run-godot.mjs hard-rejects any engine
# whose --version does not start with 4.7.1, so a drifting pin fails loudly rather than
# silently testing the wrong build.
#
#   SETUP_EXPORT_TEMPLATES=1   also install the ~1 GB export templates. Only
#                              `npm run build` / godot:export / godot:smoke:exports need
#                              them; every correctness gate runs without them.

set -euo pipefail

readonly GODOT_VERSION="4.7.1"
readonly GODOT_URL="https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64.zip"
readonly GODOT_SHA512="4ccdab7a48eeccbe8819a2fc1f6262f8d72065d98601bcb3743fcbd7ebd39f373758a788ee3293a05ec5b2c48538266c437404312e372225cd2df273945a2de9"
readonly TEMPLATES_URL="https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_export_templates.tpz"
readonly TEMPLATES_SHA512="afcc83d8d3d298038f19c58744a0d660fa75dd4baa33cb55d1011bb2565a2a8c2381728924564cb909e37c205a23f21b521b23bd057993afd43ae4da0b2f9d47"

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TOOLS="$ROOT/.ci-tools/godot"
readonly BINARY="$TOOLS/Godot_v4.7.1-stable_linux.x86_64"
readonly TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/4.7.1.stable"

log() { printf '[setup] %s\n' "$1"; }

# Any 4.7.1 already on PATH wins -- that is the Cursor Cloud snapshot, and reinstalling
# over it would be pure cost.
if command -v godot >/dev/null 2>&1 && godot --version 2>/dev/null | grep -q "^$GODOT_VERSION"; then
  log "Godot $GODOT_VERSION already on PATH; skipping engine install."
else
  if [ -x "$BINARY" ] && "$BINARY" --version 2>/dev/null | grep -q "^$GODOT_VERSION"; then
    log "Godot $GODOT_VERSION already unpacked at .ci-tools/; skipping download."
  else
    log "Installing Godot $GODOT_VERSION..."
    mkdir -p "$TOOLS"
    archive="$TOOLS/godot.zip"
    # --http1.1 and the retries mirror ci.yml: this download is the flakiest step here.
    curl --fail --location --http1.1 --retry 5 --retry-all-errors --retry-delay 2 \
      --output "$archive" "$GODOT_URL"
    # Verify before anything executes the binary, not after.
    echo "$GODOT_SHA512  $archive" | sha512sum --check --quiet
    unzip -q -o "$archive" -d "$TOOLS"
    rm -f "$archive"
    chmod +x "$BINARY"
    log "Installed $("$BINARY" --version)"
  fi

  # run-godot.mjs probes GODOT_BIN, then a Windows path, then `godot4`/`godot` on PATH. A
  # hook cannot export an env var into later tool calls, so the symlink is what actually
  # makes the gates work for the rest of the session -- and it puts the engine exactly
  # where AGENTS.md says it lives on the snapshot.
  if [ -w /usr/local/bin ]; then
    ln -sf "$BINARY" /usr/local/bin/godot
    log "Linked /usr/local/bin/godot"
  else
    log "WARNING: /usr/local/bin not writable. Run gates with GODOT_BIN=$BINARY"
  fi
fi

if [ "${SETUP_EXPORT_TEMPLATES:-0}" = "1" ]; then
  if [ -f "$TEMPLATE_DIR/web_nothreads_release.zip" ]; then
    log "Export templates already installed; skipping."
  else
    log "Installing export templates (~1 GB)..."
    mkdir -p "$TEMPLATE_DIR"
    tmp="$(mktemp /tmp/godot-tp-XXXXXX.tpz)"
    scratch="$(mktemp -d /tmp/godot-tp-XXXXXX)"
    curl --fail --location --retry 5 --output "$tmp" "$TEMPLATES_URL"
    echo "$TEMPLATES_SHA512  $tmp" | sha512sum --check --quiet
    unzip -q "$tmp" -d "$scratch"
    # The same subset pages.yml copies. The full .tpz carries every platform; the web and
    # Windows release templates are the only ones this project exports.
    for template in web_nothreads_release.zip web_release.zip version.txt \
      windows_release_x86_64.exe windows_release_x86_64_console.exe; do
      cp "$scratch/templates/$template" "$TEMPLATE_DIR/" 2>/dev/null || true
    done
    rm -rf "$tmp" "$scratch"
    log "Export templates installed to $TEMPLATE_DIR"
  fi
else
  log "Skipping export templates (set SETUP_EXPORT_TEMPLATES=1 to install)."
fi

if [ ! -d "$ROOT/node_modules" ]; then
  # `npm install` rather than `npm ci`: the container image is cached after the hook
  # completes, and ci wipes node_modules on every run rather than reusing that layer.
  log "Installing npm dependencies..."
  (cd "$ROOT" && npm install --no-audit --no-fund)
else
  log "node_modules present; skipping npm install."
fi

log "Ready. Verify with: npm run godot:smoke"
