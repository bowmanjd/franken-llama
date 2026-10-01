#!/usr/bin/env bash

# Update llama.cpp version in flake.nix (input URL and module defaults)

set -euo pipefail

REPO_ROOT="$(git -C "${BASH_SOURCE[0]%/*}" rev-parse --show-toplevel)"

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed" >&2
    exit 1
fi

get_latest_tag() {
    local tag=""
    if command -v gh >/dev/null 2>&1; then
        tag=$(gh release view --repo ggml-org/llama.cpp --json tagName --jq .tagName 2>/dev/null || true)
    fi
    if [ -z "$tag" ]; then
        tag=$(git ls-remote --tags --sort='v:refname' https://github.com/ggml-org/llama.cpp.git | \
              grep -E 'refs/tags/[bv][0-9][^^{}]*$' | tail -n 1 | sed 's|.*/||')
    fi
    echo "$tag"
}

TAG="${1:-}"
if [ -z "$TAG" ]; then
    echo "Fetching latest llama.cpp tag..."
    TAG=$(get_latest_tag)
    if [ -z "$TAG" ]; then
        echo "Error: Could not determine latest llama.cpp tag" >&2
        exit 1
    fi
fi

echo "Tag: $TAG"

# Prefetch the hash
echo "Prefetching hash..."
PREFETCH_URL="https://github.com/ggml-org/llama.cpp/archive/refs/tags/${TAG}.tar.gz"
JSON_OUTPUT=$(nix store prefetch-file --unpack --json "$PREFETCH_URL" --extra-experimental-features "nix-command flakes" 2>/dev/null || {
    PREFETCH_URL_ALT="https://github.com/ggml-org/llama.cpp/archive/${TAG}.tar.gz"
    nix store prefetch-file --unpack --json "$PREFETCH_URL_ALT" --extra-experimental-features "nix-command flakes"
})

HASH=$(echo "$JSON_OUTPUT" | jq -r '.hash')
if [ -z "$HASH" ] || [ "$HASH" = "null" ]; then
    echo "Error: Failed to fetch hash for tag $TAG" >&2
    exit 1
fi

echo "Hash: $HASH"

FLAKE="$REPO_ROOT/flake.nix"

# Update input URL
sed -i -E 's|(url = "github:ggml-org/llama\.cpp/)[^"]*|\1'"$TAG"'|' "$FLAKE"

# Update default values in module options (llamaCppTag default on line after mkOption)
sed -i -E '/llamaCppTag = lib\.mkOption/,/};/ s|(default = ")[^"]*|\1'"$TAG"'|' "$FLAKE"
sed -i -E '/llamaCppHash = lib\.mkOption/,/};/ s|(default = ")[^"]*|\1'"$HASH"'|' "$FLAKE"

echo "Updated $FLAKE"

# Update npmDepsHash for the web UI
OVERLAY="$REPO_ROOT/llama-cpp-overlay.nix"
if [ -f "$OVERLAY" ]; then
    echo "Calculating npm deps hash for web UI..."

    # Create a temp directory and extract the UI source
    TMPDIR=$(mktemp -d)
    trap "rm -rf $TMPDIR" EXIT

    # Download archive and extract tools/ui directory
    ARCHIVE_FILE="$TMPDIR/archive.tar.gz"
    curl -sSfL "https://github.com/ggml-org/llama.cpp/archive/refs/tags/${TAG}.tar.gz" -o "$ARCHIVE_FILE" 2>/dev/null || \
    curl -sSfL "https://github.com/ggml-org/llama.cpp/archive/${TAG}.tar.gz" -o "$ARCHIVE_FILE" 2>/dev/null || true

    if [ -s "$ARCHIVE_FILE" ]; then
        ROOT_DIR=$(tar -tzf "$ARCHIVE_FILE" 2>/dev/null | head -n 1 | cut -d'/' -f1 || true)
        if [ -n "$ROOT_DIR" ]; then
            tar -xzf "$ARCHIVE_FILE" -C "$TMPDIR" --strip-components=1 "$ROOT_DIR/tools/ui" 2>/dev/null || true
        fi
        if [ ! -d "$TMPDIR/tools/ui" ]; then
            tar -xzf "$ARCHIVE_FILE" -C "$TMPDIR" --strip-components=1 --wildcards "*/tools/ui" 2>/dev/null || true
        fi
    fi

    if [ -f "$TMPDIR/tools/ui/package-lock.json" ]; then
        NPM_HASH=""

        # Use prefetch-npm-deps if available
        if command -v prefetch-npm-deps &> /dev/null; then
            NPM_HASH=$(prefetch-npm-deps "$TMPDIR/tools/ui/package-lock.json" 2>/dev/null || true)
        fi

        # Fallback: use nix-prefetch-npm-deps from nixpkgs
        if [ -z "$NPM_HASH" ] || [ "$NPM_HASH" = "null" ]; then
            NPM_HASH=$(nix run nixpkgs#prefetch-npm-deps -- "$TMPDIR/tools/ui/package-lock.json" 2>/dev/null || true)
        fi

        if [ -n "$NPM_HASH" ] && [ "$NPM_HASH" != "null" ]; then
            echo "npm deps hash: $NPM_HASH"
            sed -i -E 's|(npmDepsHash = .* else ")[^"]*|\1'"$NPM_HASH"'|' "$OVERLAY"
            echo "Updated $OVERLAY"
        else
            echo "Warning: Could not calculate npm deps hash. You may need to update it manually." >&2
            echo "Build once to get the correct hash from the error message." >&2
        fi
    else
        echo "Warning: tools/ui/package-lock.json not found in release" >&2
    fi
fi

echo "Run 'nix flake lock --update-input llama-cpp' to sync the lock file."
