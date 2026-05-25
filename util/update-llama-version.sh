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
              grep -o 'refs/tags/b[0-9]*' | tail -n 1 | cut -d'/' -f3)
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
echo "Run 'nix flake lock --update-input llama-cpp' to sync the lock file."
