# 给 AI agent 的 goalkeeper 接入指引

你在帮用户给他的 coding agent 装 goalkeeper —— 让 agent「不达目的不停手」:每次想停先跑一遍完成条件命令,没过就拦回去继续。照下面做。

## 1. 跑安装器

在用户的**项目根目录**:

```bash
GOALKEEPER_PICK=all GOALKEEPER_TARGET="$PWD" bash <goalkeeper仓库>/install.sh
```

`GOALKEEPER_PICK` 可换成空格分隔的序号(只接入部分平台)。它会检测本机 agent、写 `.goalkeeper/`、给各平台接入。

## 2. 设对 DONE_CMD(最关键的一步)

编辑 `.goalkeeper/goal.sh`。`DONE_CMD` 必须是一条**能跑出 0/1 的命令**(退出码 0 = 达成),从项目推断:

- 有 `package.json` 且含 `scripts.test` → `npm test`(用 pnpm/yarn 的换掉)
- Python 项目(有 `pyproject.toml`/`pytest.ini`)→ `pytest -q`
- 有 `Makefile` 且有 `check`/`test` 目标 → `make check`
- 有 CI 脚本 → 复用它本地能跑的那条
- 实在没有测试 → 至少用 `<build命令>`(如 `tsc --noEmit` / `cargo build`),别留 `true`

同时把 `GOAL` 写成一句话目标,`MAX_TURNS` 一般保持 30。

## 3. 各平台接入位置(install 已自动写,你确认即可)

| 平台 | 位置 | 备注 |
|---|---|---|
| Claude Code | `.claude/settings.json` → `hooks.Stop`(嵌套 `hooks` 数组) | 扁平写法不触发 |
| Kimi | `.kimi/config.toml` → `[[hooks]] event="Stop"` | |
| Kiro | `.kiro/agents/goalkeeper.json` → `hooks.stop` | 启动加 `--agent goalkeeper` |
| opencode | `.opencode/plugin/goalkeeper.js` | 启动自动加载 |
| pi | `.pi/extensions/goalkeeper.ts` | 提醒用户 `pi -e .pi/extensions/goalkeeper.ts` 加载 |
| hermes / openclaw | 无强制续跑钩子 | 改用 `.goalkeeper/goalkeeper-run.sh "任务"`,并在 `goal.sh` 设 `AGENT_CMD` |
| ZCode | GUI 无 CLI | 用它自带 `/goal`,或改 `ANTHROPIC_BASE_URL` 走 Claude Code |

## 4. 自检

```bash
echo '{}' | .goalkeeper/check-goal.sh
```

`DONE_CMD` 没过时,应输出 `{"decision":"block","reason":"..."}`;让 `DONE_CMD` 通过后再跑,应无输出、退出码 0。两种都对 = 接好了。

## 心智模型

判定真相源只有一个:`.goalkeeper/check-goal.sh`(跑 `DONE_CMD` 判退出码 + `MAX_TURNS` 刹车)。
所有平台都指向它,区别只在"用什么钩子在 agent 想停时调用它"。改完成条件 = 改 `goal.sh` 一行,不要去改各平台配置。
