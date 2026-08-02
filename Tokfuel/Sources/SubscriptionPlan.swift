import Foundation

/// サブスクを契約する相手先。コストソース id（`CostSourceMode` / `CostDriver.id`）と 1:1 で対応
/// させ、表示中のソースに含まれるベンダーだけを比較に載せられるようにする。
enum PlanVendor: String, CaseIterable, Identifiable, Sendable {
    case claude, codex, cursor

    var id: String { rawValue }

    /// 対応するコストソース id。`CostSourceMode.includes(sourceID:)` にそのまま渡せる。
    var sourceID: String {
        switch self {
        case .claude: return CostSourceMode.claudeSourceID
        case .codex: return CostSourceMode.codexSourceID
        case .cursor: return CostSourceMode.cursorSourceID
        }
    }

    /// UI に出す名前。課金はどれもアカウント単位なので、CLI 名（Codex）ではなく
    /// 契約の名前（ChatGPT）で呼ぶ——設定画面で探すのは請求書に出ている方の名前。
    var label: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "ChatGPT"
        case .cursor: return "Cursor"
        }
    }
}

/// 定額プラン 1 つ。月額は内部表現に合わせて常に USD で持つ。
///
/// 公称価格は変わるものなので、カタログはあくまでプリセットとして持ち、ベンダーごとに
/// 「カスタム」枠を必ず 1 つ用意する。値上げ・年払い・法人契約・為替のどれもここで吸収できる
/// ——アプリの更新を待たずにユーザーが正しい額を入れられることを、陳腐化への答えにする。
struct SubscriptionPlan: Identifiable, Equatable, Sendable {
    let id: String
    let vendor: PlanVendor
    /// プラン名（「Max 20x」「Plus」など）。`none` と `custom` は状態を表す名前を持つ。
    let name: String
    /// 月額 (USD)。`none` は 0（固定費が無く、使ったぶんだけ API に払う）。
    /// `custom` はここでは 0 で、実額は `AppSettings.customPlanMonthlyUSD` が持つ。
    let monthlyUSD: Double

    static let noneSuffix = ".none"
    static let customSuffix = ".custom"

    /// 契約なし（API 従量）か。
    var isNone: Bool { id.hasSuffix(Self.noneSuffix) }
    /// ユーザーが月額を自分で入れる枠か。
    var isCustom: Bool { id.hasSuffix(Self.customSuffix) }
    /// 定額を払っている枠か（推奨候補として扱えるのはこれと `none` だけ）。
    var isPreset: Bool { !isNone && !isCustom }

    /// プリセット価格の基準時点。UI に必ず添えて、古い数字を黙って見せない。
    static let priceAsOf = "2026-08"

    // MARK: - カタログ

    static func none(_ vendor: PlanVendor) -> SubscriptionPlan {
        SubscriptionPlan(id: vendor.rawValue + noneSuffix, vendor: vendor,
                         name: "契約なし（API 従量）", monthlyUSD: 0)
    }

    static func custom(_ vendor: PlanVendor) -> SubscriptionPlan {
        SubscriptionPlan(id: vendor.rawValue + customSuffix, vendor: vendor,
                         name: "カスタム", monthlyUSD: 0)
    }

    /// ベンダー 1 つぶんの選択肢（契約なし → 安い順のプリセット → カスタム）。
    static func options(for vendor: PlanVendor) -> [SubscriptionPlan] {
        [none(vendor)] + presets(for: vendor) + [custom(vendor)]
    }

    /// 公称の定額プラン（`priceAsOf` 時点）。安い順に並べる。
    static func presets(for vendor: PlanVendor) -> [SubscriptionPlan] {
        switch vendor {
        case .claude:
            return [
                SubscriptionPlan(id: "claude.pro", vendor: .claude, name: "Pro", monthlyUSD: 20),
                SubscriptionPlan(id: "claude.max5", vendor: .claude, name: "Max 5x", monthlyUSD: 100),
                SubscriptionPlan(id: "claude.max20", vendor: .claude, name: "Max 20x", monthlyUSD: 200)
            ]
        case .codex:
            return [
                SubscriptionPlan(id: "codex.plus", vendor: .codex, name: "Plus", monthlyUSD: 20),
                SubscriptionPlan(id: "codex.pro", vendor: .codex, name: "Pro", monthlyUSD: 200)
            ]
        case .cursor:
            return [
                SubscriptionPlan(id: "cursor.pro", vendor: .cursor, name: "Pro", monthlyUSD: 20),
                SubscriptionPlan(id: "cursor.ultra", vendor: .cursor, name: "Ultra", monthlyUSD: 200)
            ]
        }
    }

    /// 保存済み id からプランを引く。未知の id（アプリを戻した・カタログが変わった）は
    /// そのベンダーの「契約なし」へ落とす——存在しないプランの月額を勝手に決めない。
    static func plan(id: String, vendor: PlanVendor) -> SubscriptionPlan {
        options(for: vendor).first { $0.id == id } ?? none(vendor)
    }
}
