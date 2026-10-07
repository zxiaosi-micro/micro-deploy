# keys.example · 密钥样例（入库）

真实密钥在 `deploy/conf/keys/`（gitignore，**永不入库**，E11）；本目录是**样例**：
展示 `tools/keygen` 的产出文件名/格式/kid 组织方式，供服务侧对接（jwtauth 多公钥集合、
crypto MICRO_DATA_KEYS 解析、OTA_SIGN_KEY 读取）参考与 CI 校验格式。

| 文件 | 说明 | 私钥是否入库 |
|---|---|---|
| sample_keys.json | keygen 产出的元数据（kid→文件映射）结构样例 | —（仅结构） |
| sample_jwt_public.pem | RS256 JWT 验签公钥样例（PKIX "PUBLIC KEY"） | 仅公钥 |
| sample_ota_public.pem | Ed25519 OTA 验签公钥样例（PKIX "PUBLIC KEY"） | 仅公钥 |

关键约定（v4/02 §13 / 附录 C）：

- JWT header.kid = keygen 产出（SHA-256(SPKI) 截断 16 hex）；验签方按 kid 在多公钥集合选钥，
  轮换期新旧并存（`JWT_KEYS_DIR` 目录下 keys.json 索引）。
- 数据密钥：`MICRO_DATA_KEYS=<kid>=<base64url 32B>[,<kid2>=...]`（轮换期并存），
  `MICRO_DATA_KEY_KID` 指定当前加密 kid——与 micro-common/crypto `ParseKeySpec` 一致。
- OTA：私钥 `OTA_SIGN_KEY` 环境变量注入，未签名固件拒绝入库（S6）。

重新生成真实密钥：`cd micro-server && go run ./tools/keygen`（已存在时 -force 覆盖）。
