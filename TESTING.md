# 测试与验证

goalkeeper 分两层验证:**自动化测试**(不依赖真 agent,CI 每次跑)和**端到端验证**(在真 agent 上手动跑)。

## 自动化测试(不依赖真 agent)

```bash
bash test/run.sh
```

覆盖判定核心的 10 个断言:判定四路径(拦回 / 达成 / 轮数刹车 / 时间刹车)、JSON 转义(含引号反斜杠不破 JSON)、防"只拦一轮"回归、install 文件生成 + 配置合法性。CI(GitHub Action)每次 push / PR 自动跑。

## 端到端验证(在真 agent 上)

判定逻辑测了,但"agent 想停时 hook 真触发并续轮"这件事,每个 agent 得在真 agent 上验。**目前只有 Claude Code 验过。**

### 通用做法(以 Claude Code 为例)

1. 建 mock 项目,装 goalkeeper(选该 agent)。
2. 把 `DONE_CMD` 设成一个记录调用次数的探针:
   ```bash
   printf 'echo tick >> "$PWD/.goalkeeper/calls.log"\nexit 1\n' > .goalkeeper/done.sh
   chmod +x .goalkeeper/done.sh
   # .goalkeeper/goal.sh: DONE_CMD=".goalkeeper/done.sh"  MAX_TURNS=2
   ```
3. 跑 agent 的非交互模式,诱导它"一句话就停":
   ```bash
   claude -p "请只回复'收到'就结束,不要调用工具。"
   ```
4. 看 `.goalkeeper/calls.log` 行数 = agent 被拦回的次数。**≥2 且最终 `.status` = `turns_limited`** = hook 真触发、续轮、刹车全通。

### 各 agent 的坑(已知,验证时注意)

- **Kimi**:只读全局 `~/.kimi/config.toml`,`--config-file` 是替换不合并。验证时把 hook 段加到全局 config(和 model 配置一起),再用 `kimi --print -p "..."`。
- **opencode / pi**:续轮 API(`client.session.promptAsync` / `pi.sendUserMessage`)从社区插件推断,需在真 opencode / pi 上核对方法签名(见 `adapters/*/` 注释里的参考 repo)。
- **Kiro**:stop hook 有吞响应最后一行的 bug([#4183](https://github.com/kirodotdev/Kiro/issues/4183))。

**验证通过某个平台后,欢迎提 PR** 把 README 支持表里它的标记从 🧪 / ⚙️ 升到 ✅,附上你的验证命令和 `calls.log` 结果。
