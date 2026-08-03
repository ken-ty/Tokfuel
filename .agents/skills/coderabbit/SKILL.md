---
name: coderabbit
description: >-
  PR に付いた CodeRabbit のレビュー指摘を取り込んで対応する。「PR #1 の CodeRabbit を見て」
  「コードラビットの指摘に対応して」「レビューボットの指摘を直して」のように言われたときに使う。
  インラインコメントと折りたたまれた nitpick の両方を集め、1 件ずつ実コードで再現を確かめ、
  再現したものだけ直し、見送ったものは理由を添えて報告する。提案された diff は鵜呑みにしない。
---

# CodeRabbit の指摘に対応する

CodeRabbit は PR を開いた時点と push のたびに自動レビューを走らせる。このスキルは、その指摘を
**検証してから**取り込むための手順。指摘には各コメントに `🤖 Prompt for AI Agents` が同梱されており、
そこにも「現行コードに対して各指摘を検証し、まだ有効なものだけ直せ」と書かれている。

**このスキルの価値は、指摘を機械的に適用することではなく、再現するかを確かめて直し方を選ぶことにある。**
実測では 12 件中 1 件が再現せず、1 件は指摘の方向は正しいが提案された修正が不適切だった。
一方で 1 件は人のレビューで見落としていた実バグだった。全部拾い、全部疑う。

## 手順

1. **指摘を集める。2 か所に分かれている**

   ```bash
   REPO=ken-ty/Tokfuel   # fork の PR。本家なら Tokfuel/Tokfuel
   PR=1

   # インライン（Actionable comments）
   gh api repos/$REPO/pulls/$PR/comments --paginate \
     -q '.[] | "=== \(.path):\(.line // .original_line) id=\(.id)\n\(.body)\n"'

   # レビュー本体（Nitpick comments は折りたたまれてこちらに入る）
   gh api repos/$REPO/pulls/$PR/reviews --paginate \
     -q '.[] | select(.body != "") | .body'
   ```

   `reviews` 側を読み飛ばすと nitpick を丸ごと落とす。件数は本体冒頭の
   `Actionable comments posted: N` と `Nitpick comments (M)` で突き合わせる。

2. **重大度で読む順を決める**

   各指摘には分類（`🎯 Functional Correctness` / `📐 Maintainability` など）、重大度
   （`🟠 Major` / `🟡 Minor` / `🔵 Trivial`）、費用対効果（`⚡ Quick win` / `💤 Low value`）が付く。
   Major から見る。ただし **Trivial だから正しいとは限らないし、Major だから正しいとも限らない**。

3. **1 件ずつ、実コードで再現を確かめる**

   これが本体。指摘の本文は現行コードを読んで書かれているが、外れることがある。

   - **ロジックの指摘**: 主張された条件を実際にコードで辿る。可能なら失敗するテストを先に書く。
   - **UI の指摘**（レイアウト崩れ・ラベル切れなど）: 推測せず実際に描く。

     ```bash
     swift run Tokfuel --ui-preview /tmp/uiprev   # 全画面を PNG で書き出して目視する
     ```

     表示通貨で幅が変わる指摘なら、USD と JPY の両方で描いて確かめる。
   - **アクセシビリティの指摘**: コードで裏が取れる（ラベルの有無、`.overlay` が下層を
     残すか）。取れないものは「未検証」と明記して扱いを決める。

4. **再現したものだけ直す。提案された diff は出発点として扱う**

   CodeRabbit は修正 diff を添えてくることがあるが、最善とは限らない。たとえば「名前が実装と
   合っていない」という指摘に対し、提案は「名前を変えろ」でも、その値が画面の見出しとして
   大きく出るなら**判定の方を直す**のが正しい。指摘が指している問題を自分で理解してから決める。

5. **検証ゲートを通す**

   ```bash
   swift build
   swift test
   ```

   UI に触ったら `swift run Tokfuel --ui-preview` で描き直して確認する。新しい状態を作ったなら
   `ScreenshotRenderer.allScreens()` と `ui-preview.yml` の `ORDER` / `screen_title` も更新する
   （AGENTS.md の検証ゲート）。

6. **見送りを明示して残す**

   見送った指摘は、コミットメッセージの末尾に理由付きで書く。「再現しなかった」と
   「直さないと決めた」は別なので区別する。後から同じ指摘が再掲されたときに、判断をやり直さずに済む。

   ```
   ポップオーバーの「API 換算（…）」がラベル切れするという指摘は、USD でも JPY でも
   実描画で収まっていたので見送る。
   ```

## PR への返信

指摘への返信・解決済みマークは**外向きの発信なので、勝手にやらない**。必要なら本人に確認してから。

```bash
gh api repos/$REPO/pulls/$PR/comments/<comment-id>/replies -f body='<返信>'
```

再レビューを回したいときは PR コメントで `@coderabbitai review`。コマンド一覧は
`@coderabbitai help` で出る。

## 注意

- このリポジトリに `.coderabbit.yaml` は無い。設定は CodeRabbit の Organization UI 側から来ており、
  レビュープロファイルは `CHILL`。指摘の量や厳しさを変えたいならリポジトリではなくそちらを触る。
- **Autofix (Beta)** のチェックボックス（PR 本文にある「Push a commit to this branch」）は、
  この手順 3 の再現確認を飛ばす。使うなら結果を必ず読み直す。
- ブランチ運用は AGENTS.md に従う。指摘が既存 feature ブランチの中身に対するものなら、`main` から
  新しく切らずそのブランチに積む（upstream に出すとき 1 つの PR として筋が通る）。
