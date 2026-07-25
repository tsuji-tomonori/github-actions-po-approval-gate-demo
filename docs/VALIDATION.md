# Live validation evidence

検証日: 2026-07-25（JST）

## 判定

| 対象 | 結果 | 証跡 |
|---|---|---|
| Public repositoryとsource投入 | PASS | 初期実装コミット`855de0736517be9ed7e011d535fa0eeaafb257c0` |
| Pull Request CI | PASS | PR #9 HEAD `580cd4e74b58c2df92e99300b2aafedd7e4cb2f8`、run `30151297233` |
| 許可方向のexact-SHA判定 | PASS | PR #9の`Validate branch direction`、external ID `branch-direction:9:580cd4e74b58c2df92e99300b2aafedd7e4cb2f8`、conclusion `success` |
| 逆方向`prd -> main`の拒否 | PASS | PR #12 HEAD `a363142da023a7ea64b30aa9a9b8b9d31395763c`、exact-SHA Check conclusion `failure` |
| 判定のコメントAPI非依存化 | PASS | PR #15、merge SHA `c87039d4483dc25cb0bd52459bf6fb042bf8f48c` |
| `prd`マージ由来の検証 | PASS | PR #4、merge SHA `eeafeb4c43c59ff92fc3bfb200a2007af9b4c206` |
| production deployment simulation | PASS | run `30144224312` |
| deployment artifact | PASS | artifact ID `8615456219`、digest `sha256:ffa3f0dd23dffd48bcf439e3c3e2103fd9fbf8a12ac665f6780b1f6a438dd746` |
| artifact内容の相互一致 | PASS | repository、merge SHA、source PR #4、run IDが一致 |
| required reviewerによる待機 | 未認定 | Repository Administration設定の適用後に人間の操作で確認します |
| Rulesetによるマージ拒否 | 未認定 | Repository Administration設定の適用後に確認します |

## 修正した問題

PR #8は`prd -> main`の逆方向で作成されていました。PO承認Workflowは`prd`をbaseとするPull Requestだけを対象にするため、逆方向PRはPO承認の対象外です。さらに`main`の通常CIが成功すると、Ruleset未適用の状態ではマージ可能に見えていました。

次の方針へ修正しました。

```text
feature/* -> main -> prd -> Deploy production
                         ^ PO approval required
```

- `main`を正規のソースブランチとします。
- `prd`をデプロイ専用の到達先とします。
- `prd`をheadとするPull Requestはすべて拒否します。
- `Validate branch direction`はPull Requestの正確なHEAD SHAへChecks APIで作成します。
- `pull_request_target`と、CI完了後の`workflow_run`の両方から冪等に再評価します。
- 信頼済みWorkflowはPull Requestのコードをcheckout、install、実行しません。
- PRコメントAPIは判定経路から除外し、権限制約や一時障害が判定を変えないようにしました。

関連PR:

- PR #10: 一方向のrelease flowと契約テストを追加
- PR #11: exact-SHA Checkを追加
- PR #13: CI完了後のtrusted reconciliationを追加
- PR #15: PRコメントAPI依存を除去

## 許可方向の証跡

正しい方向のDraft PR #9は、`chore/reconcile-prd-with-main -> prd`です。HEADは`580cd4e74b58c2df92e99300b2aafedd7e4cb2f8`です。

確認結果:

```text
Validate repository: success
Validate branch direction: success
PO approval for PRD: in_progress
```

`Validate branch direction`のCheck output:

```text
title: Branch direction accepted
external_id: branch-direction:9:580cd4e74b58c2df92e99300b2aafedd7e4cb2f8
head: chore/reconcile-prd-with-main
base: prd
HEAD SHA: 580cd4e74b58c2df92e99300b2aafedd7e4cb2f8
trigger: workflow_run
```

`PO approval for PRD`も同じHEAD SHAへ作成され、承認待ちを表す`in_progress`です。PR #9はRepository Administration設定を適用し、POが現在のHEAD SHAを承認するまでDraftのまま維持します。

## 逆方向拒否の証跡

負のテストPR #12は`prd -> main`です。HEADは`a363142da023a7ea64b30aa9a9b8b9d31395763c`です。

exact-SHA Check:

```text
name: Validate branch direction
external_id: branch-direction:12:a363142da023a7ea64b30aa9a9b8b9d31395763c
conclusion: failure
title: Reverse release flow rejected
head: prd
base: main
HEAD SHA: a363142da023a7ea64b30aa9a9b8b9d31395763c
trigger: workflow_run
```

PR #15適用後の`pull_request_target` run `30151360664`、job `89662174906`では、Checkを作成・更新したあと、禁止方向であることを理由に意図どおり失敗しました。以前発生していたPRコメント作成時のHTTP 403はなく、ログ末尾は次だけです。

```text
One or more Pull Requests use a forbidden branch direction.
```

したがって、逆方向PRは判定ロジックによって拒否され、観測用コメントの権限エラーによって失敗しているわけではありません。PR #12はマージせずクローズします。

## デプロイ証跡

PR #4を`prd`へsquash mergeした結果、merge SHAは`eeafeb4c43c59ff92fc3bfb200a2007af9b4c206`になりました。Deploy production run `30144224312`では次が成功しました。

- `Verify merged PR provenance`
- `Deploy production`
- repository checkout
- simulation実行
- artifact upload

生成されたartifact:

```text
name: production-deployment-eeafeb4c43c59ff92fc3bfb200a2007af9b4c206
artifact id: 8615456219
sha256: ffa3f0dd23dffd48bcf439e3c3e2103fd9fbf8a12ac665f6780b1f6a438dd746
```

artifact内の`deployment.json`:

```json
{
  "commit_sha": "eeafeb4c43c59ff92fc3bfb200a2007af9b4c206",
  "mode": "simulation",
  "repository": "tsuji-tomonori/github-actions-po-approval-gate-demo",
  "schema_version": "production-deployment-evidence/v1",
  "source_pull_request": 4,
  "workflow_run_id": "30144224312"
}
```

## 残るRepository Administration設定

コード上の判定、CI、逆方向拒否、exact-SHA binding、マージ後デプロイは検証済みです。残るのはGitHub EnvironmentとRulesetの管理設定です。

repository administratorとして認証した端末で実行します。

```bash
bash scripts/configure-repository.sh \
  tsuji-tomonori \
  github-actions-po-approval-gate-demo \
  tsuji-tomonori

bash scripts/verify-repository.sh \
  tsuji-tomonori \
  github-actions-po-approval-gate-demo \
  tsuji-tomonori
```

最終合格条件:

1. `prd-approval`のrequired reviewerがPO役のユーザーだけです。
2. required reviewer以外は［Approve and deploy］を実行できません。
3. `PO approval for PRD`がpendingの間、`prd`へマージできません。
4. PO承認後にコミットを追加すると、新しいSHAで再承認が必要になります。
5. 再承認後の`prd`マージだけがDeploy productionを起動します。
