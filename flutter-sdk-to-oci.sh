#!/usr/bin/env bash

set -euo pipefail

if [[ -z "${FLUTTER_VERSION:-}" ]]; then
  echo "❌ FLUTTER_VERSION is not set"
  exit 1
fi

FLUTTER_ZIP_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_${FLUTTER_VERSION}-stable.zip"
TMP_DIR="$(mktemp -d)"
MOUNT_POINT="$TMP_DIR/flutter"
FLUTTER_SDK_PATH="$MOUNT_POINT/flutter"
VERSION_FILE="$FLUTTER_SDK_PATH/VERSION"

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

# this script creates a sparse disk image on macos then uploads it to an OCI registry using oras

echo "📦 Creating sparse disk image..."
hdiutil create -size 4g -type SPARSE -fs APFS -volname "Flutter" "$TMP_DIR/flutter.sparseimage"
hdiutil attach "$TMP_DIR/flutter.sparseimage" -mountpoint "$MOUNT_POINT"
echo "✅ Sparse disk image created and mounted at $MOUNT_POINT"

echo "⬇️  Downloading Flutter SDK version ${FLUTTER_VERSION}..."
curl -sSL "$FLUTTER_ZIP_URL" -o "$TMP_DIR/flutter.zip"
echo "📂 Extracting Flutter SDK directly to sparse disk image..."
unzip -q "$TMP_DIR/flutter.zip" -d "$MOUNT_POINT"
echo "✅ Flutter SDK downloaded and extracted to $FLUTTER_SDK_PATH"

echo "🔍 Verifying Flutter SDK version..."
INSTALLED_VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
if [[ "$INSTALLED_VERSION" == "$FLUTTER_VERSION" ]]; then
  echo "✅ Flutter SDK version $INSTALLED_VERSION verified."
else
  echo "❌ Flutter SDK version mismatch: expected $FLUTTER_VERSION, got $INSTALLED_VERSION"
  exit 1
fi

echo "💾 Detaching sparse disk image..."
hdiutil detach "$MOUNT_POINT"
echo "✅ Sparse disk image detached."

echo "📤 Uploading sparse disk image to OCI registry..."
oras push "oci://my-oci-registry.com/my-flutter-image:latest" --artifact-type "application/vnd.apple.disk-image.sparse" "$TMP_DIR/flutter.sparseimage"
echo "✅ Sparse disk image uploaded to OCI registry."
echo "✅ Cleanup complete."