#!/usr/bin/env bash
# goalkeeper · 通用 wrapper(档3)
# 给没有"强制续跑"stop 钩子的 agent 兜底:hermes / openclaw / 任意 headless CLI。
# 它在进程外包一个循环:调 agent 跑一轮 -> 跑完成条件命令 -> 没过就把失败原因当下一轮 prompt 再调,直到达成或撞刹车。
#
# 用法: goalkeeper-run.sh "任务描述"
#   AGENT_CMD / RESUME_FLAG / DONE_CMD / MAX_TURNS 从 .goalkeeper/goal.sh 读,可用环境变量覆盖。
set -uo pipefail

GKDIR="${GOALKEEPER_DIR:-$PWD/.goalkeeper}"
# shellcheck disable=SC1091
[ -f "$GKDIR/goal.sh" ] && source "$GKDIR/goal.sh"

TASK="${1:?用法: goalkeeper-run.sh \"任务描述\"}"
: "${DONE_CMD:=npm test}"
: "${MAX_TURNS:=10}"
: "${AGENT_CMD:=hermes -z}"
: "${RESUME_FLAG:=--continue}"
: "${TURN_TIMEOUT:=1800}"        # 单轮墙钟秒数,防单轮挂死
: "${NO_PROGRESS_LIMIT:=3}"      # 连续几轮无进展就判卡死
: "${MAX_SECONDS:=0}"            # 刹车:总墙钟预算(秒,0=不限)

prompt="$TASK"; resume=""; last_fp=""; stale=0; START_TS=$(date +%s)

for ((t=1; t<=MAX_TURNS; t++)); do
  echo "── goalkeeper 轮 $t/$MAX_TURNS ──" >&2

  # 0) 时间预算:撞总墙钟就停(长任务的主刹车)
  if [ "$MAX_SECONDS" -gt 0 ] && [ $(( $(date +%s) - START_TS )) -ge "$MAX_SECONDS" ]; then
    echo "撞时间预算 ${MAX_SECONDS}s,停。" >&2; exit 4
  fi

  # 1) 调 agent 跑一轮(单轮超时保护)。第一轮全新,之后续接 session。
  # shellcheck disable=SC2086
  timeout "$TURN_TIMEOUT" $AGENT_CMD $resume "$prompt"
  [ $? -eq 124 ] && { echo "单轮超时,停。" >&2; exit 2; }
  resume="$RESUME_FLAG"

  # 2) 跑完成条件命令,捕获输出 + 退出码
  out="$(eval "$DONE_CMD" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "✅ 达成(完成条件退出码 0),共 $t 轮。" >&2
    exit 0
  fi

  # 3) 无进展刹车:完成命令输出 + 代码状态指纹连续不变 -> 判卡死
  fp="$(printf '%s' "$out" | shasum 2>/dev/null)$(git status --porcelain 2>/dev/null | shasum 2>/dev/null)"
  if [ "$fp" = "$last_fp" ]; then
    stale=$((stale+1)); echo "无进展 $stale/$NO_PROGRESS_LIMIT" >&2
    [ "$stale" -ge "$NO_PROGRESS_LIMIT" ] && { echo "连续无进展,停。" >&2; exit 3; }
  else
    stale=0
  fi
  last_fp="$fp"

  # 4) 把失败原因当下一轮 prompt 喂回
  prompt="完成条件 \`$DONE_CMD\` 仍未通过(退出码 $rc)。失败输出:
$out

请继续修复,直到该命令退出码为 0。只改必要代码,不要改测试本身。"
done

echo "❌ 撞 MAX_TURNS=$MAX_TURNS 仍未达成,停。" >&2
exit 1
