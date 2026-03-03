#!/bin/bash
set -euo pipefail

# Build llama.cpp xcframework for iOS
# Usage: ./scripts/setup-llama.sh [commit]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VENDOR_DIR="$PROJECT_ROOT/vendor/llama.cpp"
FRAMEWORK_DIR="$PROJECT_ROOT/Frameworks"

LLAMA_REPO="https://github.com/ggml-org/llama.cpp.git"
LLAMA_BRANCH="master"
LLAMA_COMMIT="${1:-}"

echo "==> Setting up llama.cpp xcframework..."

# Clone or update llama.cpp
if [ -d "$VENDOR_DIR" ]; then
    echo "==> Updating existing llama.cpp checkout..."
    cd "$VENDOR_DIR"
    git fetch origin
    if [ -n "$LLAMA_COMMIT" ]; then
        git checkout "$LLAMA_COMMIT"
    else
        git checkout "$LLAMA_BRANCH"
        git pull origin "$LLAMA_BRANCH"
    fi
else
    echo "==> Cloning llama.cpp..."
    mkdir -p "$(dirname "$VENDOR_DIR")"
    git clone --depth 100 "$LLAMA_REPO" "$VENDOR_DIR"
    cd "$VENDOR_DIR"
    if [ -n "$LLAMA_COMMIT" ]; then
        git checkout "$LLAMA_COMMIT"
    fi
fi

echo "==> Building xcframework (this may take several minutes)..."
cd "$VENDOR_DIR"
bash build-xcframework.sh

# Copy xcframework to project
echo "==> Copying xcframework to $FRAMEWORK_DIR..."
mkdir -p "$FRAMEWORK_DIR"
rm -rf "$FRAMEWORK_DIR/llama.xcframework"
cp -R "$VENDOR_DIR/build-apple/llama.xcframework" "$FRAMEWORK_DIR/"

echo "==> Done! llama.xcframework is ready at $FRAMEWORK_DIR/llama.xcframework"
echo "==> Run 'xcodegen generate' to regenerate the Xcode project."
