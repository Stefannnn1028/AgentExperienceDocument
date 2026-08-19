---
name: sync-experience
description: 把当前项目的开发经验增量同步到 AgentExperienceDocument 经验库仓库（github.com/Stefannnn1028/AgentExperienceDocument），更新对应主题文档、README 索引，并 commit & push。Use when 用户在某个项目下说"同步经验"、"总结这次开发经验"、"更新经验库"，或 invokes /sync-experience。
---

# 同步项目经验到经验库

把**当前项目**这段时间的开发经验，增量写进经验库仓库 `C:\LFZProject\AgentExperienceDocument`，然后推送。

> 与 `/update-experience` 的区别：那个维护 E 盘的两份**全局**总结文档；这个维护 **git 经验库**里按项目分文件的文档。两者互不干扰。

## 前置

经验库本地路径：`C:\LFZProject\AgentExperienceDocument`（下称 REPO）。
不存在就先 `git clone git@github.com:Stefannnn1028/AgentExperienceDocument.git C:\LFZProject\AgentExperienceDocument`。

**开工第一件事**：`git -C REPO pull --rebase`。远端可能被另一台主机改过。

## Workflow

1. **定位当前项目**。用户没指定就取当前工作目录所在的项目根（含 `.git`／`.sln`／`package.json` 的最近上层目录）。

2. **找到对应文档**。读 REPO 下所有 `docs/**/*.md` 的 front matter，按 `projects` 逐条匹配当前项目，命中任一条即算命中该文档：
   1. `REPO\paths.local.json` 里若已填过该项目所属的变量，直接用它拼出的路径比对；
   2. 否则比对**目录名** `dir_name`；
   3. 目录名也对不上时，用 `markers`（特征文件，全部存在才算数）确认。
   命中一份 → 增量更新它；命中多份 → 问用户；**没命中** → 走「新增文档」流程（见下）。

   > `legacy_path` 只是旧主机上的历史值，**仅供追溯，不参与匹配**。

3. **对齐本机路径**。文档正文用 `%VAR%` 写路径（见每份文档的「路径约定」一节）。
   若 `paths.local.json` 里该变量为空或文件不存在，就用当前项目的实际位置反推填上，并告诉用户填了什么。
   这个文件**不进 git**，每台主机各自维护。

4. **扫描变化**。以该文档 front matter 的 `last_updated` 为起点：
   ```
   powershell -ExecutionPolicy Bypass -File <SKILL_DIR>\scripts\scan-project.ps1 -Path <项目路径> -Since <last_updated>
   ```
   脚本给出：该区间的 git log、当前未提交改动、变化的源码/文档/脚本文件清单。
   若脚本报 `NO_CHANGES` 且工作区干净 → 告诉用户"无变化"，**不做任何提交**，结束。

5. **调研变化**。派 Explore 代理读变化的文件（并行，按模块分组），要求它们只报告**有经验价值**的东西：
   - 新做的功能／新的架构决策，以及**为什么这么选**
   - 新踩的坑：症状 + 根因 + 解法（症状要写成可被 grep 的原话）
   - 回归体系变化：新用例、新基线、通过率与耗时（**带实测日期**）
   - 状态变化：什么合并了、什么还挂在分支上、新的已知缺陷
   明确要求跳过 `bin/obj/node_modules/packages/.vs/x64/Release/Debug/models/图片` 等目录。
   无路径佐证的结论不要采信，先核实。

6. **增量更新文档**，严格遵守 `REPO\CONVENTIONS.md` §3：
   - 只 Edit 真正变化的章节，其余逐字保留，**不要整篇重写**
   - 新证据与已有结论矛盾 → **先问用户**，确认后改并注明「（YYYY-MM-DD 修订：原结论 X，因 Y 改为 Z）」
   - 「当前状态与欠账」一节每次都重写 —— 它最容易陈旧且危害最大
   - 不确定的写成 `> ⚠ 待确认：...`，别猜
   - 刷新 front matter 的 `last_updated` 为今天

7. **同步 README 索引**：更新该文档所在主题表格里的「一句话」「状态」「更新」列。新增文档则加一行；开了新主题则加一节并补「主题分类」表。

8. **提交并推送**：
   ```
   git -C REPO add -A
   git -C REPO commit -m "docs(<topic>/<slug>): <一句话>" -m "- <变更点>"
   git -C REPO push
   ```
   提交信息格式见 CONVENTIONS.md §4。push 失败（多半是远端有新提交）→ `git pull --rebase` 后重试一次，仍失败就报告用户，不要 force。

9. **汇报**：说清楚扫了哪些文件、改了哪几节、提交的 commit hash。无变化也要明说。

## 新增文档流程

当前项目在经验库里还没有文档时：

1. 按 CONVENTIONS.md §1 的骨架起草，主题从 `agent / testing / algorithms / engineering` 里选；都不合适才开新主题目录（要跟用户确认）。
2. 文件名用小写英文 slug（`diagagent-field-diagnosis.md` 这种），标题用中文写在 front matter 和 H1 里。
3. **初稿必须给用户过目再提交** —— 新文档是从零编的，比增量更新更容易写错。

## 约束

- **增量优先**。已有结论不会被无声覆盖，冲突一律先问。
- **绝不 force push**，绝不 `reset --hard` 经验库。
- 提交前 `git -C REPO status` 确认改动范围符合预期，不要把无关文件带进去。
- **正文里不许出现带盘符的绝对路径**（`legacy_path` 除外）。新写的路径一律用 `%VAR%`；
  需要新变量就加进该文档 front matter 的 `path_vars` 和「路径约定」表，并同步 `paths.local.json.example`。
- 无头/定时模式下不向用户提问：此时**跳过**所有需要提问的分支（结论冲突、新增文档、多文档命中），把它们列进汇报里留给人处理。
