# goalkeeper

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
MAX_TURNS=30             # 刹车: 最多自动续多少轮,撞上限转人工
```

然后**正常启动你的 agent 干活**。它每次想停,goalkeeper 跑一次 `DONE_CMD`:没过 → 拦回去喂"继续修",过了或撞 `MAX_TURNS` → 放行。

## 支持哪些 agent

| 平台 | 命令 | "想停"钩子 | 接入位置 | 自动接入 |
|---|---|---|---|---|
| Claude Code | `claude` | `Stop` hook | `.claude/settings.json` | ✓ |
| Kimi Code | `kimi` | `Stop` hook | `.kimi/config.toml` | ✓ |
| Kiro | `kiro-cli` | `stop` hook | `.kiro/agents/goalkeeper.json` | ✓ |
| opencode | `opencode` | `session.idle` 事件 | `.opencode/plugin/goalkeeper.js` | ✓ |
| pi | `pi` | `agent_end` 事件 | `.pi/extensions/goalkeeper.ts` | ✓(需 `pi -e` 加载) |
| openclaw | `openclaw` | 无强制续跑钩子 | wrapper | 用 `goalkeeper-run.sh` |
| hermes | `hermes` | 只能观察、不能拦 | wrapper | 用 `goalkeeper-run.sh` |
| ZCode | (GUI,无 CLI) | 自带 `/goal` | — | 用它自带的,或走 Claude Code 路线 |

> **ZCode** 是桌面 GUI,接不进外部 hook。两条路:直接用它**自带的 `/goal`**;或改用 GLM 驱动 Claude Code(设 `ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic`),那样复用 Claude Code 的接入。

## 原理:一个判定核心 + 三档适配

所有平台共用同一个判定真相源 `.goalkeeper/check-goal.sh`:跑 `DONE_CMD` 看退出码 + 用 `.turns` 文件做 `MAX_TURNS` 刹车。各平台只是**用不同方式把它钩进"agent 想停"那一刻**:

- **档 1 · 原生 Stop 钩子**(Claude Code / Kimi / Kiro):agent 的停止钩子直接调 `check-goal.sh`,读它返回的 `{"decision":"block","reason":...}` 决定拦不拦。三家配置载体不同(JSON / TOML / JSON),脚本同一个。
- **档 2 · 事件插件**(opencode / pi):插件挂 `session.idle` / `agent_end` 事件,`spawn` 一次 `check-goal.sh` 判定,没达成就用各家续轮 API(`client.session.promptAsync()` / `pi.sendUserMessage(.., {deliverAs:"followUp"})`)把"继续修"投回去。
- **档 3 · 通用 wrapper**(hermes / openclaw / 任意 headless CLI):它们没有"强制续跑"的钩子,改用 `.goalkeeper/goalkeeper-run.sh "任务"` 在**进程外**包一个循环:调 agent 跑一轮 → 跑 `DONE_CMD` → 没过把失败输出当下一轮 prompt 再调,直到达成或撞刹车。

### 五要件(给任何 agent 写 goal mode,都靠这五件)

1. **存目标** —— 目标 + 一条能跑出 0/1 的完成条件(`goal.sh`)
2. **判完成** —— 跑 `DONE_CMD` 看退出码(`check-goal.sh`)
3. **没达成挡回** —— 返回"别停,继续"+ 把"还差什么"喂回去
4. **钩住想停** —— 这是唯一各平台不一样的一件(Stop hook / idle 事件 / wrapper)
5. **刹车** —— `MAX_TURNS` / 超时 / 无进展检测,防无限烧钱

换一个 agent 平台,只换第 4 件,其余四件逻辑照搬。

## 如果你是 AI agent

读 [AGENTS.md](AGENTS.md) —— 里面是命令式的接入步骤(怎么跑 install、怎么从 `package.json`/`Makefile` 推断 `DONE_CMD`、各平台接入位置、怎么自检)。

## 诚实的边界

- **档 2 的续轮 API**(opencode 的 `promptAsync`、pi 的 `sendUserMessage`)是从官方插件文档 + 现成 goal 插件源码确认的;落地前请按 `adapters/*/` 文件注释里的参考 repo 核对一次方法签名。
- **Kiro** 的 stop hook 有已知 bug([Kiro#4183](https://github.com/kirodotdev/Kiro/issues/4183),会吞响应最后一行),上线前真机验证一次 block→续轮链路。
- **wrapper 档**每轮重启 agent 进程,靠 `--continue` / session resume 保上下文;比原生钩子重,但对任何 CLI 都通吃。

## License

MIT
