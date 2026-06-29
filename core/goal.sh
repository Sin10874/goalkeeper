# goalkeeper 目标配置 · 改这几行就够
# 这份文件被装到你项目的 .goalkeeper/goal.sh,所有接入的 agent 共用它。

GOAL="把当前这个任务做完,并通过下面的完成条件"
DONE_CMD="npm test"      # 完成条件命令,退出码 0 = 达成。换成你的: pnpm test / pytest -q / make check / ./verify.sh
MAX_TURNS=30             # 刹车1: 最多自动续多少轮,撞上限放行转人工
MAX_SECONDS=0            # 刹车2: 最多跑多少秒就放行(0=不限)。长任务建议设,如 7200=2 小时
DONE_TIMEOUT=120         # 单次完成条件命令最多跑多久(秒),防 DONE_CMD 卡死把 hook 拖挂

# ── 仅 wrapper 模式(hermes / openclaw / 任意没有 stop 钩子的 CLI)才用到 ──
AGENT_CMD="${AGENT_CMD:-hermes -z}"        # 单发 / headless 调用前缀
RESUME_FLAG="${RESUME_FLAG:---continue}"   # 续接上一轮 session 的 flag(没有就设成空)
