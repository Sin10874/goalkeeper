# goalkeeper 目标配置 · 改这几行就够
# 这份文件被装到你项目的 .goalkeeper/goal.sh,所有接入的 agent 共用它。

GOAL="把当前这个任务做完,并通过下面的完成条件"
DONE_CMD="npm test"      # 完成条件命令,退出码 0 = 达成。换成你的: pnpm test / pytest -q / make check / ./verify.sh
MAX_TURNS=30             # 刹车: 最多自动续多少轮,撞上限就放行转人工(防无限烧钱)

# ── 仅 wrapper 模式(hermes / openclaw / 任意没有 stop 钩子的 CLI)才用到 ──
AGENT_CMD="${AGENT_CMD:-hermes -z}"        # 单发 / headless 调用前缀
RESUME_FLAG="${RESUME_FLAG:---continue}"   # 续接上一轮 session 的 flag(没有就设成空)
