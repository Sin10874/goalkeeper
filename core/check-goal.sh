#!/usr/bin/env bash
# goalkeeper · 判定核心(单一真相源)
# 档1(Claude Code / Kimi / Kiro)的 Stop 钩子直接调它,读它 stdout 的 JSON。
# 档2(opencode / pi)插件 spawn 它、解析输出,再用各家 API 续轮。
# 达成或撞刹车 -> exit 0(放行,无 stdout);未达成 -> 输出 {"decision":"block","reason":...} 拦回。
set -uo pipefail
GK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$GK_DIR/goal.sh"

# 消费 stdin(Claude Code / Kimi 会通过 stdin 传 JSON),但不据此放行 ——
# 防无限循环靠下面的 MAX_TURNS 刹车,不靠 stop_hook_active;否则只会拦一轮就放手,达不到"不达目的不停手"。
cat >/dev/null 2>&1 || true

# 计时:第一次被调用时记下开始时间(时间预算的基准)
[ -f "$GK_DIR/.started" ] || date +%s > "$GK_DIR/.started"
STARTED="$(cat "$GK_DIR/.started" 2>/dev/null || date +%s)"
ELAPSED=$(( $(date +%s) - STARTED ))
COUNT="$(cat "$GK_DIR/.turns" 2>/dev/null || echo 0)"
clear_state(){ rm -f "$GK_DIR/.turns" "$GK_DIR/.started"; }
# JSON 字符串转义:防 GOAL/DONE_CMD 里的 " \ 换行 破坏 block JSON(顺序:先反斜杠)
json_escape(){ local s=$1; s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\r'/}; s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; printf '%s' "$s"; }

# 跑完成条件命令 —— 用超时包住,否则 DONE_CMD 卡死会让整个 hook 挂死、时间预算永不放行。
# 安全边界:DONE_CMD 是你在自己项目 .goalkeeper/goal.sh 里写的,等同本地脚本;别执行不可信的 goal.sh。
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
# 超时跑一条命令:优先 GNU timeout/gtimeout;macOS 默认两者都没有,用纯 bash 后台 + watcher kill 兜底。
run_timed(){
  local secs=$1; shift
  if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "$secs" "$@"; return $?; fi
  "$@" & local pid=$!
  ( sleep "$secs"; kill -TERM "$pid" 2>/dev/null; sleep 2; kill -KILL "$pid" 2>/dev/null ) >/dev/null 2>&1 & local w=$!
  wait "$pid" 2>/dev/null; local rc=$?
  kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
  return "$rc"
}
run_done(){ run_timed "${DONE_TIMEOUT:-120}" bash -c "${DONE_CMD:-false}" >/dev/null 2>&1; }

# 判完成最优先:退出码 0 = 真达成
if run_done; then
  echo "complete" > "$GK_DIR/.status"; clear_state; exit 0
fi

# 刹车 1 · 时间预算(长任务的主刹车;0 = 不限)
if [ "${MAX_SECONDS:-0}" -gt 0 ] && [ "$ELAPSED" -ge "${MAX_SECONDS}" ]; then
  echo "time_limited" > "$GK_DIR/.status"; clear_state
  echo "goalkeeper: 撞时间预算 ${MAX_SECONDS}s(已跑 ${ELAPSED}s),放行转人工" >&2; exit 0
fi

# 刹车 2 · 轮数上限
if [ "$COUNT" -ge "${MAX_TURNS:-30}" ]; then
  echo "turns_limited" > "$GK_DIR/.status"; clear_state
  echo "goalkeeper: 撞 ${MAX_TURNS} 轮上限,放行转人工" >&2; exit 0
fi

# 未达成 + 没撞刹车 -> 拦回,把进度喂回 agent(reason 会进模型上下文)
echo $((COUNT + 1)) > "$GK_DIR/.turns"; echo "active" > "$GK_DIR/.status"
reason="目标未达成: ${GOAL}。完成条件「${DONE_CMD}」还没通过(已续 $((COUNT + 1)) 轮 / ${ELAPSED}s),继续修,别停。"
printf '{"decision":"block","reason":"%s"}\n' "$(json_escape "$reason")"
