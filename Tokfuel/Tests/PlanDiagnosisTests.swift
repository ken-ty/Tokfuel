import Foundation
import Testing
@testable import Tokfuel

/// 契約の診断。実効月額の比較、同額のときの現状維持、定額の上限に対する注意、
/// そして月換算の外挿を見る。
struct PlanDiagnosisTests {
    /// カスタム枠は月額を辞書側に持つので、テストでは実額を明示して組む。
    private func input(vendor: PlanVendor = .claude,
                       api: Double,
                       plan: SubscriptionPlan,
                       monthly: Double? = nil) -> PlanDiagnosis.VendorInput {
        PlanDiagnosis.VendorInput(vendor: vendor,
                                  monthlyAPIEquivalentUSD: api,
                                  currentPlan: plan,
                                  currentMonthlyUSD: monthly ?? plan.monthlyUSD)
    }

    private func preset(_ vendor: PlanVendor, _ name: String) -> SubscriptionPlan {
        SubscriptionPlan.presets(for: vendor).first { $0.name == name }!
    }

    // MARK: - 実効月額

    @Test func 契約なしの実効月額はAPI換算そのもの() {
        let result = PlanDiagnosis.verdict(
            for: input(api: 143, plan: .none(.claude)))
        #expect(result.currentEffectiveUSD == 143)
    }

    @Test func 契約中の実効月額は月額だけで超過従量は数えない() {
        let result = PlanDiagnosis.verdict(
            for: input(api: 1430, plan: preset(.claude, "Max 20x")))
        #expect(result.currentEffectiveUSD == 200)
    }

    // MARK: - 推奨

    @Test func API換算が月額を上回るなら定額を勧める() {
        let result = PlanDiagnosis.verdict(for: input(api: 500, plan: .none(.claude)))
        // 月 $500 を吸収できるのは Max 20x（$200 × 3）だけ。Pro や Max 5x は金額こそ安いが、
        // この使用量を定額で通せる見込みが無いので候補から外れる。
        #expect(result.recommended.name == "Max 20x")
        #expect(result.recommendedEffectiveUSD == 200)
        #expect(result.savingUSD == 300)
        #expect(result.isCurrentBest == false)
    }

    @Test func 吸収できない使用量では安いプランを勧めない() {
        // 月 $1,430 は最上位プラン（$200 × 3 = $600）でも吸収できない。従量と現状だけが残り、
        // 現状（Max 20x）の方が安いので現状維持になる。
        let result = PlanDiagnosis.verdict(
            for: input(api: 1430, plan: preset(.claude, "Max 20x")))
        #expect(result.isCurrentBest)
        #expect(result.savingUSD == 0)
        // 定額で通せる保証は無いので、そのことは必ず添える。
        #expect(result.mayHitRateLimit)
    }

    @Test func API換算が最安プランを下回るなら従量のままを勧める() {
        let result = PlanDiagnosis.verdict(for: input(api: 12, plan: preset(.claude, "Pro")))
        #expect(result.recommended.isNone)
        #expect(result.savingUSD == 8)
        #expect(result.headline == "API 従量に戻すと月 $8.00 減ります")
    }

    @Test func 同額なら現状のプランを勝ち残らせる() {
        // カスタムで $20 を入れている人に、同額の Pro への乗り換えを勧めない。
        let custom = SubscriptionPlan.custom(.claude)
        let result = PlanDiagnosis.verdict(
            for: input(api: 500, plan: custom, monthly: 20))
        #expect(result.isCurrentBest)
        #expect(result.savingUSD == 0)
        #expect(result.headline == "カスタム のままが最安です")
    }

    @Test func 現状が最安ならその旨だけを言う() {
        let result = PlanDiagnosis.verdict(for: input(api: 500, plan: preset(.claude, "Pro")))
        #expect(result.isCurrentBest)
        #expect(result.headline == "Pro のままが最安です")
    }

    // MARK: - 定額の利用上限

    @Test func API換算が月額の三倍を超えたら上限の注意を立てる() {
        // $601 は Max 20x ($200) の 3 倍超。従量 ($601) より現状 ($200) が安いので推奨は
        // 現状維持になるが、その定額で通せる保証は無い。
        let over = PlanDiagnosis.verdict(for: input(api: 601, plan: preset(.claude, "Max 20x")))
        #expect(over.mayHitRateLimit)
        #expect(over.detail.contains("使い切れるとは限りません"))
        // ちょうど 3 倍は超えていないので立てない。
        let exact = PlanDiagnosis.verdict(for: input(api: 600, plan: preset(.claude, "Max 20x")))
        #expect(exact.mayHitRateLimit == false)
    }

    @Test func 従量を勧めるときは上限の注意を立てない() {
        let result = PlanDiagnosis.verdict(for: input(api: 5, plan: preset(.claude, "Pro")))
        #expect(result.recommended.isNone)
        #expect(result.mayHitRateLimit == false)
    }

    // MARK: - 合計

    @Test func 合計は現状と推奨とすべて従量の三本を出す() {
        let result = PlanDiagnosis.diagnose(PlanDiagnosis.Input(
            vendors: [
                input(vendor: .claude, api: 1430, plan: preset(.claude, "Max 20x")),
                input(vendor: .cursor, api: 8, plan: preset(.cursor, "Pro"))
            ],
            windowDays: 30, windowLabel: "今月"))
        // Claude は Max 20x のまま（$200）、Cursor は従量へ落として $8。
        #expect(result.currentMonthlyTotal == 220)
        #expect(result.recommendedMonthlyTotal == 208)
        #expect(result.apiOnlyMonthlyTotal == 1438)
        #expect(result.subscriptionMonthlyTotal == 220)
        #expect(result.savingUSD == 12)
        #expect(result.annualSavingUSD == 144)
        #expect(result.dominantVendor == .claude)
        #expect(result.isSubscriptionCentric)
    }

    @Test func 削減が無いときの結論は現状肯定になる() {
        let subscribed = PlanDiagnosis.diagnose(PlanDiagnosis.Input(
            vendors: [input(api: 1430, plan: preset(.claude, "Max 20x"))],
            windowDays: 30, windowLabel: "今月"))
        #expect(subscribed.savingUSD == 0)
        #expect(subscribed.summary == "いまの契約がこの使い方に対して最安です。")

        let payAsYouGo = PlanDiagnosis.diagnose(PlanDiagnosis.Input(
            vendors: [input(api: 3, plan: .none(.claude))],
            windowDays: 30, windowLabel: "今月"))
        #expect(payAsYouGo.summary == "API 従量のままがこの使い方に対して最安です。")
        #expect(payAsYouGo.isSubscriptionCentric == false)
    }

    @Test func ソースが無ければ空として扱う() {
        let result = PlanDiagnosis.diagnose(PlanDiagnosis.Input())
        #expect(result.isEmpty)
        #expect(result.dominantVendor == nil)
        #expect(result.summary == "比較できる実績も契約もまだありません。")
    }

    @Test func 実績が七日未満なら短い窓として印を付ける() {
        #expect(PlanDiagnosis.diagnose(
            PlanDiagnosis.Input(vendors: [], windowDays: 6, windowLabel: "今週")).isShortWindow)
        #expect(PlanDiagnosis.diagnose(
            PlanDiagnosis.Input(vendors: [], windowDays: 7, windowLabel: "今週"))
            .isShortWindow == false)
    }

    // MARK: - 月換算

    @Test func 月換算は期間の日次ペースを当月の日数まで伸ばす() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // 2026-04（30 日）に、7 日で $70 使ったペース → 月 $300。
        let april = DateComponents(calendar: calendar, year: 2026, month: 4, day: 10).date!
        #expect(PlanDiagnosis.monthlyEquivalent(
            spend: 70, windowDays: 7, now: april, calendar: calendar) == 300)
    }

    @Test func 外挿の根拠が無ければ月換算はゼロ() {
        #expect(PlanDiagnosis.monthlyEquivalent(spend: 0, windowDays: 7) == 0)
        #expect(PlanDiagnosis.monthlyEquivalent(spend: 70, windowDays: 0) == 0)
    }
}
