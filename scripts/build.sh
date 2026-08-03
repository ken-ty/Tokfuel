#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$PROJECT_DIR/scripts/package-app.sh"

# 既定は配布と同じ release 構成で、リリース版と同じ Tokfuel.app を置き換える。
#
#   --debug  開発者向けのデバッグセクション（設定の一番下）を含む debug 構成。
#            置き場所は既定のまま。配布物には使わない。
#   --dev    debug 構成を「Tokfuel Dev.app」として別バンドル ID でインストールする。
#            リリース版と同時に常駐でき、設定（UserDefaults）もバンドル ID ごとに
#            分かれるので、開発中の操作が普段使いの Tokfuel を壊さない。
CONFIG="release"
APP_NAME="Tokfuel"
BUNDLE_ID=""
case "${1:-}" in
  --debug)
    CONFIG="debug"
    ;;
  --dev)
    CONFIG="debug"
    APP_NAME="Tokfuel Dev"
    BUNDLE_ID="com.akidon0000.tokfuel.dev"
    ;;
  "")
    ;;
  *)
    echo "Usage: $0 [--debug|--dev]" >&2
    exit 1
    ;;
esac
APP_DIR="/Applications/${APP_NAME}.app"
BUILD_DIR="$PROJECT_DIR/.build/$CONFIG"

echo "Building $APP_NAME ($CONFIG)..."
cd "$PROJECT_DIR"
swift build -c "$CONFIG" 2>&1

echo "Packaging .app bundle..."
rm -rf "$APP_DIR"
package_tokfuel_app "$BUILD_DIR" "$APP_DIR" "$PROJECT_DIR" "$APP_NAME" "$BUNDLE_ID"

codesign --force --sign - "$APP_DIR" 2>/dev/null || true

echo "Installed to $APP_DIR"
echo ""

# 実行ファイル名はバンドル名に合わせてあるので、--dev で建てた方だけを落とせる。
if pgrep -f "$APP_DIR/Contents/MacOS/" > /dev/null 2>&1; then
  echo "Restarting..."
  pkill -f "$APP_DIR/Contents/MacOS/" 2>/dev/null || true
  sleep 1
fi

echo "Launching..."
open "$APP_DIR"
echo "Done."
