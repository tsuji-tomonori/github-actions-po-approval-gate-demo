# GitHub Actions PO approval gate demo

Product Owner（PO）が承認したPull Requestだけを`prd`へマージ可能にし、`prd`へのマージ後だけ本番デプロイWorkflowを起動する公開検証用リポジトリです。本番配信処理は安全のためJSON artifactを生成するsimulationです。

## 仕組み

1. `prd`向けPull Requestを作成します。
2. `PRD PO Approval`がPull Requestの最新HEAD SHAへ`PO approval for PRD` Checkを作成します。
3. `prd-approval` Environmentのrequired reviewerだけに［Approve and deploy］が表示されます。
4. PO承認後もHEAD SHAを再確認し、承認中にコミットが追加されていれば失敗させます。
5. `prd` Rulesetが`PO approval for PRD`、`Validate branch direction`、`Validate repository`を必須Checkにするため、承認前はマージできません。
6. `prd`へのマージで`Deploy production`が起動します。
7. デプロイ前に、対象コミットが`prd`向けのmerged Pull Request由来であることを確認します。

## ブランチモデル

`main`を正規のソースブランチ、`prd`をデプロイ済みスナップショットを保持する到達先として扱います。

```text
feature/* ──> main ──> prd ──> Deploy production
                  PO approval required
```

許可する方向は次のとおりです。

- `feature/*`、`fix/*`、`hotfix/*`から`main`
- `main`または`main`から作成したrelease branchから`prd`

`prd`から`main`や他のブランチへ戻すPull Requestは禁止します。`prd`上で判明した修正は、`main`から修正ブランチを作って`main`へ反映し、その後、新しいPull Requestで`prd`へ配信します。

`.github/workflows/branch-policy.yml`は信頼済みbase branch上の`pull_request_target`として動き、Pull Requestのコードをcheckoutせずに`prd`をheadとする逆方向PRを失敗させます。`pull_request_target`自身のjob結果ではなく、Checks APIでPull Requestの正確なHEAD SHAへ`Validate branch direction`を作成するため、Rulesetが最新revisionを確実に判定できます。拒否時は理由をPull Requestへコメントします。

## 一度だけ行うRepository Administration設定

接続済みのGitHub AppからEnvironmentとRulesetの管理APIを操作できない場合は、repository administratorとして認証したGitHub CLIから次を実行します。

```bash
gh auth login
bash scripts/configure-repository.sh \
  tsuji-tomonori \
  github-actions-po-approval-gate-demo \
  tsuji-tomonori

bash scripts/verify-repository.sh \
  tsuji-tomonori \
  github-actions-po-approval-gate-demo \
  tsuji-tomonori
```

個人アカウントの単独検証では`PREVENT_SELF_REVIEW=false`が既定です。複数のPOを持つOrganizationで運用する場合は、PO Team対応へ変更したうえで`PREVENT_SELF_REVIEW=true`を使用します。

設定スクリプトは次を冪等に適用します。

- `prd-approval` Environmentのrequired reviewerをPOだけに限定
- `prd-approval`と`production`で管理者bypassを無効化
- `prd-approval`は信頼済み実行refの`main`だけを許可
- `production`は`prd`だけを許可
- `prd`はPull Request経由、`PO approval for PRD`、`Validate branch direction`、`Validate repository`を必須化
- `main`はPull Request経由、`Validate branch direction`、`Validate repository`を必須化
- 両Rulesetのbypass actorを空に設定

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
  - `Validate branch direction`
  - `Validate repository`
- Require branches to be up to date
- Require conversation resolution
- Block force pushes and deletion
- Bypass actor: なし

## セキュリティ上の要点

`pull_request_target`は強い権限を持つため、承認Workflowとbranch policy WorkflowではPull Request由来コードをcheckout・install・実行しません。承認対象は常にPull Requestの最新HEAD SHAへ固定します。デプロイWorkflowは`prd`へのpushだけで起動し、さらにmerged Pull Request由来であることをAPIで検証します。

## 動作確認

```bash
bash scripts/validate.sh
```

GitHub上の受け入れテスト:

1. feature branchから`prd`向けPRを作成します。
2. PO承認前に`PO approval for PRD`がpendingで、Mergeボタンが無効であることを確認します。
3. POが［Review deployments］から承認します。
4. Check成功後にコミットを追加し、再びpendingへ戻ることを確認します。
5. 新しいSHAを再承認して`prd`へマージします。
6. `Deploy production`が成功し、`production-deployment-<SHA>` artifactのSHAとPR番号を確認します。
7. `prd`から`main`へのPRを作成し、`Validate branch direction`が失敗することを確認します。

## 現在の検証状況

- Repository公開・source投入: PASS
- `Validate repository`: PASS
- 最新HEAD SHAへPO Checkを作成し、SHA変更後に新しいCheckを作る経路: PASS
- `prd`マージ後のprovenance検証、模擬デプロイ、artifact生成: PASS
- PR #4 / merge SHA `eeafeb4c43c59ff92fc3bfb200a2007af9b4c206` / workflow run `30144224312`の相互一致: PASS
- required reviewerによる承認待ちとRulesetによるマージブロック: Repository Administration設定の適用後に最終確認

個人アカウントの公開デモではPO Teamを作れないため、required reviewerにはPO役の個人ユーザーを指定します。実運用ではOrganization Teamを用い、Workflow管理者とPOを分離してください。
