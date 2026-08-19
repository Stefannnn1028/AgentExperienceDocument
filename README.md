# AgentExperienceDocument

林工（fuzhao.lin@nexai-tech.co）的**软件项目开发经验库**。

每份文档回答同一个问题：**换一台主机、隔三个月回来，靠这份文档能不能把项目跑起来并接着往下做。**
不是流水账，不是 API 文档 —— 是踩过的坑、定过的结论、别再重新调研的东西。

---

## 索引

### 🤖 agent —— Agent 与大模型应用

| 文档 | 一句话 | 关联项目 | 状态 | 更新 |
|---|---|---|---|---|
| [DiagAgent 现场诊断助手](docs/agent/diagagent-field-diagnosis.md) | 本地小模型 + 只读工具层，让现场调试员自助排障；15/15 场景零"自信的错误结论" | `E:\Project\嘉立讯标准软件\自研算子\DiagAgent` | 活跃 | 2026-08-19 |

### 🧪 testing —— 测试体系与质量保障

| 文档 | 一句话 | 关联项目 | 状态 | 更新 |
|---|---|---|---|---|
| [2D 与 3D 算子测试体系](docs/testing/2d-3d-operator-testing.md) | 2D 鲁棒性矩阵（520 用例）+ 3D 黄金对拍（44 用例）；含"全绿却漏 bug"的方法论 | `OperatorAutoTest`、`CY3DOpTest` | 活跃 | 2026-08-19 |

---

## 主题分类

新文档归到已有主题；确实放不进去再开新主题目录，并在本 README 加一节。

| 目录 | 收什么 |
|---|---|
| `docs/agent/` | Agent、LLM 应用、提示词与工具层设计、模型选型与部署 |
| `docs/testing/` | 测试体系、回归基线、对拍与黄金数据、质量红线 |
| `docs/algorithms/` | 算子与算法实现、Halcon 复刻、精度与性能调优 |
| `docs/engineering/` | 构建、部署、环境、跨主机迁移、工程实践 |

---

## 怎么维护

在**任意项目目录**下对 Claude Code 说 `/update-experience`，它会：

1. 读取本仓库 `docs/` 下所有文档的 front matter，找出与当前项目关联的那份；
2. 扫描该项目自 `last_updated` 以来的变化（git log、未提交改动、新增测试与回归结果）；
3. 增量更新对应文档，**只改变了的章节**，并刷新 `last_updated`；
4. 同步本 README 索引，然后 commit & push。

规则见 [CONVENTIONS.md](CONVENTIONS.md)。所有写入都是增量的 —— 已有结论不会被无声覆盖，冲突会先问你。
