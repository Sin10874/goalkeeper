# ZCode 接入说明

ZCode(Z.ai)是桌面 GUI 应用,没有 CLI、没有 headless,接不进外部 hook 或 wrapper。所以 goalkeeper 不给它单独装东西。两条路:

1. **用 ZCode 自带的 `/goal`** —— 它原生就有 goal mode,直接用。
2. **改用 GLM 驱动 Claude Code** —— 设环境变量后跑的还是 `claude` CLI,于是复用 goalkeeper 的 Claude Code 接入(`.claude/settings.json` 的 Stop hook):

   ```bash
   export ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic
   export ANTHROPIC_AUTH_TOKEN=<你的 z.ai key>
   ```

   安装 goalkeeper 时选 **Claude Code** 一项即可。
