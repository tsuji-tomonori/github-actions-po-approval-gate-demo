# GitHub Actions PO approval gate demo

Product Owner（PO）が承認したPull Requestだけを`prd`へマージ可能にし、`prd`へのマージ後だけ本番デプロイWorkflowを起動する公開検証用リポジトリです。本番配信処理は安全のためJSON artifactを生成するsimulationです。

## 仕組み

1. `prd`向けPull Requestを作成します。
2. `PRD PO Approval`がPull Requestの最新HEAD SHAへ`PO approval for PRD` Checkを作成します。
3. `prd-approval` Environmentのrequired reviewerだけに［Approve and deploy］が表示されます。
4. PO承認後もHEAD SHAを再確認し、承認中にコミットが追加されていれば失敗させます。
5. `prd` Rulesetが`PO approval for PRD`と`Validate repository`を必須Checkにするため、承認前はマージできません。
6. `prd`へのマージで`Deploy production`が起動します。
7. デプロイ前に、対象コミットが`prd`向けのmerged Pull Request由来であることを確認します。

## 必須のRepository設定

### Environment `prd-approval`

- Required reviewers: PO本人、またはOrganizationのPO Teamだけ
- Prevent self-review: 複数POで運用する場合はON
- Allow administrators to bypass configured protection rules: OFF
- Deployment branches: `main`のみ（`pull_request_target`の実行元はdefault branchです）
- Secrets: 登録しません

### Environment `production`

- Required reviewers: なし（PO承認を二重化しないため）
- Allow administrators to bypass configured protection rules: OFF
- Deployment branches: `prd`のみ
- 本番SecretまたはOIDC設定はここだけへ登録します

### Ruleset `Protect prd with PO approval`

対象: `refs/heads/prd`

- Require a pull request before merging
- Required status checks:
  - `PO approval for PRD`
  - `Validate repository`
- Require branches to be up to date
- Require conversation resolution
- Block force pushes and deletion
- Bypass actor: なし

## セキュリティ上の要点

`pull_request_target`は強い権限を持つため、承認WorkflowではPull Request由来コードをcheckout・install・実行しません。承認対象は常にPull Requestの最新HEAD SHAへ固定します。デプロイWorkflowは`prd`へのpushだけで起動し、さらにmerged Pull Request由来であることをAPIで検証します。

## 動作確認

```bash
./scripts/validate.sh
```

GitHub上の受け入れテスト:

1. feature branchから`prd`向けPRを作成します。
2. PO承認前に`PO approval for PRD`がpendingで、Mergeボタンが無効であることを確認します。
3. POが［Review deployments］から承認します。
4. Check成功後にコミットを追加し、再びpendingへ戻ることを確認します。
5. 新しいSHAを再承認して`prd`へマージします。
6. `Deploy production`が成功し、`production-deployment-<SHA>` artifactのSHAとPR番号を確認します。

個人アカウントの公開デモではPO Teamを作れないため、required reviewerにはPO役の個人ユーザーを指定します。実運用ではOrganization Teamを用い、Workflow管理者とPOを分離してください。
