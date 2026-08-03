import Foundation

/// リリース版と並べてインストールした開発用バンドルかどうか（`scripts/build.sh --dev`）。
///
/// 判定はバンドル ID の `.dev` サフィックスだけを見る。設定は `UserDefaults.standard`
/// つまりバンドル ID ごとに分かれるので、追加で切り分けが要るのは Application Support の
/// ディレクトリ名と、メニューバーで両者を見分けるための印だけ。
enum BuildVariant {
    static let isDevelopment = (Bundle.main.bundleIdentifier ?? "").hasSuffix(".dev")

    /// `~/Library/Application Support` 以下のディレクトリ名。
    /// 開発版のイベントログやキャッシュを普段使いの Tokfuel に混ぜない。
    static var appSupportDirectoryName: String { isDevelopment ? "Tokfuel Dev" : "Tokfuel" }
}
