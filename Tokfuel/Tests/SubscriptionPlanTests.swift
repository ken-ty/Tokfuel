import Foundation
import Testing
@testable import Tokfuel

/// プランのカタログと、`AppSettings` 側の出し入れ。実ユーザーの UserDefaults には
/// 触らないよう、テスト専用のスイート名で `UserDefaults` を作る。
@MainActor
struct SubscriptionPlanTests {
    private func makeSettings() -> AppSettings {
        let name = "tokfuel-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return AppSettings(defaults: defaults, codexInstalled: true)
    }

    // MARK: - カタログ

    @Test func 選択肢は契約なしで始まりカスタムで終わる() {
        for vendor in PlanVendor.allCases {
            let options = SubscriptionPlan.options(for: vendor)
            #expect(options.first?.isNone == true)
            #expect(options.last?.isCustom == true)
            #expect(options.allSatisfy { $0.vendor == vendor })
        }
    }

    @Test func プリセットは安い順に並ぶ() {
        for vendor in PlanVendor.allCases {
            let prices = SubscriptionPlan.presets(for: vendor).map(\.monthlyUSD)
            #expect(prices == prices.sorted())
            #expect(prices.allSatisfy { $0 > 0 })
        }
    }

    @Test func ベンダーはコストソースidと対応する() {
        #expect(PlanVendor.claude.sourceID == CostSourceMode.claudeSourceID)
        #expect(PlanVendor.cursor.sourceID == CostSourceMode.cursorSourceID)
        #expect(PlanVendor.codex.sourceID == CostSourceMode.codexSourceID)
    }

    @Test func 未知のidは契約なしへ落ちる() {
        // アプリを戻した・カタログが変わった場合に、存在しない月額を勝手に作らない。
        #expect(SubscriptionPlan.plan(id: "claude.legend", vendor: .claude).isNone)
        #expect(SubscriptionPlan.plan(id: "", vendor: .cursor).isNone)
        // 他ベンダーの id も自分のものとしては引かない。
        #expect(SubscriptionPlan.plan(id: "cursor.pro", vendor: .claude).isNone)
    }

    // MARK: - 設定の出し入れ

    @Test func 既定はどのベンダーも契約なし() {
        let settings = makeSettings()
        #expect(PlanVendor.allCases.allSatisfy { settings.plan(for: $0).isNone })
        #expect(settings.subscriptionMonthlyTotal == 0)
        #expect(settings.hasAnySubscription == false)
    }

    @Test func プリセットを選ぶと月額はカタログの値になる() {
        let settings = makeSettings()
        settings.setPlan(SubscriptionPlan.plan(id: "claude.max20", vendor: .claude), for: .claude)
        #expect(settings.monthlyPlanCost(for: .claude) == 200)
        #expect(settings.subscriptionMonthlyTotal == 200)
        #expect(settings.hasAnySubscription)
    }

    @Test func カスタムは入力した月額を使い負値は受け付けない() {
        let settings = makeSettings()
        settings.setPlan(.custom(.cursor), for: .cursor)
        settings.setCustomMonthly(35, for: .cursor)
        #expect(settings.monthlyPlanCost(for: .cursor) == 35)
        settings.setCustomMonthly(-10, for: .cursor)
        #expect(settings.monthlyPlanCost(for: .cursor) == 0)
    }

    @Test func 表示中のソースに含まれるベンダーだけを比較に載せる() {
        let settings = makeSettings()
        settings.setPlan(SubscriptionPlan.plan(id: "claude.pro", vendor: .claude), for: .claude)
        settings.setPlan(SubscriptionPlan.plan(id: "cursor.pro", vendor: .cursor), for: .cursor)

        settings.costSourceMode = .combined
        #expect(settings.comparablePlanVendors.count == PlanVendor.allCases.count)
        #expect(settings.subscriptionMonthlyTotal == 40)

        // 「Claude のみ」では、見えていない Cursor の定額を合計に足さない。
        settings.costSourceMode = .claudeOnly
        #expect(settings.comparablePlanVendors == [.claude])
        #expect(settings.subscriptionMonthlyTotal == 20)
    }
}
