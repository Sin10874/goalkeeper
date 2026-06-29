#!/usr/bin/env bash
# goalkeeper 自动化测试 —— 判定核心 / JSON 转义 / 刹车 / install,全部不依赖真 agent,可 CI 跑。
# 真 agent 端到端验证(Claude Code 等)不在这里,见 TESTING.md。
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)" || { echo "mktemp 失败"; exit 1; }; [ -n "$TMP" ] || exit 1; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }

# 装一个 mock 项目:DONE_CMD / MAX_TURNS / MAX_SECONDS 由参数定
setup(){
  rm -rf "$TMP/p"; mkdir -p "$TMP/p/.goalkeeper"
  cp "$ROOT/core/check-goal.sh" "$TMP/p/.goalkeeper/check-goal.sh"; chmod +x "$TMP/p/.goalkeeper/check-goal.sh"
  { printf 'GOAL="测试目标"\n'; printf 'DONE_CMD=%s\n' "$1"; printf 'MAX_TURNS=%s\n' "$2"; printf 'MAX_SECONDS=%s\n' "$3"; } > "$TMP/p/.goalkeeper/goal.sh"
}
run(){ ( cd "$TMP/p" && ./.goalkeeper/check-goal.sh </dev/null 2>/dev/null ); }
status(){ cat "$TMP/p/.goalkeeper/.status" 2>/dev/null; }

echo "== 判定四路径 =="
setup '"false"' 99 0; out=$(run)
[[ "$out" == *'"decision":"block"'* ]] && ok "未达成 → 拦回 block" || no "未达成应拦回"
[[ "$(status)" == active ]] && ok "未达成 → 状态 active" || no "状态应 active"

setup '"true"' 99 0; out=$(run)
[[ -z "$out" && "$(status)" == complete ]] && ok "达成 → 放行(无输出)+ complete" || no "达成应放行+complete"

setup '"false"' 2 0; run >/dev/null; run >/dev/null; run >/dev/null
[[ "$(status)" == turns_limited ]] && ok "撞轮数 → turns_limited" || no "轮数刹车"

setup '"false"' 99 10; echo $(( $(date +%s) - 100 )) > "$TMP/p/.goalkeeper/.started"; run >/dev/null
[[ "$(status)" == time_limited ]] && ok "撞时间预算 → time_limited" || no "时间刹车"

echo "== JSON 转义(防引号/反斜杠破坏 block JSON)=="
rm -rf "$TMP/p"; mkdir -p "$TMP/p/.goalkeeper"
cp "$ROOT/core/check-goal.sh" "$TMP/p/.goalkeeper/check-goal.sh"; chmod +x "$TMP/p/.goalkeeper/check-goal.sh"
printf '%s\n' 'GOAL="带 \"引号\" 和 \\反斜杠 的目标"' 'DONE_CMD="grep \"PASS\" out"' 'MAX_TURNS=9' 'MAX_SECONDS=0' > "$TMP/p/.goalkeeper/goal.sh"
out=$(run)
if printf '%s' "$out" | python3 -c "import sys,json;json.load(sys.stdin)" 2>/dev/null; then ok "含引号/反斜杠 → 仍是合法 JSON"; else no "JSON 转义(输出: $out)"; fi

echo "== JSON 控制字符全覆盖(\\v \\x01 \\x1f 等 C0)=="
rm -rf "$TMP/p"; mkdir -p "$TMP/p/.goalkeeper"
cp "$ROOT/core/check-goal.sh" "$TMP/p/.goalkeeper/check-goal.sh"; chmod +x "$TMP/p/.goalkeeper/check-goal.sh"
printf 'GOAL=$(printf "a\\013b\\001c\\037d")\nDONE_CMD="false"\nMAX_TURNS=9\nMAX_SECONDS=0\n' > "$TMP/p/.goalkeeper/goal.sh"
out=$(run)
if printf '%s' "$out" | python3 -c "import sys,json;json.load(sys.stdin)" 2>/dev/null; then ok "含 C0 控制字符 → 仍合法 JSON"; else no "JSON 控制字符未全覆盖"; fi

echo "== 防'只拦一轮'回归(stop_hook_active 不应放行)=="
setup '"false"' 2 0
for _ in 1 2 3; do printf '{"stop_hook_active":true}' | ( cd "$TMP/p" && ./.goalkeeper/check-goal.sh ) >/dev/null 2>&1; done
[[ "$(status)" == turns_limited ]] && ok "带 stop_hook_active 仍持续拦到刹车(旧 bug 会第2次就放行)" || no "stop_hook_active 不应让它只拦一轮"

echo "== install 文件生成(fake claude in PATH)=="
mkdir -p "$TMP/bin"; printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/claude"; chmod +x "$TMP/bin/claude"
HT="$TMP/home"; mkdir -p "$HT"
PATH="$TMP/bin:$PATH" GOALKEEPER_TARGET="$HT" GOALKEEPER_PICK=1 bash "$ROOT/install.sh" >/dev/null 2>&1
[[ -f "$HT/.goalkeeper/check-goal.sh" ]] && ok "install → .goalkeeper/check-goal.sh" || no "install 核心脚本"
[[ -f "$HT/.claude/settings.json" ]] && ok "install → .claude/settings.json" || no "install claude 配置"
if python3 -c "import json;d=json.load(open('$HT/.claude/settings.json'));assert d['hooks']['Stop'][0]['hooks'][0]['type']=='command'" 2>/dev/null; then
  ok "settings.json 是合法的嵌套 Stop hook"; else no "settings.json 结构"; fi

echo "== DONE_CMD 超时(防卡死,macOS 无 timeout 也要生效)=="
setup '"sleep 30"' 9 0; echo 'DONE_TIMEOUT=2' >> "$TMP/p/.goalkeeper/goal.sh"
s=$(date +%s); run >/dev/null; el=$(( $(date +%s) - s ))
[ "$el" -lt 12 ] && ok "DONE_CMD 卡死被超时打断(${el}s,没卡满 30s)" || no "DONE_CMD 超时未生效(${el}s)"

echo "== 纯 bash 超时 fallback(强制无 timeout 命令,覆盖 macOS/CI 路径)=="
setup '"sleep 30"' 9 0; echo 'DONE_TIMEOUT=2' >> "$TMP/p/.goalkeeper/goal.sh"
s=$(date +%s); ( cd "$TMP/p" && GK_FORCE_BASH_TIMEOUT=1 ./.goalkeeper/check-goal.sh </dev/null >/dev/null 2>&1 ); el=$(( $(date +%s) - s ))
[ "$el" -lt 12 ] && ok "强制 bash fallback 也能超时打断(${el}s)" || no "bash fallback 超时(${el}s)"

echo "== install opencode 目录是复数 plugins/(防回归 plugin/)=="
PYDIR="$(dirname "$(command -v python3 || echo /usr/bin/python3)")"
mkdir -p "$TMP/ocbin"; printf '#!/bin/sh\nexit 0\n' > "$TMP/ocbin/opencode"; chmod +x "$TMP/ocbin/opencode"
HO="$TMP/ochome"; mkdir -p "$HO"
PATH="$TMP/ocbin:$PYDIR:/usr/bin:/bin" GOALKEEPER_TARGET="$HO" GOALKEEPER_PICK=1 bash "$ROOT/install.sh" >/dev/null 2>&1
[ -f "$HO/.opencode/plugins/goalkeeper.js" ] && ok "install → .opencode/plugins/(复数)" || no "opencode 应装到复数 plugins/"

echo "== install 自动推断 DONE_CMD(A 版:不让用户手写)=="
HN="$TMP/nodehome"; mkdir -p "$HN"; printf '{"scripts":{"test":"jest"}}' > "$HN/package.json"
PATH="$TMP/bin:$PATH" GOALKEEPER_TARGET="$HN" GOALKEEPER_PICK=1 bash "$ROOT/install.sh" >/dev/null 2>&1
grep -q 'DONE_CMD="npm test"' "$HN/.goalkeeper/goal.sh" && ok "node 项目 → 自动推断 DONE_CMD=npm test 写进 goal.sh" || no "install 未自动推断 DONE_CMD"

echo
echo "─────────────────────────────"
printf '结果: \033[32m%d passed\033[0m, ' "$PASS"
[ "$FAIL" -eq 0 ] && printf '\033[32m%d failed\033[0m\n' "$FAIL" || printf '\033[31m%d failed\033[0m\n' "$FAIL"
[ "$FAIL" -eq 0 ]
