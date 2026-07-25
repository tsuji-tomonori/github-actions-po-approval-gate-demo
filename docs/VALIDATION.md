# Live validation evidence

検証日: 2026-07-25（JST）

## 判定

| 対象 | 結果 | 証跡 |
|---|---|---|
| Public repositoryとsource投入 | PASS | `main`の実装コミット`855de0736517be9ed7e011d535fa0eeaafb257c0` |
| Pull Request CI | PASS | PR #4、run `30144203624`、job `Validate repository` |
| 最新HEAD SHAへのPO Check作成 | PASS | PR #4 HEAD `03ab6f5f5a25e05d7ac9dd0d7ceab9c3c0a8d09b`の`PO approval for PRD` |
| `prd`マージ由来の検証 | PASS | PR #4、merge SHA `eeafeb4c43c59ff92fc3bfb200a2007af9b4c206` |
| production deployment simulation | PASS | run `30144224312` |
| deployment artifact | PASS | artifact ID `8615456219`、digest `sha256:ffa3f0dd23dffd48bcf439e3c3e2103fd9fbf8a12ac665f6780b1f6a438dd746` |
| artifact内容の相互一致 | PASS | repository、merge SHA、source PR #4、run IDが一致 |
| required reviewerによる待機 | 未検証 | Repository Administration設定が未適用のため、Environmentは待機せず通過しました |
| Rulesetによるマージ拒否 | 未検証 | Repository Administration設定が未適用のため、PR #4はマージ可能でした |

## CI証跡

PR #4のHEAD SHAは`03ab6f5f5a25e05d7ac9dd0d7ceab9c3c0a8d09b`です。GitHub Actions run `30144203624`では、次が成功しました。

- `Validate repository`
- `PO approval for PRD`

後者が待機せず成功したことはWorkflow経路が動作した証拠ですが、PO required reviewerが設定された証拠ではありません。required reviewerがないEnvironmentは承認待ちにならないためです。

## デプロイ証跡

PR #4を`prd`へsquash mergeした結果、merge SHAは`eeafeb4c43c59ff92fc3bfb200a2007af9b4c206`になりました。Deploy production run `30144224312`では次のjobとstepがすべて成功しました。

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

## 残る管理設定

次をrepository administrator権限で適用したあと、最終受け入れテストを実施します。

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

合格条件:

1. `prd-approval`のrequired reviewerがPO本人だけになっています。
2. required reviewer以外は［Approve and deploy］を実行できません。
3. `PO approval for PRD`がpendingの間、`prd`へマージできません。
4. PO承認後にコミットを追加すると、新しいSHAで再承認が必要になります。
5. 再承認後の`prd`マージだけがDeploy productionを起動します。
