# 阶段二部署 · K3s + ArgoCD GitOps（S11-04，ADR-06/02 §15.3）

> 阶段一（compose，ECS×2）稳定运行且节点数 ≥3 后启动阶段二；节点 >10 再升完整 K8s（ADR-06 重新评估条件）。

## 拓扑

| 节点组 | 负载 |
|---|---|
| K3s ×3（无状态） | 17 个业务服务（replicas=2）+ APISIX |
| obs 节点（可观测） | Prometheus/Grafana/Loki/Promtail/Jaeger/Alertmanager + TDengine（local-path）+ Kafka + EMQX |
| 托管 | MySQL/Redis/OSS 云托管（同阶段一） |

## 清单生成（契约先行同款纪律）

```bash
# 1) goctl kube 生成基线（在服务目录内，--style go_zero）
cd micro-server/services/order
goctl kube deploy -name order -image ghcr.io/zxiaosi-micro/micro-order:<sha> -port 8090 -namespace micro -o deploy.yaml
# 2) 模板化：overlay 到 deploy/k8s/overlays/<svc>.yaml（replicas/资源限额/探针/env 注入由 Kustomize 管理）
# 3) 生成物不入库手改——deploy/k8s/overlays 才是正本
```

## GitOps（app-of-apps）

```bash
kubectl apply -f argocd/app-of-apps.yaml      # 根应用
# 子应用：argocd/micro-services-app.yaml（ApplicationSet，按 services 列表逐服务生成）
# 同步策略：automated.selfHeal=true（漂移即拉回）；staging 自动、prod 手动 Sync（生产窗口）
```

## 网络隔离

- `base/networkpolicy-default-deny.yaml`：micro 命名空间默认全拒；
- 按需放行：APISIX→BFF、BFF→RPC、全部→etcd/Redis/Kafka、iotingest→EMQX/Kafka/TDengine；
- ingress 只暴露 APISIX 80/443。

## 发布演练 5 项（阶段二验收门槛，全部可重复执行）

| # | 演练 | 通过标准 |
|---|---|---|
| 1 | 滚动发布零中断 | `kubectl rollout status` 全绿；期间 pentest/p5smoke 抽查零 5xx |
| 2 | 回滚 | `IMAGE_TAG` 回退上一 sha 一键完成；回滚后 drill -case station 通过 |
| 3 | 数据库前向兼容 | 新版本先加列部署→旧代码跑通→再删列（两阶段纪律 02 §15.4） |
| 4 | 配置灰度推送 | configpush -diff 一致 → 改正本 → push → listener 秒级 reload（configpush -demo） |
| 5 | 单实例故障切换 | `kubectl delete pod`（replicas=2 下）→ 交易链路不受影响（NFR-AVL-004） |

## 与阶段一的切换纪律

- 双跑观察 ≥1 周（K3s 集群消费同一云 MySQL，业务量先切 5%——复用 APISIX traffic-split 通道）；
- 切换窗口全量后阶段一 compose 保留一个发布周期作为回退线，之后下线。
