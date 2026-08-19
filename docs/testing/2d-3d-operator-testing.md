---
title: 2D 与 3D 算子测试体系
topic: testing
projects:
  - name: OperatorAutoTest
    markers: ['OperatorAutoTest.csproj', 'Program.cs']
  - name: CY3DOpTest
    markers: ['CY3DOpTest.csproj', 'TestHarness.cs', 'Suites.cs', 'Synthetic.cs']
status: 活跃
last_updated: 2026-08-19
---

# 2D 与 3D 算子测试经验（交接版）

> 生成日期：**2026-08-19**（林工 / fuzhao.lin@nexai-tech.co）
> 用途：**换到另一台开发主机后，靠这份文档把 2D、3D 算子测试跑起来并继续开发**。
> 只讲 2D（JET2DVis 自研算子）和 3D（carvedyu PointCloud3D 双后端）两套体系。
> 板端（包裹检测/灰度仪）那套见《算子测试体系总结》第四章（那份不在本经验库），本文不重复。
> 配套文档：[DiagAgent 现场诊断助手](../agent/diagagent-field-diagnosis.md)（同批生成）。

---

## 0. 三十秒导航

| 我要做什么 | 跳到 |
|---|---|
| 新主机第一次把测试跑起来 | §2 落地清单 |
| 改了 2D 算子实现，要验有没有回归 | §3.5 |
| 改了自研模板匹配 / blob 算子 | §3.4、§3.6 |
| 改了 3D 算子或加了新后端 | §4.5 |
| 复刻 Halcon 行为踩坑对照 | §5 |
| 我的测试为什么"全绿却漏掉了 bug" | §6（最值钱的一章） |
| 现在代码停在哪、什么没合并 | §7 |

**一句话现状**：2D 模板匹配替换已完成并切换调用点；2D blob Find 系列自研完成但**停在未合并分支等审核**；3D 双后端 + 44 用例黄金对拍全绿，代码自 2026-08-06 未动。

---

## 1. 两套体系一览

| | **体系 A：2D 算子鲁棒性矩阵 + A/B 对照** | **体系 B：3D 算子黄金对拍** |
|---|---|---|
| 被测对象 | JET2DVis `ImageProcessToolkit`（8 个注册算子 + `*BySelf` 自研算子） | carvedyu `CYImageProcessToolkit\PointCloud3D`（Halcon 后端 vs `Managed\` 自研后端） |
| 工具 | `OperatorAutoTest`（「自研算子」外层仓库内） | `CY3DOpTest`（carvedyu 仓库 `tools\` 下） |
| 规模 | 8 算子 × 5 通道 × 13 ROI（单张彩图 520 用例）+ 3 个 A/B 模式 | 44 常规用例 + 3 perf + 1 条件用例，30 条带容差基线 |
| 真值来源 | 无真值（鲁棒性）／合成图解析真值／Halcon 互比 | 种子化合成点云解析真值 + `golden_halcon.txt` 黄金基线 |
| 核心判据 | **不许异常/超时/崩溃**；ROI 全在图外必须 false + error | **不许崩进程、不许 NaN/Inf**；指标在容差内 |
| 一句话 | 图×通道×ROI 扫边界，红线优先于精度 | 一套基线验任意新后端，44 用例一行不改 |

**两套体系共同的骨架**：改动前留基线 → 改动 → diff。区别只在 diff 的对象是 CSV 行、还是带容差的指标 key。

---

## 2. 新主机落地清单（按顺序做）

### 2.1 必须拷过去的东西（**不在仓库里**，git clone 拿不到）

| 内容 | 路径 | 说明 |
|---|---|---|
| 2D 测试图库 | 「自研算子测试图片」图库的 `{1,2,3}` 三个子目录 | 20/17/24 张产线 NG 图，子文件夹=产品。没有它只能跑合成图冒烟 |
| 2D 当前基线报告 | `OperatorAutoTest\_autotest_reports\abshape_real_20260723_110606\` | 模板匹配 A/B 的对比基准，丢了就没有参照 |
| blob A/B 历史报告 | `自研算子\_autotest_reports\abblob_real_20260812_*` | 8-12 blob 验收留档 |
| **外层仓库整目录** | 「自研算子」外层仓库 | ⚠ **外层仓库没有任何 git remote**，推不出去。迁移只能整目录拷（含 `.git` 和未提交的工作区改动），否则 DiagAgent 那批已验证未提交的改动直接丢 |
| 3D 点云测试数据（可选） | `--cloud` 指定的真实点云文件 | 不给就不注册 realdata 那条用例 |

### 2.2 工具链

- **必须用 VS 2022 *Preview* 版自带的 `MSBuild.exe`**（`MSBuild\Current\Bin\` 下那个）。
  **`dotnet build` 编不了 JET2DVis 主工程**（.resx 报 MSB3822/3823），必须用 VS MSBuild。算子库和 OperatorAutoTest 可以用 dotnet。
- .NET Framework 4.7.2 / 4.8 开发包，x64。
- **Halcon 授权**：A/B 对照要跑 Halcon 侧才需要。授权不可用时 A/B 会**自动降级为只验自研**（summary 里写"Halcon 不可用"）——⚠ **别把降级当通过**。
- 3D 跑 Halcon 后端需要 Halcon native dll，定位顺序：`--halcon-dir` > 环境变量 `CY3D_HALCON_DIR` > exe 目录 > 向上找 `CarvedYu\bin`。**所以跑 halcon 后端前必须先编过 HuiKe 主程序**。

### 2.3 编译顺序（2D，顺序错了跑的是旧算子）

```powershell
# 在「自研算子」外层仓库根下执行
# $msbuild = VS 2022 Preview 版的 MSBuild.exe
# 1) 先编算子库
& $msbuild `
  JET2DVis\ImageProcessToolkit\ImageProcessToolkit.csproj -p:Configuration=Debug -v:minimal -nologo
# 2) 再编测试工程
dotnet build OperatorAutoTest -c Debug
# 或者两步合一
powershell -NoProfile -ExecutionPolicy Bypass -File DevAgent\automation\build.ps1
```

> ⚠ **头号构建陷阱**：`OperatorAutoTest.csproj` 以 `HintPath + Private=false` 引用 toolkit，但运行时加载的是**自己 bin\Debug 下的副本**。改完 toolkit **必须再 build OperatorAutoTest** 刷新 dll，否则跑的是旧算子。2026-07 曾因此误判"stride=1 修复无效"。

### 2.4 编译（3D）

`tools\CY3DOpTest\CY3DOpTest.csproj` **不在任何 sln 里**，要单独 MSBuild 这个 csproj（net472/x64）。

### 2.5 仓库布局（**双仓库，必须搞清**）

```
自研算子\                              ← 外层仓库（无 remote，纯本地）
├── OperatorAutoTest\                      测试宿主
├── DiagAgent\  DevAgent\  Web\
└── JET2DVis\                              ← 独立 git 仓库（有 remote），外层已 ignore
    └── ImageProcessToolkit\               算子本体在这
```

- 改**算子实现** → 在 `JET2DVis\` 内层做 git 操作；改**测试用例/工具** → 外层。
- 内层 remote：`github.com:Stefannnn1028/JET2DVisAgent.git`（`agent` 远程）；`main` 没配 upstream。
- 项目根 `CLAUDE.md` 里有给 Agent 的硬性规则（冲突检查、禁 `git add -A`、禁 push、禁改 `Camera/`、`Common/`、主程序 UI）——迁移后照旧生效。

---

## 3. 体系 A：2D 算子自动测试

### 3.1 组成

| 件 | 位置 | 备注 |
|---|---|---|
| 测试宿主 | `OperatorAutoTest\Program.cs`（1217 行，net472/x64） | 4 种模式，见下 |
| 被测算子 | `JET2DVis\ImageProcessToolkit\ImageProcessToolkit2D.cs`（13000+ 行，`*New` 后缀=Halcon 替换目标） | |
| 自研算子 | `ImageProcessToolkit2DBySelf.cs` | **约定：自研算子统一写这里，签名尽量与 Halcon 版一致**，减少调用方替换工程量 |
| Claude 技能 | `自研算子\.claude\skills\op-autotest\`（SKILL.md + REFERENCE.md + templates） | ⚠ `templates\Program.cs` **落后于实际版本**，缺 `--ab-shape-real` / `--ab-shape-crop`，**绝不要用它覆盖现有 Program.cs** |
| 报告 | `_autotest_reports\<时间戳>\results.csv` + `summary.md` | CSV 是 UTF-8 BOM，`roi_rect` 为 `cx;cy;w;h` |

### 3.2 主矩阵模式（默认）

- **8 个注册算子**（`BuildRegistry()`，Program.cs:1090 起）：`FindCircleNew` / `MeasureLineNew` / `MeasureCircleNew` / `FindBlobExtremum` / `FindBlobMeanPoint` / `MeasureBlobMeanPoint` / `MeasureBlobExtremumPoint` / `MeanIntensity`。
- **只有 ROI 是变量**，其余参数取合理默认——**这是鲁棒性测试，不是精度测试**。
- 矩阵：产品 → 图片 → 通道（灰度 1 种；彩色 gray/color_bgr/B/G/R 共 5 种）→ **13 种 ROI**（5 inside / 6 partial / 2 outside，Angle 全 0）→ 算子。
- 五种 outcome：`EXCEPTION` / `TIMEOUT`(30s) 任何情况都算失败；outside ROI 返回 TRUE 计入**可疑**；`LOAD_ERROR` 单列。
- **退出码**：0 干净 / 1 有异常或超时 / 2 参数或目录错 / **没有退出码 = native 崩溃（最严重）**。
- **崩溃定位**：`results.csv` 每行即时 Flush，**崩溃后最后一行就是复现参数**。
- ⚠ 一个用例 TIMEOUT 会 `goto NextChannel` 跳过该通道剩余用例——**TIMEOUT 出现后覆盖率数字失真**。

```powershell
OperatorAutoTest.exe --images <图库根> --operator <名|all> --product <名|all> --max-images N --out <目录>
```
建议总是显式给 `--out`（默认落当前工作目录的 `_autotest_reports\`）。

### 3.3 冒烟（秒级，不依赖外部数据）

```powershell
OperatorAutoTest\bin\Debug\OperatorAutoTest.exe --ab-shape
```
判定：same / shift / rot(10°) / rot(45°) 应匹配且角点偏差 <2px；**rot(-10°) 不匹配是正常行为**（超出角度范围 [0,90]，两引擎都"无匹配"才对）。

### 3.4 模板匹配 A/B 三模式（改 `*BySelf` 模板匹配时用，从便宜到贵）

1. `--ab-shape` — 合成图有真值，角点偏差 <2px。加 `--scale 3.33` 模拟产线分辨率。
2. `--ab-shape-real --max-images N` — 61 张真实图双引擎互比，与基线 `abshape_real_20260723_110606` 对：**找到率 61/61、分数 avg≈0.992、角点差 max ≤0.70px、自研 39–47ms vs Halcon 43–50ms**。
   调试：`--product 2 --debug-image <子串> --render` + 环境变量 `JET_SELFMATCH_DUMP=1`（顶层候选+逐层细化轨迹+L0 角度剖面）/ `JET_SELFMATCH_EXPECT=row,col` / `JET_SELFMATCH_PROFILE=1`。标注图**绿线(Halcon) 应落在红带(自研) 中央**。
3. `--ab-shape-crop` — 复现 `ShapeModelForm` 的裁剪建模+涂抹剔除+整图匹配路径。生产调用方：`Tool\PositionTool.cs`、`Solution\UI\Template2D\ShapeModelForm.cs`。

**模板匹配替换的历史结论（2026-07-23 已完成并切调用点）**：
- 自研 `CreateShapeModelBySelf` / `FindShapeModelBySelf` / `ReleaseShapeModelBySelf` / `SetImageMat` 与 Halcon 版同签名。
- 全工程已无 Halcon 模板匹配残留（`grep '\.(Create|Find|Release)ShapeModel\('` 无命中）。
- 耗时优化到略快于 Halcon 的六项：细化逐层按"最优-0.15"裁候选／亚像素复用 L0 梯度区域／梯度区域改旋转点集外接矩形（面积减半）／细化动态剪枝（邻域 0.8×当前最优提前终止）／ROI 掩膜按顶层分辨率绘制／大区域归一化并行化。
- **真实图暴露的两个鲁棒性 bug**（合成图测不出）：①顶层扫描 stride=2 会整峰跳过精细纹理（高层金字塔峰宽可窄至 1px，产品2 曾 8/17 张匹配错位）→ 顶层改全扫 stride=1；②`RefineCandidate` 角度采样越界被丢弃而非夹取（真角度在端点 0° 时 1e-4 浮点差被过滤，产品3 全组卡 0.2°/1px）→ 越界角度夹取到 angleMin/angleMax。

### 3.5 SOP：更新已注册的 2D 算子

1. 先跑基线留档（`--operator <名>` 全量，`--out` 指明时间戳目录）。
2. 改实现。**必须保留**：`IsRectInImage` 前置守卫（`ImageProcessToolkit2D.cs:7106`，全包含语义）+ `error="轮廓超出图像"` + HObject 在 `finally` 里 Dispose。
3. 重编**两个**工程（§2.3）。
4. 再跑同样命令，**diff 两份 `results.csv` 该算子的行**：`TRUE→FALSE`、新增 `EXCEPTION`/`TIMEOUT`、`elapsed_ms` 显著上升 = 回归。

### 3.6 SOP：新增 2D 算子 / 自研化一个 Halcon 算子

- **接入测试**：只在 `BuildRegistry()` 末尾照抄一条 `OperatorEntry`（非 ROI 参数给默认，参考 `MeanIntensity` 的写法）→ 冒烟 `--max-images 2` → 全量。ROI/通道矩阵零改动自动覆盖。
  限制：委托签名只喂**一个** `CYRoiInfo`，多 ROI 算子要先扩框架。
- **自研化流程**（`workflow-replace-after-confirm`）：在 `*BySelf` 里写算子可以直接做 → 跑完自动测试**汇报** → **用户确认后才改调用点**（`PositionTool` 等）。不要自己顺手切。
- **blob 系列的 A/B 模式在未合并分支**：`--ab-blob` / `--ab-blob-real` 只存在于外层分支 `claude/req-20260812_blobself`（`1f6f8f6`→`3d66cd1`→`052a0e6`），main 上没有。要接着做 Measure 系列，先 `git switch claude/req-20260812_blobself`（内外层同名分支配对，内层 `d93fb13`→`e4ea5de`）。
- **判读注意**：双引擎**一起**失败通常是测试夹具／自动选 ROI 的问题，不是算法回归（2026-07-23 09:41 的 0/3 就是这样）。

---

## 4. 体系 B：3D 算子黄金对拍（CY3DOpTest）

> 代码自 **2026-08-06** 起未改动（2026-08-19 复核：5 个 .cs + `golden_halcon.txt` 时间戳均为 08-06），所以下面的结论现在仍然成立。

### 4.1 组成

- 工程 `tools\CY3DOpTest\`（carvedyu 仓库内）：`Program.cs`(CLI) / `TestHarness.cs`(断言·Golden·Report) / `Synthetic.cs`(合成数据) / `Suites.cs`(全部用例)。
- 基线 `tools\CY3DOpTest\golden_halcon.txt`（30 条带容差指标，**随代码进版本管理**；`bin\Debug` 下那份是历史残留，别用）。
- **双后端完全分离**：`PointCloud3D\*.cs`（Halcon）与 `PointCloud3D\Managed\*.cs`（纯 C# 自研）互不调用，入口类一行分发（如 `PointCloudFitter.cs:37`）。切换 = `CY3DBackend.Current`（环境变量 `CY3D_BACKEND=managed` 或 `--backend managed`）。`PointCloudProcessor` / `PointCloudMeasure` 已后端无关。
- 自研后端内容：`CpuPointCloud`、`ManagedFitter`（平面 PCA / 球 Kasa+GN / 圆柱主轴候选+LM）、`ManagedRegistration`（**点到面 ICP**——点到点在网格采样面上会被格点锁死、收敛停在半格距）、`ManagedCompare`（KD-tree NN）、`ManagedPointCloudIO`、`KdTree3`、`MathUtil3D`。
- 性能参考：自研 FitPlane 200k 点 ≈38ms vs Halcon 510ms（Halcon 的大头是 HTuple 逐元素构造）。

### 4.2 用例与判定

- **44 常规用例**（accuracy 22 / robust 22）+ 3 perf（`--perf` 才跑，只记指标不设阈值）+ 1 条件 realdata（给了 `--cloud` 才注册）。
  覆盖 `FitPlane` / `FitSphere` / `FitCylinder` / `VoxelDownsample` / `RemoveOutliers` / `Transform` / `ClipToBoxes` / `Icp` / `Compare` / `IO` / **`Measure`**（帮助文本和文档漏写了 Measure，实际存在，是 8-06 加 GD&T 节点时补的 4 条）。
- accuracy：种子化合成点云带解析真值。噪声模型——平面沿法向 N(0,σ)、球/圆柱径向噪声、120° 部分圆弧、余弦鼓包缺陷、三正交面 `CornerCloud`（保证 ICP 不欠约束）。
- robust：null / 点数不足 / 退化几何（共线、共面圆环、平面喂圆柱）/ NaN·Inf。三种可接受形态：精确异常类型 / `Success=false` 且 `Error` 非空 / `RunTolerant` 干净抛托管异常。**红线：不许崩进程、不许产出 NaN/Inf。**
- **两层阈值必须分清**：用例内 `CheckLess` 是**对真值的绝对精度线**；`ctx.Metric(key, v, absTol/relTol)` 是**两后端/两版本的一致性线**（声明了容差才进基线）。判定 diff ≤ absTol **或** diff ≤ relTol×|基线|。
- **种子机制**：每用例 `Random(seed ^ StableHash(FullName))`，默认 `seed=20260806`。增删/重排用例不影响其他用例的随机序列，基线不整体漂移。**用例体禁止自己 `new Random`。**
- native 崩溃定位：Runner 执行前先打印用例名并 Flush。

### 4.3 运行

```
CY3DOpTest.exe --backend halcon|managed [--op A,B] [--tags accuracy,robust] [--perf]
               [--seed n] [--repeat n] [--json f] [--dump-golden f] [--check-golden f]
               [--halcon-dir d] [--cloud f] [--list]
```
- 退出码：0 全过 / 1 有失败或超差 / 2 工具错误。
- 报告 `cy3d_report.json`：summary + 逐用例 status/ms/metrics/failures。**报告不含容差，容差只在 `Suites.cs` 里**。
- `--repeat 20` 压句柄/内存泄漏（看 WorkingSet 变化），但只保留最后一轮结果，**不适合抓间歇性失败**。

### 4.4 ⚠ 三个基线陷阱（文档没写，源码为证）

1. **`--dump-golden` 是全量覆写，不是合并**。带 `--op` / `--tags` 过滤去 dump，会把 30 条基线砍成几条，其余静默丢失（check 时"缺 key 只 Info"不报警）。**dump 基线必须全套跑、不加任何过滤。**
2. `--dump-golden` 和 `--check-golden` 同时传**不互斥**：先覆盖基线再自比 = 永远全过。别这么用。
3. **用例名一旦定下不要改**：基线 key 是 `Op/Name/Metric`，改名 = 基线孤儿且无告警。

### 4.5 SOP

**改已有 3D 算子**：动手前全量 dump 基线 → 改代码 → 快速环 `--op <域> --tags accuracy,robust`（百 ms 级）→ 全量 `--check-golden` → `--repeat 20` + `--perf` → **两个后端都跑**。只有"预期变更（新实现更准）"才改容差或重刷基线，commit 里写明原因。

**新增 3D 算子**：`Synthetic.cs` 加带解析真值的生成器（**Random 要注入，不要自己 new**）→ `Suites.cs` 加用例（accuracy 1–2 条 + robust 2–3 条 + 可选 perf）→ 关键指标声明容差 → `--list` 确认 → 全量重刷基线。输出点云**务必走 `CY3DBackend.CreateCloud`**，否则 managed 模式会串到 Halcon。

**新增后端**：实现 `ICY3DPointCloud` → 入口一行分发 → 入口同契约拦 NaN/Inf → 现成 `golden_halcon.txt` 直接对拍，**44 个用例一行不改就能验新后端**。这是这套设计最大的回报。

### 4.6 3D 覆盖缺口（接着做的话从这里挑）

- 平面度/共面度节点（`CY3DFlatnessNode` / `CY3DCoplanarityNode`）**没有用例**——`GridPlane + WithBump` 能给解析 PV 真值，补测成本很低。
- New3D 的 23 个节点**节点层**（ProtoBuf 序列化、ROI 变换、Scale/Offset）无自动化测试。8-06 新增的 5 个 GD&T 节点（Height/StepHeight/Coplanarity/DirectionAngle/Volume，ProtoInclude 3601–3605）只有算法层 4 条 Measure 用例，**节点本身仍是"编译过、待实机验证"**。
- 2D 算子在 carvedyu 内**没有**等价工具（体系 A 的 `op-autotest\SKILL.md` 是现成蓝本）。
- 旧 API `CY2DImageProcessToolkit3D.CalculateFlatness`（失败返回魔数 `-10000`）与新体系并存且无测试。
- 三角化 `PointCloudMesh` 未自研（暂无节点用）；`om3`/`dxf` 只有 Halcon 能读；`Roi3DDto` 七种类型只实现了 Box，其余**静默跳过**。
- 生产默认后端仍是 Halcon，切 `managed` 要实机验证后才能拍板。

---

## 5. 复刻 Halcon 行为的坑（照抄这一节能省几天）

### 5.1 2D blob 定点系列（2026-08-12 实战，做 Measure 系列会再遇到）

1. **ROI 框朝向**：`gen_rectangle2` 的主轴在 (列,行) 坐标下是 `(cos Phi, -sin Phi)`，调用方代入 `Phi=-rad(Angle)` 得到 `+Angle`。照抄 `IsRectInImage` 里的 `-Angle` 会**镜像反**，斜 ROI 上中心点偏到 398px。
   ⚠ **`IsRectInImage` 本身校验的就是镜像框，这是既有 bug，影响所有旋转矩形 ROI 算子。**
2. `IsSubRegion` 会先把 blob **膨胀 2px** 再测子集，不是空操作——贴 ROI 边的 blob 会被丢掉。
3. `get_region_contour` 返回**闭合**轮廓（起点在末尾重复），起点是"最上行最右点"，遍历方向与 OpenCV 相反。不复刻的话中心点有 **0.25px 固定偏差**。
4. 必须**只在 ROI 外接矩形上运算**（对应 `reduce_domain`）。整图运算慢 **64 倍**。
5. **极值点口径按林工指示改了**：不再是 Halcon 那种"角度归四象限后取图像轴极值"（粗糙近似），改为**按标注方向投影取最远点**。ROI 角度 = 标注起点→终点的 `atan2`，方向向量 `(cos Angle, sin Angle)`（y 向下）。改后斜方向下与 Halcon 必然不同 → **判据换成不变量：自研点沿标注方向的投影不该比 Halcon 近**，实测"更近 0 次、更远 13/15 次"。
6. 验收成绩留档：合成 30/30 偏差 0.000px；真实图中心点最大 0.156px；耗时 1.73~2.33 倍（门槛 3 倍）；全量回归与 main 基线逐项相同。

### 5.2 Halcon 3D（已全部固化成用例）

- **NaN/Inf 喂 `GenObjectModel3dFromPoints` 直接崩进程**，托管捕获不了（3D 相机无效点很常见）→ `HalconPointCloud.FromXyz` 加了有限值守卫抛 `ArgumentException`，**自研后端入口必须同样拦**。
- 平面参数约定 `n·x=d` vs `n·x+D=0`（D=-d）。包装层曾当后者用 → **平面不过原点时点到面/面间距偏 2d**。有 `d_abs_err` 指标盯着。
- `fit_primitives` 球/圆柱**需要点法向**（缺则先 `SurfaceNormalsObjectModel3d("mls")` 估算）+ 默认半径界会**静默拒绝大半径基元**（报 #9522）→ 显式 `min_radius=1e-6 / max_radius=1e6`。这两点没做对之前 FitSphere/FitCylinder **从未能用**。
- `register_object_model_3d_pair` 的 pose 本来就是 **model1(参考)→model2(当前)**，代码多取一次逆会导致位置修正反向。专设诊断指标 `mean_err_vs_inverse`：**它≈0 而 mean_err 大 = 方向反了**。
- 欧拉角锁定 `R = Rz·Ry·Rx`；奇异矩阵求逆返回单位阵；裁空返回原实例（用 `ReferenceEquals` 断言）；`.pcd` Halcon 读不了（known-issue 用例只记录不判失败，读成功会自愈提示）。
- 编 HuiKe 时若 `bin\Debug` 被运行中的实例锁住，只有复制阶段失败（MSB3027），代码编译其实已过，关程序重编即可。

---

## 6. 测试设计方法论：怎么不被"假绿"骗

这一章是两套体系（以及 DiagAgent 那套 LLM 回归）反复付学费换来的，**新主机上写任何新用例前先读一遍**。

1. **改动前先留基线，改动后 diff**——三套体系共同的骨架（CSV diff / golden 对拍 / 逐字文本 diff）。
2. **红线判定优先于精度判定**：不崩进程、不出 NaN/Inf、不超时，比"算得准"更基础。退化输入（null / 点数不足 / ROI 在图外 / 共线共面）必须显式测。
3. **崩溃现场要可定位**：逐行 Flush CSV、执行前打印用例名——native 崩溃托管抓不到，只能靠"最后一条输出"。
4. **种子化 + 用例名哈希**：随机数据可复现，且增删用例不漂移其他用例。
5. **两层阈值分离**：对真值的绝对精度线 ≠ 两实现间的一致性容差线。混在一起会同时失去两种保护。
6. **合成用例天然温和，缺陷只在真实图/斜方向暴露**：blob 朝向缺陷在合成图和真实图 0° 下**全绿**，只有真实图斜 ROI 才现形；模板匹配的 stride 和角度夹取两个 bug 也只有真实图抓到。**"合成图全过"永远不是结论。**
7. **凡是"方向/朝向/符号"类约定，要专门设计一正一反的判别用例**：blob 放在正确框内**必须找到** / 放在镜像框内**必须找不到**。否则测试会假绿。
8. **挑一个对被测维度不敏感的干净判据**：中心点算子与方向无关，是掩膜口径的干净判据——朝向 bug 就是靠它揪出来的。
9. **两个实现同时失败 = 先查夹具**（ROI 自动选择、测试图、配置），不是算法回归。
10. **诊断指标与判定指标分开**：`mean_err_vs_inverse`（方向反了？）、known-issue 用例（只记录 + 自愈提示）这类"不判失败但帮定位"的输出很值钱。
11. **计时分辨率要配得上算子**：亚毫秒级算子做 A/B 计时必须用微秒，ms 分辨率下 Halcon 恒显示 0，比值没法评估。
12. **判定分支只要没有对应的输入用例，回归就考不到它**（DiagAgent 那边为此专门加了"问法变体"机制）。写完一条兜底规则，回头问一句：**哪条用例会走到它？** 走不到就等于没写。
13. **改口径就要同步改判据**：极值点口径一变，与 Halcon 逐点对比就永久失效 → 换成不变量判据。别为了让老判据继续绿而放弃更好的口径。
14. **判定与采集分开，判定要能吃合成输入**（2026-08-19，NVS 插件体检实战）。凡是"采集事实 → 照事实下结论"的模块，把结论那一半写成**纯函数**（只吃一个 record，不碰文件系统/反射/全局状态）。理由是结论那一半才是会长期加规则的，而**每条规则都必须有一个能让它变红的用例**——真程序集造不出"有算法没定义"这种局面，合成一个事实 record 随手就能造。落地形状：`Violates(检查名, 期望严重级, 基线 with { 只改坏一处 })`，一行一条规则。
15. **断言要连"严重级/分类"一起查，不只查"报没报"**（同上）。一条规则从"错"悄悄退成"警"，报告里照样有这一条，但**通过与否的判定已经变了**。只查有无的断言抓不到这种退化。同理：诊断类输出要查它归到了哪一类，不只查它出现了。
16. **"我看不到"不等于"它没有"**（同上）。检查器拿不到某一维信息时（NVS 的无头入口看不到界面的面板注册表），要出一条**说明**说"这一维没查"，绝不能按缺失判失败。假红比漏检更伤：它训练人忽略整份报告。同一类还有"正常的部署形态别判成错"——单平台插件出现在另一种机器上是正常的，不是缺陷。
17. **装一个真的第三方件 = 上真机**（同上，与 [DiagAgent 经验](../agent/diagagent-field-diagnosis.md) §6.2 同源）。把示例插件从"测试夹具目录"真装进产品的 `plugins/` 目录，一次跑出 4 个夹具路径测不出的缺陷：宿主的"漏翻就红"和"号段只能落在 01xx–08xx"两条自检**把本工程的内部约定套到了第三方的码上**（装个只写英文的插件，宿主自检就红——责任指向完全错的方向）；一处 `plugin!` 把"插件已装在别处"掩成 NullReferenceException；还有一条自检的**预期本身写错了**（已装在别处时，重扫夹具报"同 ID 两目录"恰恰是正确行为）。**判据：凡是"我们自己的编号规矩/翻译责任"那类断言，都要先问一句"这条数据是我们的吗"。**
18. **guard 之后残留的判空会让编译器流分析退回**（C# 特有，但同类语言通用）。`if (x is null) return;` 之后再出现一个 `x is null ? a : b`，之后每一处 `x.Y` 都开始报 CS8602。留着的判空在 guard 之后本就是死代码，删掉即可——**别用 `!` 压警告**，那正是上面那个 NRE 的来源。
19. **综合判断类的规则要清点它看了几个信息源**（2026-08-19 又栽一次；与第 5 条、[DiagAgent 经验](../agent/diagagent-field-diagnosis.md) §4.6 同源）。NVS 那条"界面名字必须在词表里"的检查第一版只看了 `[ZhStrings]` 补充块、漏了主词表，于是把「目标极性」「阈值」这些**明明存在**的控件报成不存在——12 条里 4 条是假红，指的方向还完全相反。**同一个漏源当时还在另一处**：内嵌字体那条"界面文案每个字都被覆盖"只查了 307 条词条，补上主表后是 477 条（仍全过，但那才算真验过）。**判据：写完一条"综合"判定，把它读到的来源逐个数出来，问一句"这一类数据还有别的地方存吗"。**
20. **能变成断言的经验，就不该只留在文档里**（2026-08-19）。"界面指导必须照源码核实"（[DiagAgent 经验](../agent/diagagent-field-diagnosis.md) §4.17）原本只能靠人自觉。NVS 把它机械化成一条自检：凡错误码的建议里用 `「」` 引的名字，必须能在中文词表里逐字找到（允许"名字 + 括号后缀"，因为屏幕上写的是「旋转搜索范围(±度，0=关)」）；行文强调用的 `「」` 列一份白名单，**只许缩短**。负向验证直接用那个项目栽过的原话——塞进「重新连接相机」，自检当场红。
21. **别用 `!` / `as` 压掉"可能为空"，那正是下一个 NRE 的入口**（2026-08-19，与第 18 条同类）。NVS 的插件自检里有一处 `plugin!.Directory`，把"这个插件已经装在别处了"这种**正常局面**掩成 NullReferenceException，堆栈指向自检文件而不是原因，症状是"我装了示例插件，你的自检就崩了"。**判据：写下 `!` 之前先问"它为什么可能是 null"——答得出来就该处理那一支，答不出来说明前面的 guard 写错了。**

---

## 7. 当前状态与欠账（2026-08-19 复核）

### 7.1 分支/提交状态

| 仓库 | 位置 | 状态 |
|---|---|---|
| 外层 `自研算子` | `main` = `c1c612e` | **无 remote**，纯本地 8+ 提交。工作区有 DiagAgent 的 6 项改动未提交（详见配套文档） |
| 外层分支 | `claude/req-20260812_blobself` = `052a0e6` | **blob A/B 测试模式 `--ab-blob` / `--ab-blob-real` 只在这里**，未合并 |
| 外层分支 | `claude/req-20260810_171915`、`claude/diagagent-*`、`claude/req-20260814_diagregress` | 其他交付/历史分支 |
| 内层 `JET2DVis` | `main` = `9f2e64a` | 干净。remote `agent` 存在但 main 未配 upstream，**未 push** |
| 内层分支 | `claude/req-20260812_blobself` = `e4ea5de` | blob Find 系列自研实现，**未合并、待审核** |
| carvedyu | `main` = `ce3ec89` | 3D 相关文件自 08-06 未动 |

⚠ **carvedyu 有两个分叉副本，别在错的那份上改 3D。** 认副本看内容，不看位置：活跃主线那份有 `tools\CY3DOpTest\`、`docs\adr\`、`New3D\`；另一份停在 2026-05，只有 `docs\ai-chat` 评测集。

### 7.2 待办清单

**2D**
1. blob Find 系列**待林工审核**（报告：`DevAgent\requests\review\draft-20260810-自研blob算子替换halcon-报告.md`）；审核通过后合并两个 `req-20260812_blobself` 分支。
2. Measure 系列两个（`MeasureBlobMeanPoint` / `MeasureBlobExtremumPoint`）另提需求，坑同 §5.1。
3. blob 调用点**未切换**（按"确认后才切"的流程）；切之前要复核斜方向下的判定阈值——自研结果会变。
4. `IsRectInImage` 的镜像框既有 bug 未修（影响所有旋转矩形 ROI 算子），修它要重跑全量矩阵。
5. 下一个替换目标：`PositionTool` 点线模式（`FindCoordinateLine` / `FindPoint`），它依赖的 `MatToHObject` 通道（`PositionTool.cs:517/1317`）为此保留。
6. `op-autotest` 技能的 `templates\Program.cs` 需要同步到实际版本（现在是陷阱）。

**3D**
7. 补平面度/共面度用例（成本低、缺口明显）。
8. 5 个 GD&T 节点实机验证；节点层（ProtoBuf/ROI 变换/Scale）自动化测试仍是空白。
9. 生产切 `managed` 后端要实机验证后拍板。
10. 与 AiVision（94 个 3D 算子 vs 本项目 17 个）的差距清单，按优先级：深度图⇄点云转换（打通真机的桥）＞真 3D 相机→New3D 管线断链（Gocator/盛相只出 Mat 深度图，`CY3DInputModule` 只读本地文件）＞Profile 截面轮廓家族(11)＞3D 探针/边缘/斑点/PPF 匹配、手眼标定、多云拼接。

---

## 8. 快速索引：我要改 X，跑什么

| 场景 | 命令 |
|---|---|
| 改 2D 算子实现 | 改前后各跑 `--operator <名>`，diff `results.csv` |
| 新增 2D 算子 | `BuildRegistry()` 加一条 → `--max-images 2` 冒烟 → 全量（§3.6） |
| 改自研模板匹配 | `--ab-shape` → `--ab-shape --scale 3.33` → `--ab-shape-real`（比基线 110606）→ `--ab-shape-crop` |
| 改自研 blob | 切到 `claude/req-20260812_blobself`，`--ab-blob` → `--ab-blob-real`（§3.6） |
| 改 3D 算子 | 全量 dump 基线 → 改 → `--op <域> --tags accuracy,robust` 快速环 → 全量 `--check-golden` **双后端** → `--repeat 20 --perf` |
| 新增 3D 算子/后端 | §4.5 |
| 声称"重构不改行为" | 3D：golden 对拍零超差；2D：同参数 `results.csv` 逐行相同 |
| 只想确认环境没坏 | `--ab-shape`（秒级，不依赖测试图库） |

---

## 附：术语与路径速查

| 名字 | 是什么 |
|---|---|
| `*New` 后缀算子 | `ImageProcessToolkit2D.cs` 里的 Halcon 实现，**替换目标** |
| `*BySelf` 后缀算子 | `ImageProcessToolkit2DBySelf.cs` 里的自研实现，**约定统一写这里** |
| `CY3DBackend.Current` | 3D 后端开关，`CY3D_BACKEND=managed` 或 `--backend managed` |
| `golden_halcon.txt` | 3D 黄金基线，30 条带容差指标，随代码进版本管理 |
| `abshape_real_20260723_110606` | 2D 模板匹配当前基线报告目录 |
| 测试图库 | 「自研算子测试图片」`{1,2,3}` 三个子目录（不在仓库） |
| VS MSBuild | VS 2022 *Preview* 版自带的 `MSBuild.exe`（主工程只能用它） |
