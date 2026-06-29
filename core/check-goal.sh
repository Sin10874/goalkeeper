#!/usr/bin/env bash
# goalkeeper · 判定核心(单一真相源)
# 档1(Claude Code / Kimi / Kiro)的 Stop 钩子直接调它,读它 stdout 的 JSON。
# 档2(opencode / pi)插件 spawn 它、解析输出,再用各家 API 续轮。
# 达成或撞刹车 -> exit 0(放行,无 stdout);未达成 -> 输出 {"decision":"block","reason":...} 拦回。
set -uo pipefail
GK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$GK_DIR/goal.sh"

# 读 stdin:Claude Code / Kimi 会传 JSON。含 stop_hook_active=true 说明已在续轮循环里,放行防死循环。
input="$(cat 2>/dev/null || true)"
case "$input" in
  *'"stop_hook_active": true'*|*'"stop_hook_active":true'*) exit 0 ;;
esac

# 刹车:撞续作上限就放行,清计数
COUNT="$(cat "$GK_DIR/.turns" 2>/dev/null || echo 0)"
if [ "$COUNT" -ge "${MAX_TURNS:-30}" ]; then
  rm -f "$GK_DIR/.turns"
  echo "goalkeeper: 撞 ${MAX_TURNS} 轮上限,放行转人工(目标仍未达成)" >&2
  exit 0
fi

# 判完成:跑完成条件命令,退出码 0 = 真达成
if eval "${DONE_CMD:-false}" >/dev/null 2>&1; then
  rm -f "$GK_DIR/.turns"
  exit 0
fi

# 未达成 -> 拦回 + 把"还差什么"喂回 agent(reason 会进模型上下文)
echo $((COUNT + 1)) > "$GK_DIR/.turns"
printf '{"decision":"block","reason":"目标未达成: %s。完成条件「%s」还没通过(已续 %s 轮),继续修,别停。"}\n' \
  "$GOAL" "$DONE_CMD" "$((COUNT + 1))"
