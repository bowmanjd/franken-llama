#!/usr/bin/env bash
# Update llguidance version in llama-cpp-overlay.nix based on llama.cpp's requirements

set -euo pipefail

REPO_ROOT="$(git -C "${BASH_SOURCE[0]%/*}" rev-parse --show-toplevel)"
OVERLAY_FILE="$REPO_ROOT/llama-cpp-overlay.nix"

echo "Fetching llama.cpp source from flake input..."

# Get llama.cpp source from the flake input
LLAMA_CPP_SRC=$(nix eval --raw "$REPO_ROOT#packages.x86_64-linux.llama-cpp-cpu.src.outPath" 2>/dev/null)

if [[ -z "$LLAMA_CPP_SRC" || ! -f "$LLAMA_CPP_SRC/common/CMakeLists.txt" ]]; then
    echo "Error: Could not fetch llama.cpp source from flake"
    echo "Make sure your flake.lock is up to date:"
    echo "  nix flake lock --update-input llama-cpp"
    exit 1
fi

echo "Reading llguidance version from llama.cpp source..."

# Extract the GIT_TAG from CMakeLists.txt
GIT_TAG=$(grep -A 3 "GIT_REPOSITORY.*llguidance" "$LLAMA_CPP_SRC/common/CMakeLists.txt" | grep "GIT_TAG" | awk '{print $2}')
VERSION=$(grep -A 3 "GIT_REPOSITORY.*llguidance" "$LLAMA_CPP_SRC/common/CMakeLists.txt" | grep "# v" | sed 's/.*# v\(.*\):/\1/')

if [[ -z "$GIT_TAG" ]]; then
    echo "Error: Could not extract GIT_TAG from CMakeLists.txt"
    exit 1
fi

echo "Found llguidance:"
echo "  Version: $VERSION"
echo "  Git tag: $GIT_TAG"
echo ""

# Check current values in overlay
CURRENT_REV=$(grep 'rev = "' "$OVERLAY_FILE" | head -1 | sed 's/.*"\([a-f0-9]*\)".*/\1/')

if [[ "$CURRENT_REV" == "$GIT_TAG" ]]; then
    echo "llguidance is already up to date ($GIT_TAG)"
    exit 0
fi

echo "Current rev in overlay: $CURRENT_REV"
echo "Need to update to: $GIT_TAG"
echo ""
echo "Fetching new hashes..."

# Get source hash
echo "Getting source hash..."
SRC_HASH=$(nix-prefetch-url --unpack "https://github.com/guidance-ai/llguidance/archive/$GIT_TAG.tar.gz" 2>/dev/null)
SRC_HASH_SRI=$(nix hash to-sri --type sha256 "$SRC_HASH" 2>/dev/null | sed 's/warning:.*//')

# Get cargo hash by building with dummy hash and extracting from error
echo "Getting cargo hash (this may take a moment)..."
CARGO_HASH=$(nix build --impure --expr "
  with import <nixpkgs> {};
  rustPlatform.fetchCargoVendor {
    src = fetchFromGitHub {
      owner = \"guidance-ai\";
      repo = \"llguidance\";
      rev = \"$GIT_TAG\";
      hash = \"$SRC_HASH_SRI\";
    };
    hash = \"sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\";
  }
" 2>&1 | grep "got:" | awk '{print $2}' || true)

if [[ -z "$CARGO_HASH" ]]; then
    echo "Error: Could not fetch cargo hash"
    exit 1
fi

echo ""
echo "New hashes:"
echo "  Source: $SRC_HASH_SRI"
echo "  Cargo:  $CARGO_HASH"
echo ""

# Update the overlay file
echo "Updating $OVERLAY_FILE..."

# Create a backup
cp "$OVERLAY_FILE" "$OVERLAY_FILE.bak"

# Update version
sed -i "s/version = \"[^\"]*\";/version = \"$VERSION\";/" "$OVERLAY_FILE"

# Update rev
sed -i "s|rev = \"[a-f0-9]*\"; # v[0-9.]*|rev = \"$GIT_TAG\"; # v$VERSION|" "$OVERLAY_FILE"

# Update source hash
sed -i "0,/hash = \"sha256-[^\"]*\";/{s|hash = \"sha256-[^\"]*\";|hash = \"$SRC_HASH_SRI\";|}" "$OVERLAY_FILE"

# Update cargo hash
sed -i "0,/cargoHash = \"sha256-[^\"]*\";/{s|cargoHash = \"sha256-[^\"]*\";|cargoHash = \"$CARGO_HASH\";|}" "$OVERLAY_FILE"

echo "Updated overlay file"
echo "  Backup saved to: $OVERLAY_FILE.bak"
echo ""
echo "Please review the changes with:"
echo "  git diff $OVERLAY_FILE"
echo ""
echo "Then test with: nix build .#llama-cpp-cpu-llguidance"
