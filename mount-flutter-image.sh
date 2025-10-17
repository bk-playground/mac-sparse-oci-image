#!/usr/bin/env bash

set -euo pipefail

if [[ -z "${FLUTTER_VERSION:-}" ]]; then
  echo "❌ FLUTTER_VERSION is not set"
  exit 1
fi

if [[ -z "${BUILDKITE_HOSTED_REGISTRY_URL:-}" ]]; then
  echo "❌ BUILDKITE_HOSTED_REGISTRY_URL is not set"
  exit 1
fi

IMAGE_REF="${BUILDKITE_HOSTED_REGISTRY_URL}/my-flutter-image:${FLUTTER_VERSION}"
TMP_DIR="$(mktemp -d)"
MOUNT_POINT="$TMP_DIR/flutter"
FLUTTER_SDK_PATH="$MOUNT_POINT/flutter"

# Cleanup function to ensure unmounting on exit
cleanup() {
  if mount | grep -q "$MOUNT_POINT"; then
    echo "🧹 Unmounting sparse disk image..."
    hdiutil detach "$MOUNT_POINT" 2>/dev/null || true
  fi
  if [[ -d "$TMP_DIR" ]]; then
    echo "🧹 Cleaning up temporary files..."
    rm -rf "$TMP_DIR"
  fi
}

trap cleanup EXIT

# Check if oras is installed, if not install it
if ! command -v oras >/dev/null 2>&1; then
  echo "📥 Installing oras..."
  brew install oras
fi

oras version
echo "📦 Cache is at $ORAS_CACHE"

find $ORAS_CACHE -ls

echo "📥 Downloading sparse disk image from OCI registry: $IMAGE_REF"
cd "$TMP_DIR"
oras pull "$IMAGE_REF" --allow-path-traversal

find $ORAS_CACHE -ls

# Debug: Check what was downloaded
echo "🔍 Searching for downloaded sparse image..."
SPARSE_IMAGE=$(find /var/folders -name "flutter.sparseimage" -type f -mmin -5 2>/dev/null | head -n 1 || true)

if [[ -z "$SPARSE_IMAGE" ]]; then
  echo "❌ No sparse image file found after download"
  echo "📁 Checking /var/folders for any .sparseimage files:"
  find /var/folders -name "*.sparseimage" -type f -mmin -5 2>/dev/null || echo "No .sparseimage files found"
  exit 1
fi

echo "📦 Found sparse image at: $SPARSE_IMAGE"
echo "📦 Moving sparse image to working directory..."
mv "$SPARSE_IMAGE" "$TMP_DIR/flutter.sparseimage"
SPARSE_IMAGE="$TMP_DIR/flutter.sparseimage"

echo "✅ Downloaded: $SPARSE_IMAGE"

echo "💾 Mounting sparse disk image..."
mkdir -p "$MOUNT_POINT"
hdiutil attach "$SPARSE_IMAGE" -mountpoint "$MOUNT_POINT"
echo "✅ Sparse disk image mounted at $MOUNT_POINT"

echo "🔍 Verifying Flutter SDK..."
if [[ ! -d "$FLUTTER_SDK_PATH" ]]; then
  echo "❌ Flutter SDK not found at $FLUTTER_SDK_PATH"
  exit 1
fi

# Update PATH to include Flutter
export PATH="$FLUTTER_SDK_PATH/bin:$PATH"

echo "🚀 Running Flutter version..."
flutter --version

echo "✅ Flutter SDK verification complete!"
