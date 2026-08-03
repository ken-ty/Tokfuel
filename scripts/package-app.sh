#!/bin/bash

# SwiftPMの成果物からTokfuel.appを組み立てる共通処理。
# 呼び出し元はset -euo pipefailを設定し、必要なら事前に出力先を削除する。
#
# 引数:
#   $1 build_dir   SwiftPMの成果物ディレクトリ（.build/release など）
#   $2 app_dir     出力する .app のパス
#   $3 project_dir リポジトリのルート
#   $4 app_name    バンドルの表示名（省略時は Tokfuel）
#   $5 bundle_id   CFBundleIdentifier（省略時は Info.plist の値のまま）
#
# $4 / $5 を渡すと、リリース版と同時にインストールできる開発用バンドルになる。
# 実行ファイル名も表示名に合わせるので、pkill や アクティビティモニタで見分けられる。
package_tokfuel_app() {
  local build_dir="$1"
  local app_dir="$2"
  local project_dir="$3"
  local app_name="${4:-Tokfuel}"
  local bundle_id="${5:-}"
  local product_name="Tokfuel"

  mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
  cp "$build_dir/$product_name" "$app_dir/Contents/MacOS/$app_name"
  cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
  cp -R "$build_dir/${product_name}_${product_name}.bundle" "$app_dir/Contents/Resources/"
  cp "$project_dir/assets/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
  # Firebase は Bundle.main（Contents/Resources）から GoogleService-Info.plist を探す。
  # SPM のリソースバンドル内だけでは見つからないため、アプリバンドル直下にも置く。
  cp "$project_dir/Tokfuel/Sources/Resources/GoogleService-Info.plist" \
    "$app_dir/Contents/Resources/GoogleService-Info.plist"

  local plist="$app_dir/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $app_name" "$plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName $app_name" "$plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $app_name" "$plist"
  if [[ -n "$bundle_id" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$plist"
  fi
}

# Crashlytics のシンボルアップロード（#22）。release.sh から呼ぶ。
# dSYM が無い／upload-symbols が無い場合は非ゼロで返す（呼び出し側が握りつぶす）。
upload_crashlytics_dsym() {
  local app_dir="$1"
  local project_dir="$2"
  local binary="$app_dir/Contents/MacOS/Tokfuel"
  local gsp="$app_dir/Contents/Resources/GoogleService-Info.plist"
  local dsym_dir="$project_dir/dist/Tokfuel.dSYM"
  local upload=""

  # SwiftPM の checkout 先（バージョンでパスが変わるので glob）。
  local candidates=("$project_dir"/.build/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols)
  if [ -x "${candidates[0]:-}" ]; then
    upload="${candidates[0]}"
  else
    # ユニバーサルビルド時は .build/apple 配下に checkouts が無いことがある。
    upload="$(find "$project_dir/.build" -name upload-symbols -type f 2>/dev/null | head -n 1 || true)"
  fi
  if [ -z "$upload" ] || [ ! -x "$upload" ]; then
    echo "upload-symbols not found" >&2
    return 1
  fi
  if [ ! -f "$gsp" ] || [ ! -f "$binary" ]; then
    echo "missing GoogleService-Info.plist or binary" >&2
    return 1
  fi

  rm -rf "$dsym_dir"
  dsymutil "$binary" -o "$dsym_dir"
  # Firebase コンソールの Apple アプリは ios 登録（macOS 専用種別が無い）。
  "$upload" -gsp "$gsp" -p ios "$dsym_dir"
}
