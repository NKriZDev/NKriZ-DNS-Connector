#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/NKriZDNSConnector.xcodeproj"
SCHEME="NKriZ DNS Connector"
BUILD_DIR="$ROOT_DIR/build"
RELEASE_APP="$BUILD_DIR/Release/NKriZ DNS Connector.app"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="NKriZ DNS Connector"
PKG_ID="com.nkriz.dnsconnector"
VERSION="1.0.0"

echo "==> Building $APP_NAME..."
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$DIST_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  SYMROOT="$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  build

if [[ ! -d "$RELEASE_APP" ]]; then
  echo "Build failed: app bundle not found at $RELEASE_APP" >&2
  exit 1
fi

echo "==> Creating PKG installer..."
PKG_ROOT="$BUILD_DIR/pkg-root"
PKG_SCRIPTS="$BUILD_DIR/pkg-scripts"
rm -rf "$PKG_ROOT" "$PKG_SCRIPTS"
mkdir -p "$PKG_ROOT/Applications" "$PKG_SCRIPTS"

cp -R "$RELEASE_APP" "$PKG_ROOT/Applications/"

cat > "$PKG_SCRIPTS/postinstall" <<'EOF'
#!/bin/bash
APP_PATH="/Applications/NKriZ DNS Connector.app"
if [[ -d "$APP_PATH" ]]; then
  /usr/bin/xattr -cr "$APP_PATH" 2>/dev/null || true
  /usr/bin/open "$APP_PATH" 2>/dev/null || true
fi
exit 0
EOF
chmod +x "$PKG_SCRIPTS/postinstall"

PKG_PATH="$DIST_DIR/NKriZ-DNS-Connector-${VERSION}.pkg"
pkgbuild \
  --root "$PKG_ROOT" \
  --scripts "$PKG_SCRIPTS" \
  --identifier "$PKG_ID" \
  --version "$VERSION" \
  --install-location "/" \
  "$PKG_PATH"

echo "==> Creating DMG..."
DMG_STAGING="$BUILD_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/NKriZ-DNS-Connector-${VERSION}.dmg"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$RELEASE_APP" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo ""
echo "Build complete."
echo "  App:  $RELEASE_APP"
echo "  PKG:  $PKG_PATH"
echo "  DMG:  $DMG_PATH"
