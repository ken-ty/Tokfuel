import Foundation

/// 「いまの使い方に対して、どの契約が一番安いか」を判定する。
///
/// 入力は表示中の実績から作った月換算の API 換算コストと、いま選んでいるプランだけ。
/// ネットワークもプロセス起動も増やさず、判定はすべて純粋関数にする（テストは
/// `Tokfuel/Tests/PlanDiagnosisTests.swift`）。
///
/// 判定モデルは意図的に単純にしてある。
/// - 定額プランを契約している間は、その月の支払いは月額だけとみなす（超過従量は数えない）。
/// - 契約なしなら、支払いは API 換算コストそのもの。
/// つまり「実効月額 = 契約していれば月額、していなければ API 換算」。
///
/// ただし金額だけで最安を選ぶと、月 $1,000 使う人に $20 のプランを勧めてしまう。定額には
/// 利用上限があるので、**その使用量を吸収できそうなプランだけを推奨候補にする**
/// （`coverageMultiple` 倍まで）。上限の実数値は各社とも公開していないため、ここは推定であり、
/// 当たっているとは限らない——だから推奨に残った場合も `mayHitRateLimit` で断る。
enum PlanDiagnosis {
    /// 定額プランが吸収できるとみなす API 換算の上限（月額の何倍まで）。
    /// 各社の公称上限は非公開なので、これは控えめな推定値。
    static let coverageMultiple = 3.0
    /// 判定の根拠として心もとない期間（日）。これ未満なら UI で長い期間を勧める。
    static let shortWindowDays = 7

    // MARK: - 入力

    struct VendorInput: Equatable, Sendable {
        let vendor: PlanVendor
        /// このベンダーの API 換算コストの月換算 (USD)。
        let monthlyAPIEquivalentUSD: Double
        /// いま選んでいるプラン。
        let currentPlan: SubscriptionPlan
        /// いま選んでいるプランの実際の月額 (USD)。カスタム枠はここに入力値が入る。
        let currentMonthlyUSD: Double
    }

    struct Input: Equatable, Sendable {
        var vendors: [VendorInput] = []
        /// 月換算の元になった実績の日数（表示中の期間の経過日数）。
        var windowDays: Int = 0
        /// 月換算の元になった期間の名前（「今月」など）。文面にそのまま出す。
        var windowLabel: String = ""
    }

    // MARK: - 出力

    struct VendorResult: Identifiable, Equatable, Sendable {
        let vendor: PlanVendor
        let currentPlan: SubscriptionPlan
        let apiEquivalentUSD: Double
        /// いまの契約での実効月額。
        let currentEffectiveUSD: Double
        /// 一番安くなるプラン。
        let recommended: SubscriptionPlan
        /// 推奨プランでの実効月額。
        let recommendedEffectiveUSD: Double
        /// 乗り換えで減る月あたりの額（0 なら今のままが最安）。
        let savingUSD: Double
        /// 推奨が定額で、API 換算がその月額を大きく超えている（＝上限に当たり得る）。
        let mayHitRateLimit: Bool

        var id: String { vendor.rawValue }
        var isCurrentBest: Bool { recommended.id == currentPlan.id }

        /// 1 行の結論。
        var headline: String {
            if isCurrentBest {
                return currentPlan.isNone
                    ? "API 従量のままが最安です"
                    : "\(currentPlan.name) のままが最安です"
            }
            if recommended.isNone {
                return "API 従量に戻すと月 \(Money.format(savingUSD)) 減ります"
            }
            return "\(recommended.name) にすると月 \(Money.format(savingUSD)) 減ります"
        }

        /// 根拠。金額の出どころを毎回言い切る（推定であることを隠さない）。
        var detail: String {
            var text = "API 換算は月 \(Money.format(apiEquivalentUSD)) 相当、"
                + "いまの契約の実効月額は \(Money.format(currentEffectiveUSD)) です。"
            if mayHitRateLimit {
                text += "ただし API 換算が \(recommended.name) の月額の "
                    + "\(String(format: "%.1f", apiEquivalentUSD / max(recommendedEffectiveUSD, 0.01))) 倍あります。"
                    + "定額プランには利用上限があるため、この量をそのまま定額で使い切れるとは限りません。"
            }
            return text
        }
    }

    struct Result: Equatable, Sendable {
        let vendors: [VendorResult]
        let windowDays: Int
        let windowLabel: String

        /// いまの構成の実効月額の合計。
        var currentMonthlyTotal: Double { vendors.reduce(0) { $0 + $1.currentEffectiveUSD } }
        /// 推奨構成の実効月額の合計。
        var recommendedMonthlyTotal: Double { vendors.reduce(0) { $0 + $1.recommendedEffectiveUSD } }
        /// すべて API 従量にしたときの月額（＝お得さの比較対象）。
        var apiOnlyMonthlyTotal: Double { vendors.reduce(0) { $0 + $1.apiEquivalentUSD } }
        /// いま払っている定額の合計。
        var subscriptionMonthlyTotal: Double {
            vendors.filter { !$0.currentPlan.isNone }.reduce(0) { $0 + $1.currentEffectiveUSD }
        }
        var savingUSD: Double { max(0, currentMonthlyTotal - recommendedMonthlyTotal) }
        /// 判定の根拠になった実績が短すぎるか。
        var isShortWindow: Bool { windowDays < shortWindowDays }
        /// 判定できる材料が 1 つも無い（表示中のソースにベンダーがいない）。
        var isEmpty: Bool { vendors.isEmpty }

        /// いまの使い方が定額中心か従量中心か。
        var isSubscriptionCentric: Bool {
            vendors.contains { !$0.currentPlan.isNone }
        }

        /// API 換算が一番大きいベンダー（＝どこを削るのが効くか）。
        var dominantVendor: PlanVendor? {
            vendors.max { $0.apiEquivalentUSD < $1.apiEquivalentUSD }
                .flatMap { $0.apiEquivalentUSD > 0 ? $0.vendor : nil }
        }

        /// 全体の結論 1 行。
        var summary: String {
            guard !isEmpty else { return "比較できる実績も契約もまだありません。" }
            if savingUSD <= 0 {
                return isSubscriptionCentric
                    ? "いまの契約がこの使い方に対して最安です。"
                    : "API 従量のままがこの使い方に対して最安です。"
            }
            return "契約を見直すと月あたり \(Money.format(savingUSD)) 減らせます"
                + "（\(Money.format(currentMonthlyTotal)) → \(Money.format(recommendedMonthlyTotal))）。"
        }

        /// 1 年続けたときの差。月額だけだと小さく見える差を、判断できる大きさで見せる。
        var annualSavingUSD: Double { savingUSD * 12 }
    }

    // MARK: - 判定

    static func diagnose(_ input: Input) -> Result {
        Result(vendors: input.vendors.map(verdict(for:)),
               windowDays: input.windowDays,
               windowLabel: input.windowLabel)
    }

    static func verdict(for input: VendorInput) -> VendorResult {
        let currentEffective = effectiveMonthly(
            plan: input.currentPlan,
            monthlyUSD: input.currentMonthlyUSD,
            apiEquivalentUSD: input.monthlyAPIEquivalentUSD)

        // 候補は「契約なし」と公称プランだけ。カスタムは他人の契約条件を推測することに
        // なるので勧めない（いまの契約としては当然そのまま扱う）。
        // 定額は、この使用量を吸収できそうなものだけを残す——月 $1,000 使う人に $20 の
        // プランを「最安」として勧めないため。契約なしには上限が無いので常に残る。
        var candidates: [(plan: SubscriptionPlan, effective: Double)] =
            ([SubscriptionPlan.none(input.vendor)] + SubscriptionPlan.presets(for: input.vendor))
            .filter { covers(plan: $0, apiEquivalentUSD: input.monthlyAPIEquivalentUSD) }
            .map { ($0, effectiveMonthly(plan: $0, monthlyUSD: $0.monthlyUSD,
                                         apiEquivalentUSD: input.monthlyAPIEquivalentUSD)) }
        // いまの契約も候補に含める。カスタム枠を選んでいる人に、同額のプリセットへの
        // 「乗り換え」を勧めてしまわないよう、同値なら現状を勝ち残らせる（下の並べ替え）。
        candidates.append((input.currentPlan, currentEffective))

        let best = candidates.min { lhs, rhs in
            if lhs.effective != rhs.effective { return lhs.effective < rhs.effective }
            // 同額なら現状維持 → 安い月額 の順で優先する。
            if (lhs.plan.id == input.currentPlan.id) != (rhs.plan.id == input.currentPlan.id) {
                return lhs.plan.id == input.currentPlan.id
            }
            return lhs.plan.monthlyUSD < rhs.plan.monthlyUSD
        }
        let recommended = best?.plan ?? input.currentPlan
        let recommendedEffective = best?.effective ?? currentEffective

        return VendorResult(
            vendor: input.vendor,
            currentPlan: input.currentPlan,
            apiEquivalentUSD: input.monthlyAPIEquivalentUSD,
            currentEffectiveUSD: currentEffective,
            recommended: recommended,
            recommendedEffectiveUSD: recommendedEffective,
            savingUSD: max(0, currentEffective - recommendedEffective),
            // 推奨が定額なら、その実効月額（＝プラン月額）で吸収できるかを見る。カスタム枠が
            // 残った場合もここで拾えるよう、カタログの月額ではなく実効額で判定する。
            mayHitRateLimit: !recommended.isNone
                && input.monthlyAPIEquivalentUSD > recommendedEffective * coverageMultiple)
    }

    /// 実効月額。契約していれば月額、していなければ API 換算そのもの。
    static func effectiveMonthly(plan: SubscriptionPlan,
                                 monthlyUSD: Double,
                                 apiEquivalentUSD: Double) -> Double {
        plan.isNone ? apiEquivalentUSD : monthlyUSD
    }

    /// この使用量をプランが吸収できそうか。従量には上限が無いので常に true。
    /// カスタム枠は月額をここでは知らない（推奨候補にも入れない）ので、判定しない。
    static func covers(plan: SubscriptionPlan, apiEquivalentUSD: Double) -> Bool {
        guard plan.isPreset else { return true }
        return apiEquivalentUSD <= plan.monthlyUSD * coverageMultiple
    }

    // MARK: - 月換算

    /// 期間の実績を月あたりへ引き延ばす。`windowDays` 日で `spend` 使ったペースが
    /// 今月いっぱい続いた場合の額を返す。日数が取れないときは 0（外挿の根拠が無い）。
    static func monthlyEquivalent(spend: Double, windowDays: Int,
                                  now: Date = Date(), calendar: Calendar = .current) -> Double {
        guard windowDays > 0, spend > 0,
              let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count
        else { return 0 }
        return spend / Double(windowDays) * Double(daysInMonth)
    }
}
