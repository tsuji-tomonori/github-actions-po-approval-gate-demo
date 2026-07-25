# Security

このリポジトリは承認ゲートの公開デモです。実クラウドへのデプロイは行いません。

- `pull_request_target` WorkflowはPull Request由来コードを実行しません。
- `prd-approval`にはSecretを登録しません。
- 本番認証情報は`production` Environmentへ限定します。
- `prd`と`main`のRulesetはbypass actorなしで保護してください。
- 実運用ではPO TeamとWorkflow管理Teamを分離してください。
