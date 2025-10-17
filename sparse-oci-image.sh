#!/bin/env bash

set -euo pipefail

if [[ -z "${FLUTTER_VERSION:-}" ]]; then
  echo "❌ FLUTTER_VERSION is not set"
  exit 1
fi

FLUTTER_ZIP_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_${FLUTTER_VERSION}-stable.zip"
FLUTTER_CACHE_DIR="flutter-take-four"
FLUTTER_SDK_PATH="$PWD/$FLUTTER_CACHE_DIR/flutter"
VERSION_FILE="$FLUTTER_SDK_PATH/VERSION"
TMP_DIR="$(mktemp -d)"

brew install oras

oras version

# this script creates a sparse disk image on macos then uploads it to an OCI registry using oras

echo "⬇️  Downloading Flutter SDK version ${FLUTTER_VERSION}..."
curl -sSL "$FLUTTER_ZIP_URL" -o "$TMP_DIR/flutter.zip"
unzip -q "$TMP_DIR/flutter.zip" -d "$FLUTTER_CACHE_DIR"
echo "✅ Flutter SDK downloaded and extracted to $FLUTTER_SDK_PATH"
echo "🔍 Verifying Flutter SDK version...  "
INSTALLED_VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
if [[ "$INSTALLED_VERSION" == "$FLUTTER_VERSION" ]]; then
  echo "✅ Flutter SDK version $INSTALLED_VERSION verified."
else
  echo "❌ Flutter SDK version mismatch: expected $FLUTTER_VERSION, got $INSTALLED_VERSION"
  exit 1
fi

echo "📦 Creating sparse disk image..."
hdiutil create -size 2g -type SPARSE -fs APFS -volname "Flutter" "$TMP_DIR/flutter.sparseimage"
hdiutil attach "$TMP_DIR/flutter.sparseimage" -mountpoint "$TMP_DIR/flutter"
echo "✅ Sparse disk image created and mounted."
echo "📂 Copying Flutter SDK to sparse disk image..."
cp -R "$FLUTTER_SDK_PATH"/* "$TMP_DIR/flutter/" 
echo "✅ Flutter SDK copied to sparse disk image."
hdiutil detach "$TMP_DIR/flutter"
echo "📤 Uploading sparse disk image to OCI registry..."
oras push "oci://my-oci-registry.com/my-flutter-image:latest" --artifact-type "application/vnd.apple.disk-image.sparse" "$TMP_DIR/flutter.sparseimage"
echo "✅ Sparse disk image uploaded to OCI registry."
echo "🧹 Cleaning up temporary files..."
rm -rf "$TMP_DIR"
echo "✅ Cleanup complete."