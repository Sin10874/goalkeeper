#!/usr/bin/env bash
# goalkeeper · 通用 wrapper(档3)
# 给没有"强制续跑"stop 钩子的 agent 兜底:hermes / openclaw / 任意 headless CLI。
# 进程外循环:调 agent 跑一轮 -> 跑 DONE_CMD -> 没过把失败原因当下一轮 prompt 再调,直到达成或撞刹车。
# 用法: goalkeeper-run.sh "任务描述"
set -uo pipefail

GKDIR="${GOALKEEPER_DIR:-$PWD/.goalkeeper}"
# shellcheck disable=SC1091
[ -f "$GKDIR/goal.sh" ] && source "$GKDIR/goal.sh"

TASK="${1:?用法: goalkeeper-run.sh \"任务描述\"}"
: "${DONE_CMD:=npm test}"
: "${MAX_TURNS:=10}"
: "${AGENT_CMD:=hermes -z}"
: "${RESUME_FLAG:=--continue}"
: "${TURN_TIMEOUT:=1800}"          # 单轮墙钟秒数
: "${DONE_TIMEOUT:=120}"           # 单次 DONE_CMD 最多跑多久,防卡死
: "${NO_PROGRESS_LIMIT:=3}"        # 连续几轮无进展就判卡死
: "${MAX_SECONDS:=0}"              # 总墙钟预算(0=不限)
: "${MAX_OUTPUT_CHARS:=4000}"      # 喂回模型的失败输出上限,缩小 token / secret 泄漏面(截断,非完整脱敏)

# 超时命令:优先 GNU timeout/gtimeout;macOS 默认两者都没有,guard 里用纯 bash 兜底
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"

# 递归杀整棵进程树(与 check-goal 一致),纯 bash 兜底覆盖深层子/孙进程
kill_tree(){ local p=$1 sig=$2 c; for c in $(pgrep -P "$p" 2>/dev/null); do kill_tree "$c" "$sig"; done; kill "-$sig" "$p" 2>/dev/null; }
# 超时跑一条命令:有 timeout 命令就用;没有就纯 bash 后台 + 整树 kill(macOS 兜底,不再裸跑卡死)
guard(){
  local secs=$1; shift
  if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "$secs" "$@"; return $?; fi
  "$@" & local pid=$!
  ( sleep "$secs"; kill_tree "$pid" TERM; sleep 2; kill_tree "$pid" KILL ) >/dev/null 2>&1 & local w=$!
  wait "$pid" 2>/dev/null; local rc=$?
  kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
  [ "$rc" -gt 128 ] && rc=124   # 超时被信号杀统一成 124,和 GNU timeout 对齐
  return "$rc"
}

prompt="$TASK"; resume=""; last_fp=""; stale=0; START_TS=$(date +%s)

for ((t=1; t<=MAX_TURNS; t++)); do
  echo "── goalkeeper 轮 $t/$MAX_TURNS ──" >&2

  # 0) 时间预算:撞总墙钟就停(长任务的主刹车)
  if [ "$MAX_SECONDS" -gt 0 ] && [ $(( $(date +%s) - START_TS )) -ge "$MAX_SECONDS" ]; then
    echo "撞时间预算 ${MAX_SECONDS}s,停。" >&2; exit 4
  fi

  # 1) 调 agent 跑一轮(单轮超时保护)。捕获退出码:124=超时,非0=认证失败/命令不存在/崩溃,都别空转。
  # shellcheck disable=SC2086
  guard "$TURN_TIMEOUT" $AGENT_CMD $resume "$prompt"; arc=$?
  [ "$arc" -eq 124 ] && { echo "单轮超时(${TURN_TIMEOUT}s),停。" >&2; exit 2; }
  [ "$arc" -ne 0 ] && { echo "agent 非正常退出(rc=$arc:认证失败/命令不存在/崩溃?),停,别空转误判。" >&2; exit 5; }
  resume="$RESUME_FLAG"

  # 2) 跑完成条件命令(超时包住)。写临时文件再 tail 取尾部:不爆内存,也不会被 head 管道的 SIGPIPE
  #    把"成功但输出大"的命令退出码打成 141。ulimit -f 给临时文件封顶,防输出洪泛打满 /tmp。
  _o="$(mktemp "${TMPDIR:-/tmp}/gk.XXXXXX")"
  ( ulimit -f 4096 2>/dev/null; guard "$DONE_TIMEOUT" bash -c "$DONE_CMD" >"$_o" 2>&1 ); rc=$?
  out="$(tail -c 200000 "$_o")"; rm -f "$_o"
  if [ "$rc" -eq 0 ]; then echo "✅ 达成(完成条件退出码 0),共 $t 轮。" >&2; exit 0; fi

  # 3) 无进展刹车:完成命令输出 + 代码状态指纹连续不变 -> 判卡死
  fp="$(printf '%s' "$out" | shasum 2>/dev/null)$(git status --porcelain 2>/dev/null | shasum 2>/dev/null)"
  if [ "$fp" = "$last_fp" ]; then
    stale=$((stale+1)); echo "无进展 $stale/$NO_PROGRESS_LIMIT" >&2
    [ "$stale" -ge "$NO_PROGRESS_LIMIT" ] && { echo "连续无进展,停。" >&2; exit 3; }
  else stale=0; fi
  last_fp="$fp"

  # 4) 把失败原因(截断到末 N 字符,缩小 token / secret 泄漏面;注意:这是截断不是完整脱敏)当下一轮 prompt 喂回
  clip="$(printf '%s' "$out" | tail -c "$MAX_OUTPUT_CHARS")"
  prompt="完成条件 \`$DONE_CMD\` 仍未通过(退出码 $rc)。失败输出(末 ${MAX_OUTPUT_CHARS} 字符):
$clip

请继续修复,直到该命令退出码为 0。只改必要代码,不要改测试本身。"
done

echo "❌ 撞 MAX_TURNS=$MAX_TURNS 仍未达成,停。" >&2
exit 1
