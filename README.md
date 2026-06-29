# goalkeeper

[![test](https://github.com/Sin10874/goalkeeper/actions/workflows/test.yml/badge.svg)](https://github.com/Sin10874/goalkeeper/actions/workflows/test.yml)

> 给**没有原生 goal mode** 的 coding agent 一个 `/goal` —— 而且是**跑真命令看退出码**的那种,治 agent "自己说做完了" 的假绿。

## 它解决什么

主流 agent 的 goal mode(Claude Code 的 `/goal`、Codex 的 goal、opencode 社区那几个 `opencode-goal-plugin`)有个**共同软肋:完成判定靠模型自报** —— agent 说一句"做完了"、或调个 `update_goal` 标 `complete`,就算完成。模型会**假绿**:测试还红着,它也敢说做完。

goalkeeper 只换一件事:**agent 想停时,跑你项目的完成条件命令(自动推断,如 `npm test`),退出码 `0` 才算完。** 确定性判定,模型骗不了。

## 先看你该不该用它

| 你在用 | 建议 |
|---|---|
| **Claude Code / Codex** | 多数情况**用它们原生的 `/goal`** 就够(内建、成熟)。只有当你嫌它们"靠模型 / 小模型读对话判完成"会假绿、想要**退出码硬把关**时,才考虑 goalkeeper(它在 Claude Code 上端到端验证过)。 |
| **opencode / pi** | 它们没有内建的、带退出码硬判定的 goal —— **这是 goalkeeper 的主场**。 |
| **hermes / openclaw / 任意 headless CLI** | 用 goalkeeper 的 wrapper 档。 |
| Kiro / ZCode | 用不了(Kiro 的 Stop hook 不能 block;ZCode 无 CLI)。 |

## 用(opencode 为例)

```bash
bash ~/goalkeeper/install.sh     # 检测本机 agent,装到 opencode
```

然后在 opencode 里,一句话:

```
/goal 把登录做完,直到测试通过
```

goalkeeper **自动从项目推断完成条件**(`package.json` 有 test → `npm`/`pnpm test`、`pyproject.toml` → `pytest -q`、`Cargo.toml` → `cargo test`、`Makefile` → `make test`…),你不用写命令。agent 想停时它跑一次:没过把"还差什么"塞回去续轮,过了 / 撞预算才放行。**全程不碰配置文件。**

> 推不准?可在 `.goalkeeper/goal.sh` 手填 `DONE_CMD` —— 那是兜底,不是主路径。

子命令:`/goal status` 看状态 · `/goal clear` 清除。

## 原理

判定真相源 `.goalkeeper/check-goal.sh`:跑 `DONE_CMD` 看退出码(确定性)+ `MAX_TURNS`(轮数) / `MAX_SECONDS`(时间)刹车。各平台把它钩进"agent 想停"那一刻:

- **opencode / pi(事件插件)**:`/goal <一句话>` 命令设目标 + 自动推断 `DONE_CMD`;挂 `session.idle` / `agent_end` 事件,空闲时跑判定,没达成用续轮 API(`promptAsync` / `prompt` 兼容两种 / `sendMessage`)把"继续修"投回会话。
- **wrapper(hermes / openclaw / 任意 headless CLI)**:进程外循环,调 agent 跑一轮 → 跑 `DONE_CMD` → 没过把失败输出当下轮 prompt 再调。
- **Claude Code / Kimi(原生 Stop 钩子)**:hook 直接调 `check-goal.sh` 读 `{"decision":"block","reason"}`。(但 CC 有原生 `/goal`,多数人不需要这条。)

**和现成 opencode goal 项目(watzon / prevalentWare / willytop8)唯一的区别**:它们都让 agent 自报完成(会假绿),goalkeeper 跑真命令看退出码。壳照搬它们(`/goal` 命令、event/idle 续轮、防重入),芯换成退出码硬判定。

## 诚实的边界

- **opencode / pi 是基于三份真源码写的,但我没有真 opencode 会话做端到端验证。** 结构(`promptAsync`/`prompt` 兼容、`event`/`isIdle`、`/goal` 命令、防重入 Set)有 watzon / prevalentWare / willytop8 三份源码佐证 + 推断逻辑本地验证;但"真机续轮"这步标 🧪 实验性,欢迎 PR 验证 —— 见 [TESTING.md](TESTING.md)。
- **唯一端到端真验证过的平台是 Claude Code**(`claude -p` 跑通拦回续轮 + 刹车)。但如上,CC 有原生 `/goal`,这更多是证明"判定核心真能拦回续轮",不是推荐你在 CC 上舍原生用它。
- **自动推断 `DONE_CMD`** 覆盖 node / python / rust / go / make,推不出会提示你手填。
- **`DONE_CMD` = 本地代码执行** —— 它在你项目的 `goal.sh` 里,等同本地脚本;别执行不可信的 `goal.sh`。失败输出喂回模型前已截断,缩小泄漏面(截断,非完整脱敏)。
- **状态按项目隔离,不按 session** —— 同项目并发多 agent / session 会共享轮数与预算;单任务不受影响。

## License

MIT
