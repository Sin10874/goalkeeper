#!/usr/bin/env bash
# goalkeeper 安装器 · 让 coding agent 不达目的不停手
# 检测本地装了哪些 coding agent -> 你选哪些生效 -> 给选中的接入 goal mode。
# 用法:
#   ./install.sh                      # 装到当前目录这个项目(交互选平台)
#   GOALKEEPER_PICK="all" ./install.sh        # 非交互,全部接入
#   GOALKEEPER_TARGET=/path ./install.sh      # 装到别的项目
set -uo pipefail

GK_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${GOALKEEPER_TARGET:-$PWD}"
GKDIR="$TARGET/.goalkeeper"
PY="$(command -v python3 || command -v python || true)"

say() { printf '%s\n' "$*"; }
hr()  { printf '%s\n' "──────────────────────────────────────────────"; }

hr; say "goalkeeper · 让 coding agent 不达目的不停手"; say "安装到项目: $TARGET"; hr

# ── 1) 检测本地 coding agent ──────────────────────────────────
declare -a F_NAME F_KEY
idx=0
have() { command -v "$1" >/dev/null 2>&1; }
check() { # $1 显示名  $2 检测命令(zcode 留空)  $3 平台key
  local ok=0
  if [ "$3" = "zcode" ]; then [ -d "/Applications/ZCode.app" ] && ok=1
  elif have "$2"; then ok=1; fi
  if [ "$ok" = "1" ]; then idx=$((idx+1)); F_NAME[$idx]="$1"; F_KEY[$idx]="$3"; printf "  [%d] %s\n" "$idx" "$1"; fi
}
say "检测到的 coding agent:"
check "Claude Code" claude   claude
check "Kimi Code"   kimi     kimi
check "Kiro"        kiro-cli kiro
check "opencode"    opencode opencode
check "pi"          pi       pi
check "openclaw"    openclaw openclaw
check "hermes"      hermes   hermes
check "ZCode"       ""       zcode
[ "$idx" -eq 0 ] && { say "没检测到任何支持的 coding agent。装好其中之一再跑。"; exit 1; }

# ── 2) 选哪些生效 ─────────────────────────────────────────────
hr
if [ -n "${GOALKEEPER_PICK:-}" ]; then pick="$GOALKEEPER_PICK"
else printf "给哪些平台开启 goal mode?(空格分隔序号,all=全部): "; read -r pick; fi
[ "$pick" = "all" ] && pick="$(seq 1 "$idx")"
[ -z "${pick// }" ] && { say "没选任何平台,退出。"; exit 0; }

# ── 3) 写公共判定核心 + 目标配置 ──────────────────────────────
mkdir -p "$GKDIR"
cp "$GK_SRC/core/check-goal.sh"        "$GKDIR/check-goal.sh";        chmod +x "$GKDIR/check-goal.sh"
cp "$GK_SRC/wrapper/goalkeeper-run.sh" "$GKDIR/goalkeeper-run.sh";    chmod +x "$GKDIR/goalkeeper-run.sh"
if [ ! -f "$GKDIR/goal.sh" ]; then cp "$GK_SRC/core/goal.sh" "$GKDIR/goal.sh"; say "已写目标配置: .goalkeeper/goal.sh"; else say "保留已有 .goalkeeper/goal.sh"; fi
CHECK="$GKDIR/check-goal.sh"

# ── 4) 各平台接入函数 ─────────────────────────────────────────
inject_claude() {
  local f="$TARGET/.claude/settings.json"; mkdir -p "$TARGET/.claude"; [ -f "$f" ] && cp "$f" "$f.bak.goalkeeper"
  "$PY" - "$f" "$CHECK" <<'PY'
import json,sys,os
f,cmd=sys.argv[1],sys.argv[2]
d=json.load(open(f)) if os.path.exists(f) and os.path.getsize(f) else {}
h=d.setdefault("hooks",{}).setdefault("Stop",[])
if cmd not in json.dumps(h):
    h.append({"hooks":[{"type":"command","command":cmd}]})
json.dump(d,open(f,"w"),ensure_ascii=False,indent=2)
PY
  say "  ✓ Claude Code: Stop hook → .claude/settings.json(嵌套格式)"
}
inject_kimi() {
  # Kimi 只读全局 ~/.kimi/config.toml,且 --config-file 是替换不合并 —— 项目级装了它不读。
  # 所以只生成 hook 片段 + 提示用户手动追加到全局,不假装项目级生效。
  local f="$TARGET/.kimi/goalkeeper-hook.toml"; mkdir -p "$TARGET/.kimi"
  printf '# 追加到全局 ~/.kimi/config.toml(Kimi 不读项目级 config)\n[[hooks]]\nevent = "Stop"\ncommand = "%s"\ntimeout = 60\n' "$CHECK" > "$f"
  say "  ⚠ Kimi: 已生成 hook 片段 → .kimi/goalkeeper-hook.toml"
  say "      Kimi 只读全局 config,请手动追加到 ~/.kimi/config.toml(和 model 配置放一起,别覆盖)。"
}
inject_kiro() {
  local f="$TARGET/.kiro/agents/goalkeeper.json"; mkdir -p "$TARGET/.kiro/agents"
  "$PY" - "$f" "$CHECK" <<'PY'
import json,sys,os
f,cmd=sys.argv[1],sys.argv[2]
d=json.load(open(f)) if os.path.exists(f) and os.path.getsize(f) else {"name":"goalkeeper"}
s=d.setdefault("hooks",{}).setdefault("stop",[])
if cmd not in json.dumps(s): s.append({"command":cmd})
json.dump(d,open(f,"w"),ensure_ascii=False,indent=2)
PY
  say "  ✓ Kiro: .kiro/agents/goalkeeper.json(启动加 --agent goalkeeper)"
}
inject_opencode() {
  mkdir -p "$TARGET/.opencode/plugin"
  cp "$GK_SRC/adapters/opencode/goalkeeper.js" "$TARGET/.opencode/plugin/goalkeeper.js"
  say "  ✓ opencode: 插件 → .opencode/plugin/goalkeeper.js(启动自动加载;若不生效试 .opencode/plugins/)"
}
inject_pi() {
  mkdir -p "$TARGET/.pi/extensions"
  cp "$GK_SRC/adapters/pi/goalkeeper.ts" "$TARGET/.pi/extensions/goalkeeper.ts"
  say "  ✓ pi: 扩展 → .pi/extensions/goalkeeper.ts(用 \`pi -e .pi/extensions/goalkeeper.ts\` 加载)"
}
wrapper_note() {
  say "  ✓ $1: 走 wrapper —— 用 \`.goalkeeper/goalkeeper-run.sh \"任务描述\"\` 启动"
  say "      先在 .goalkeeper/goal.sh 设 AGENT_CMD(如 hermes: \"hermes -z\";openclaw: \"openclaw agent --local -m\")"
}
zcode_note() {
  say "  • ZCode: GUI 无 CLI,接不进外部 hook。两条路:"
  say "      1) 直接用 ZCode 自带的 /goal(原生);"
  say "      2) 改用 GLM 驱动 Claude Code(设 ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic),复用上面的 Claude Code 接入。"
}

hr; say "接入结果:"
for n in $pick; do
  case "${F_KEY[$n]:-}" in
    claude) inject_claude ;; kimi) inject_kimi ;; kiro) inject_kiro ;;
    opencode) inject_opencode ;; pi) inject_pi ;;
    openclaw) wrapper_note openclaw ;; hermes) wrapper_note hermes ;;
    zcode) zcode_note ;; *) say "  ? 序号 $n 无效,跳过" ;;
  esac
done

hr; say "装好了。最后两步:"
say "  1) 编辑 .goalkeeper/goal.sh —— 把 DONE_CMD 改成你的完成条件(如 pnpm test / pytest -q / make check)"
say "  2) 正常启动 agent 干活;它每次想停,goalkeeper 跑一次 DONE_CMD,没过就拦回去继续,过了/撞 MAX_TURNS 才放行。"
say "诚实提醒: opencode/pi 的程序化续轮 API 请按 adapters/ 里注释的参考 repo 核对一次方法签名。"; hr
