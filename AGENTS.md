# 给 AI agent 的 goalkeeper 接入指引

goalkeeper = 给**没有原生 goal mode** 的 coding agent 补一个 `/goal`,而且是**跑真命令看退出码**的硬判定(治"agent 自报做完了"的假绿)。你在帮用户接入,照下面做。

## 0. 先判断该不该装

- 用户用 **Claude Code / Codex**:多数情况**劝他用原生 `/goal`**(内建、够用)。只有他明确要"退出码硬把关、别信模型自报"时,才装 goalkeeper。
- 用户用 **opencode / pi**:这是 goalkeeper 主场,装。
- **hermes / openclaw / 任意 headless CLI**:装 goalkeeper 的 wrapper 档。
- Kiro / ZCode:装不了(Kiro 的 Stop hook 不能 block;ZCode 无 CLI),别硬装。

## 1. 跑安装器

在用户项目根目录:
```bash
GOALKEEPER_PICK=all GOALKEEPER_TARGET="$PWD" bash <goalkeeper仓库>/install.sh
```
它会:检测本机 agent、装适配、**自动从项目推断 `DONE_CMD` 写进 `.goalkeeper/goal.sh`**(package.json→npm/pnpm test、pyproject→pytest、Cargo→cargo test、Makefile→make…)。

## 2. 用 /goal(opencode / pi 主路径)

在 opencode / pi 里:
```
/goal 把登录做完,直到测试通过
```
目标写一句自然语言,完成条件 install 已推断好(或 `/goal` 触发时再推断)。**不用手写 `DONE_CMD`。**

推断不准时才手动:编辑 `.goalkeeper/goal.sh` 的 `DONE_CMD`(兜底,非主路径)。

## 3. 各平台(install 已自动写,你确认即可)

| 平台 | 怎么用 | 位置 / 状态 |
|---|---|---|
| **opencode** | `/goal <一句话>` 命令 | `.opencode/plugins/goalkeeper.js`(🧪 基于 3 份真源码,未真机端到端) |
| **pi** | `/goal`,或 install 预设 + `agent_end` 续轮 | `.pi/extensions/goalkeeper.ts`(🧪,命令 API 待真机核对) |
| hermes / openclaw | `.goalkeeper/goalkeeper-run.sh "任务"` | 设 `goal.sh` 的 `AGENT_CMD` |
| Claude Code | 劝用原生 `/goal`;非要用 goalkeeper 则 `.claude/settings.json` 的 `hooks.Stop` | ✅ 唯一端到端验证过 |
| Codex / Kimi | 用各自原生 goal | — |
| Kiro / ZCode | 不支持 | — |

## 4. 自检
```bash
echo '{}' | .goalkeeper/check-goal.sh
```
`DONE_CMD` 没过 → 输出 `{"decision":"block","reason":...}`;通过 → 无输出、退出码 0。两种都对 = 接好了。

## 心智模型

判定真相源 `.goalkeeper/check-goal.sh`:跑 `DONE_CMD` 看退出码(**硬判定,不信模型自报**)+ `MAX_TURNS` / `MAX_SECONDS` 刹车。这是 goalkeeper 和那些"让 agent 自报完成"的 goal 项目(watzon / prevalentWare / willytop8 / Claude Code 官方 /goal)唯一的区别 —— 也是它存在的全部理由。
