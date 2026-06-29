#!/usr/bin/env bash
# goalkeeper 安装器 · 让 coding agent 不达目的不停手
# 检测本地装了哪些 coding agent -> 你选哪些生效 -> 给选中的接入 goal mode。
# 用法:
#   ./install.sh                          # 装到当前目录(交互选)
#   GOALKEEPER_PICK=all ./install.sh      # 非交互全装
#   GOALKEEPER_TARGET=/path ./install.sh  # 装到别的项目
set -uo pipefail   # best-effort:单平台失败不中断其余;关键步骤各自验证(见下)

GK_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${GOALKEEPER_TARGET:-$PWD}"
GKDIR="$TARGET/.goalkeeper"
PY="$(command -v python3 || command -v python || true)"

say() { printf '%s\n' "$*"; }
hr()  { printf '%s\n' "──────────────────────────────────────────────"; }
need_py(){ [ -n "$PY" ] && return 0; say "  ✗ $1: 需要 python3 合并配置但本机没装,跳过(装 python3 后重跑)"; return 1; }
# 转义路径,防其中的 " \ 破坏 JSON/TOML 字符串
esc(){ local s=$1; s=${s//\\/\\\\}; s=${s//\"/\\\"}; printf '%s' "$s"; }
# 拷贝并验证目标确实生成,失败返回非0(给安装做 fail-fast)
must_cp(){ cp "$1" "$2" 2>/dev/null && [ -e "$2" ]; }

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

# ── 3) 写公共判定核心 + 目标配置(失败即中止)──────────────────
mkdir -p "$GKDIR" || { say "无法创建 $GKDIR,中止。"; exit 1; }
must_cp "$GK_SRC/core/check-goal.sh"        "$GKDIR/check-goal.sh"     && chmod +x "$GKDIR/check-goal.sh" || { say "判定核心拷贝失败,中止。"; exit 1; }
must_cp "$GK_SRC/wrapper/goalkeeper-run.sh" "$GKDIR/goalkeeper-run.sh" && chmod +x "$GKDIR/goalkeeper-run.sh" || { say "wrapper 拷贝失败,中止。"; exit 1; }
if [ ! -f "$GKDIR/goal.sh" ]; then cp "$GK_SRC/core/goal.sh" "$GKDIR/goal.sh"; say "已写目标配置: .goalkeeper/goal.sh"; else say "保留已有 .goalkeeper/goal.sh"; fi
CHECK="$GKDIR/check-goal.sh"

# ── 4) 各平台接入函数 ─────────────────────────────────────────
inject_claude() {
  need_py "Claude Code" || return
  local f="$TARGET/.claude/settings.json"; mkdir -p "$TARGET/.claude"; [ -f "$f" ] && cp "$f" "$f.bak.goalkeeper"
  "$PY" - "$f" "$CHECK" <<'PY'
import json,sys,os
f,cmd=sys.argv[1],sys.argv[2]
d=json.load(open(f)) if os.path.exists(f) and os.path.getsize(f) else {}
stop=d.setdefault("hooks",{}).setdefault("Stop",[])
# 精确比较 command 字段(不是子串判断,避免路径互为子串误判)
exists=any(h.get("command")==cmd for g in stop for h in (g.get("hooks") or []))
if not exists:
    stop.append({"hooks":[{"type":"command","command":cmd}]})
json.dump(d,open(f,"w"),ensure_ascii=False,indent=2)
PY
  local mrc=$?
  if [ "$mrc" -ne 0 ]; then say "  ✗ Claude Code: 合并 settings.json 失败(python rc=$mrc),已备份 $f.bak.goalkeeper"; return; fi
  # argv 精确验证 hook 真写入(不只验 JSON 可读)
  if "$PY" -c "import json,sys;d=json.load(open(sys.argv[1]));c=sys.argv[2];sys.exit(0 if any(h.get('command')==c for g in d.get('hooks',{}).get('Stop',[]) for h in (g.get('hooks') or [])) else 1)" "$f" "$CHECK" 2>/dev/null; then
    say "  ✓ Claude Code: Stop hook → .claude/settings.json(已校验写入)"
  else say "  ✗ Claude Code: hook 未确认写入,检查 $f.bak.goalkeeper"; fi
}
inject_kimi() {
  # Kimi 只读全局 ~/.kimi/config.toml,--config-file 是替换不合并 —— 项目级它不读,只生成片段+提示。
  local f="$TARGET/.kimi/goalkeeper-hook.toml"; mkdir -p "$TARGET/.kimi"
  printf '# 追加到全局 ~/.kimi/config.toml(Kimi 不读项目级 config)\n[[hooks]]\nevent = "Stop"\ncommand = "%s"\ntimeout = 60\n' "$(esc "$CHECK")" > "$f"
  say "  ⚠ Kimi: 生成 hook 片段 → .kimi/goalkeeper-hook.toml"
  say "      Kimi 只读全局 config,请手动追加到 ~/.kimi/config.toml(和 model 配置一起,别覆盖)。"
}
inject_kiro() {
  # Kiro 的 Stop hook 是 observe-only、不能 block(只有 PreToolUse/UserPromptSubmit/PreTaskExec 能),
  # 没法用它"拦住不让停"。不装无效配置,如实降级提示。
  say "  ✗ Kiro: 它的 Stop hook 不能 block,无法做 goal mode(只有 PreToolUse 等能拦)。"
  say "      若 kiro-cli 支持 headless,可走 wrapper 档:.goalkeeper/goalkeeper-run.sh \"任务\"(设 AGENT_CMD)。"
}
inject_opencode() {
  mkdir -p "$TARGET/.opencode/plugins"   # 官方加载目录是复数 plugins/
  must_cp "$GK_SRC/adapters/opencode/goalkeeper.js" "$TARGET/.opencode/plugins/goalkeeper.js" \
    && say "  🧪 opencode: 插件 → .opencode/plugins/goalkeeper.js(实验性,续轮 API 待真机核对,见 TESTING.md)" \
    || say "  ✗ opencode: 插件拷贝失败"
}
inject_pi() {
  mkdir -p "$TARGET/.pi/extensions"
  must_cp "$GK_SRC/adapters/pi/goalkeeper.ts" "$TARGET/.pi/extensions/goalkeeper.ts" \
    && say "  🧪 pi: 扩展 → .pi/extensions/goalkeeper.ts(实验性,用 \`pi -e\` 加载,API 待核对)" \
    || say "  ✗ pi: 扩展拷贝失败"
}
wrapper_note() {
  say "  ✓ $1: 走 wrapper → .goalkeeper/goalkeeper-run.sh \"任务描述\"(先在 goal.sh 设 AGENT_CMD)"
}
zcode_note() {
  say "  • ZCode: GUI 无 CLI,接不进 hook。用它自带 /goal,或设 ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic 走 Claude Code。"
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
say "  1) 编辑 .goalkeeper/goal.sh —— DONE_CMD 改成你的完成条件(npm test / pytest -q / make check)"
say "  2) 正常启动 agent;每次想停 goalkeeper 跑 DONE_CMD,没过拦回,过了 / 撞预算放行。"
say "  端到端验证某平台见 TESTING.md;目前只有 Claude Code 端到端验证过。"; hr
