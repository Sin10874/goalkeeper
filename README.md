# goalkeeper

[![test](https://github.com/Sin10874/goalkeeper/actions/workflows/test.yml/badge.svg)](https://github.com/Sin10874/goalkeeper/actions/workflows/test.yml)

> 让任何 coding agent「不达目的不停手」。
> 它每次想停下,先跑一遍你定的完成条件命令;没过就拦回去继续干,直到真达成或撞刹车。

AI agent 最常见的失败:测试还红着、活没干完,它说一句"我觉得做完了"就停了。
goalkeeper 把"做完没"从**模型的自我感觉**,换成一条**能跑出 0/1 的命令**(`npm test` 的退出码)。没过,它别想停。

强制力在 harness 层(钩住 agent 的停止事件),不在 prompt 里求它"别停",所以真有效。

---

## 装

```bash
git clone https://github.com/Sin10874/goalkeeper.git
cd 你的项目
bash ~/goalkeeper/install.sh
```

安装器做三件事:

1. **检测**本机装了哪些 coding agent(Claude Code / Kimi / Kiro / opencode / pi / openclaw / hermes / ZCode)
2. 让你**选**哪些平台生效(空格分隔序号,或 `all`)
3. 给选中的**接入** goal mode —— 能自动写配置的自动写,不能被动钩的给一键 wrapper

非交互装法(给脚本 / AI 用):

```bash
GOALKEEPER_PICK=all GOALKEEPER_TARGET=/你的项目 bash ~/goalkeeper/install.sh
```

## 装完怎么用

只剩一步 —— 编辑 `.goalkeeper/goal.sh`:

```bash
GOAL="把登录功能做完并通过测试"
DONE_CMD="npm test"      # 完成条件,退出码 0 = 达成。换成你的: pnpm test / pytest -q / make check
MAX_TURNS=30             # 刹车1: 最多自动续多少轮
MAX_SECONDS=0            # 刹车2: 最多跑多少秒(0=不限);长任务建议设,如 7200=2 小时
```

然后**正常启动你的 agent 干活**。它每次想停,goalkeeper 跑一次 `DONE_CMD`:没过 → 拦回去喂"继续修",过了或撞预算(轮数 / 时间)→ 放行,并把停因记进 `.goalkeeper/.status`(`complete` / `time_limited` / `turns_limited`)。

## 支持哪些 agent

诚实标注验证程度 —— **别把"适配代码写了"当成"验证过"**:

| 平台 | 档 | 接入位置 | 验证状态 |
|---|---|---|---|
| **Claude Code** | stdout-JSON hook | `.claude/settings.json` | ✅ **端到端真验证**(`claude -p` 跑过:拦回续轮 + 刹车全过) |
| Kimi Code | stdout-JSON hook | **全局** `~/.kimi/config.toml`(见下) | ⚙️ 判定逻辑同 CC,但 Kimi CLI 未端到端实测 |
| Kiro | ✗ 不支持 | — | **Kiro 的 Stop hook 是 observe-only、不能 block**,做不了 goal mode(只有 PreToolUse 等能拦);有 headless 可走 wrapper 档 |
| opencode | 事件插件 | `.opencode/plugins/goalkeeper.js` | 🧪 **实验性**:续轮 API 从 SDK 推断,**未在真 opencode 验证** |
| pi | 事件插件 | `.pi/extensions/goalkeeper.ts` | 🧪 **实验性**:`sendUserMessage` 同上,**未在真 pi 验证** |
| openclaw / hermes | wrapper | `goalkeeper-run.sh` | ⚙️ wrapper 逻辑实测(mock agent);真 agent 未端到端 |
| ZCode | — | (GUI,无 CLI) | 用它自带 `/goal`,或走 Claude Code 路线 |

> 图例:✅ 在真 agent 上端到端跑通 · ⚙️ 判定核心实测、但未在该 agent 端到端 · 🧪 适配代码已写、关键 API 未验证。
>
> **目前只有 Claude Code 是 ✅。** 其余欢迎你在自己的 agent 上验证后提 PR 升级标记 —— 怎么验见 [TESTING.md](TESTING.md)。

**两个已知问题(诚实摆出来):**
- **Kimi 只读全局 `~/.kimi/config.toml`**,且 `--config-file` 是替换不合并 —— install 装的项目级 `.kimi/config.toml` 它不读。用 Kimi 需手动把 hook 段加到全局 config(和你的 model 配置放一起)。install 会打印提示。
- **ZCode** 是桌面 GUI,接不进外部 hook:用它自带 `/goal`,或改 `ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic` 走 Claude Code 复用接入。

## 原理:一个判定核心 + 三档适配

所有平台共用同一个判定真相源 `.goalkeeper/check-goal.sh`:跑 `DONE_CMD` 看退出码 + `MAX_TURNS`(轮数) / `MAX_SECONDS`(时间)双刹车。各平台只是**用不同方式把它钩进"agent 想停"那一刻**:

- **档 1 · 原生 Stop 钩子**(Claude Code / Kimi):agent 的停止钩子直接调 `check-goal.sh`,读它返回的 `{"decision":"block","reason":...}` 决定拦不拦。配置载体不同(JSON / TOML),脚本同一个。(Kiro 的 Stop hook 是 observe-only、不能 block,做不了这件事 —— 见上表。)
- **档 2 · 事件插件**(opencode / pi):插件挂 `session.idle` / `agent_end` 事件,`spawn` 一次 `check-goal.sh` 判定,没达成就用各家续轮 API(`client.session.prompt()` / `pi.sendMessage(.., {triggerTurn:true, deliverAs:"followUp"})`)把"继续修"投回去。
- **档 3 · 通用 wrapper**(hermes / openclaw / 任意 headless CLI):它们没有"强制续跑"的钩子,改用 `.goalkeeper/goalkeeper-run.sh "任务"` 在**进程外**包一个循环:调 agent 跑一轮 → 跑 `DONE_CMD` → 没过把失败输出当下一轮 prompt 再调,直到达成或撞刹车。

### 五要件(给任何 agent 写 goal mode,都靠这五件)

1. **存目标** —— 目标 + 一条能跑出 0/1 的完成条件(`goal.sh`)
2. **判完成** —— 跑 `DONE_CMD` 看退出码(`check-goal.sh`)
3. **没达成挡回** —— 返回"别停,继续"+ 把"还差什么"喂回去
4. **钩住想停** —— 这是唯一各平台不一样的一件(Stop hook / idle 事件 / wrapper)
5. **刹车** —— `MAX_TURNS`(轮数)+ `MAX_SECONDS`(时间)双刹车,撞刹车记 `.status` 区分停因(对标 Codex 的 token/时间预算 + 状态机)

换一个 agent 平台,只换第 4 件,其余四件逻辑照搬。

## 如果你是 AI agent

读 [AGENTS.md](AGENTS.md) —— 里面是命令式的接入步骤(怎么跑 install、怎么从 `package.json`/`Makefile` 推断 `DONE_CMD`、各平台接入位置、怎么自检)。

## 诚实的边界

- **档 2(opencode / pi)是实验性** —— 续轮 API 的方法签名从 SDK + 现成 goal 插件推断,未在真 agent 端到端验证;落地前按 `adapters/*/` 注释核对,见 [TESTING.md](TESTING.md)。
- **Kiro 不支持** —— 它的 Stop hook 是 observe-only、不能 block,做不了 goal mode(官方只有 `PreToolUse` / `UserPromptSubmit` / `PreTaskExec` 能 block)。
- **状态按项目隔离,不按 session** —— `.goalkeeper/.turns` / `.status` 是项目级。同一项目里同时跑多个 agent / session 会共享轮数与预算;单任务场景不受影响。
- **`DONE_CMD` = 本地代码执行** —— 它在你自己项目的 `goal.sh` 里,等同本地脚本;别执行不可信的 `goal.sh`。失败输出喂回模型前已截断(`MAX_OUTPUT_CHARS`)防 secret 泄漏。
- **wrapper 档**每轮重启 agent 进程,靠 `--continue` / session resume 保上下文;比原生钩子重,但对任何 CLI 都通吃。

## License

MIT
