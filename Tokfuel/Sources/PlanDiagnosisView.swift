import SwiftUI

/// 「診断」の中身。いまの使い方（従量か定額か）、この使い方が続いたときの費用、
/// ベンダーごとの推奨プラン、そして合計での最小構成を 1 画面で見せる。
///
/// 入力は `PlanDiagnosis.Result` だけで、ライブな `UsageStore` には触らない
/// ——スクリーンショット（`ScreenshotRenderer`）が同じビューをそのまま描けるようにする。
struct PlanDiagnosisView: View {
    let result: PlanDiagnosis.Result
    var onClose: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if result.isEmpty {
                        emptyState
                    } else {
                        currentUsage
                        forecast
                        vendorVerdicts
                        notes
                    }
                }
                .padding(16)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text("診断")
                .font(.headline)
            Spacer()
            Button("閉じる", action: onClose)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - いまの使い方

    private var currentUsage: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("いまの使い方")
            Text(result.isSubscriptionCentric ? "定額（サブスク）中心" : "API 従量")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("\(result.windowLabel)の実績（\(result.windowDays) 日）を月あたりへ引き延ばして判定しています。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if result.isShortWindow {
                // すでに「今月」以上を見ている人に期間の変更を勧めても、変える先が無い。
                Label(result.canWidenWindow
                      ? "実績が \(result.windowDays) 日ぶんしかありません。推移の期間を「今月」にすると判定が安定します。"
                      : "実績が \(result.windowDays) 日ぶんしかありません。日数がたつと判定が安定します。",
                      systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 今後の費用

    private var forecast: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("このペースが続いたら")
            amountRow("いまの構成", amount: result.currentMonthlyTotal, suffix: "/月")
            amountRow("すべて API 従量", amount: result.apiOnlyMonthlyTotal, suffix: "/月",
                      muted: true)
            amountRow("推奨構成", amount: result.recommendedMonthlyTotal, suffix: "/月",
                      highlighted: result.savingUSD > 0)
            Text(result.summary)
                .font(.caption)
                .foregroundStyle(result.savingUSD > 0 ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            if result.savingUSD > 0 {
                Text("1 年続けると \(PopoverView.money(result.annualSavingUSD)) の差になります。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - ベンダーごとの推奨

    private var vendorVerdicts: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("推奨構成")
            ForEach(result.vendors) { vendor in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(vendor.vendor.label)
                            .font(.caption.weight(.semibold))
                        Text(vendor.currentPlan.isNone ? "API 従量" : vendor.currentPlan.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                        Spacer()
                        Image(systemName: vendor.isCurrentBest
                              ? "checkmark.circle" : "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(vendor.isCurrentBest ? .secondary : Color.accentColor)
                    }
                    Text(vendor.headline)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(vendor.detail)
                        .font(.caption2)
                        .foregroundStyle(vendor.mayHitRateLimit
                                         ? PopoverView.warningTint : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let dominant = result.dominantVendor, result.vendors.count > 1 {
                Text("使用量が一番大きいのは \(dominant.label) です。"
                     + "プラットフォームを絞るなら、ここを削るか上位プランへ寄せるのが最も効きます。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 注記

    /// 数字の出どころと限界。これを省くと、推定値が確定額のように読める。
    private var notes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text("・API 換算は、記録されたトークン量に API 価格表を当てた推定です（実際の請求ではありません）。")
            Text("・プリセットの月額は \(SubscriptionPlan.priceAsOf) 時点の公称価格です。実額が違うときは設定の「カスタム」に入れてください。")
            Text("・定額プランには利用上限があります。金額だけでは上限に届くかまでは判定できません。")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("比較できる実績も契約もまだありません。")
                .font(.caption)
            Text("使用量が記録されるか、契約中のプランを登録すると判定できます。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("設定を開く", action: onOpenSettings)
                .controlSize(.small)
        }
    }

    // MARK: - 部品

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func amountRow(_ title: String, amount: Double, suffix: String,
                           muted: Bool = false, highlighted: Bool = false) -> some View {
        let amountColor: Color = highlighted ? .accentColor : (muted ? .secondary : .primary)
        return HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.secondary)
            Spacer()
            Text(PopoverView.money(amount) + suffix)
                .font(.caption.monospacedDigit())
                .foregroundStyle(amountColor)
        }
    }
}
