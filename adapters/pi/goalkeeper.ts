// goalkeeper · pi 完整 goal 扩展(A 版)
//
// 同 opencode 思路:退出码硬判定(跑 DONE_CMD)+ 自动推断完成条件 + agent_end 续轮,治"LLM 自报完成"的假绿。
// 续轮基于 pi-goal 实证(sendMessage triggerTurn / 旧版 sendUserMessage)。
// ⚠ pi 的 /goal 命令注册 API 我未在真 pi 上确认 —— /goal 那段标注待核对,核心续轮不依赖它(没装命令也能用:
//   install 时自动推断写好 .goalkeeper/goal.sh,你正常干活,agent_end 时就会退出码判定 + 续轮)。
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";

// 从项目自动推断完成条件命令(同 opencode adapter)
function inferDoneCmd(root: string): string {
  try {
    if (existsSync(join(root, "package.json"))) {
      const pkg = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
      if (pkg.scripts && pkg.scripts.test) {
        if (existsSync(join(root, "pnpm-lock.yaml"))) return "pnpm test";
        if (existsSync(join(root, "yarn.lock"))) return "yarn test";
        return "npm test";
      }
    }
    if (existsSync(join(root, "pyproject.toml")) || existsSync(join(root, "pytest.ini"))) return "pytest -q";
    if (existsSync(join(root, "Cargo.toml"))) return "cargo test";
    if (existsSync(join(root, "go.mod"))) return "go test ./...";
    if (existsSync(join(root, "Makefile"))) {
      const mk = readFileSync(join(root, "Makefile"), "utf8");
      if (/^test:/m.test(mk)) return "make test";
      if (/^check:/m.test(mk)) return "make check";
    }
  } catch { /* 推不出就空,提示手填 */ }
  return "";
}

// 跑判定核心:退出码 0 = 达成(无输出);否则取 block 的 reason
function judge(gkDir: string): { done: boolean; reason?: string } {
  try {
    const out = execFileSync(join(gkDir, "check-goal.sh"), { encoding: "utf8", input: "" }).trim();
    if (!out) return { done: true };
    const d = JSON.parse(out);
    return { done: false, reason: d.reason };
  } catch (e: any) {
    console.error("[goalkeeper] check-goal 执行失败,本轮不拦截:", (e && e.message) || e);
    return { done: true };
  }
}

function setGoal(gkDir: string, objective: string, doneCmd: string) {
  mkdirSync(gkDir, { recursive: true });
  writeFileSync(
    join(gkDir, "goal.sh"),
    `GOAL=${JSON.stringify(objective)}\nDONE_CMD=${JSON.stringify(doneCmd || "false")}\nMAX_TURNS=30\nMAX_SECONDS=0\nDONE_TIMEOUT=120\n`,
  );
}

export default function (pi: any) {
  let active = false; // 防重入

  // 核心:agent_end(整轮跑完想停)时跑退出码判定,没达成续轮
  pi.on("agent_end", async (_event: any, ctx: any) => {
    const dir = (ctx && ctx.cwd) || process.cwd();
    const gk = join(dir, ".goalkeeper");
    if (!existsSync(join(gk, "goal.sh")) || active) return;
    active = true;
    try {
      const j = judge(gk);
      if (j.done) return; // 达成 / 撞刹车 → 放行
      // pi-goal 实证:sendMessage(triggerTurn);旧版回退 sendUserMessage
      if (typeof pi.sendMessage === "function") {
        pi.sendMessage({ content: j.reason, display: true }, { deliverAs: "followUp", triggerTurn: true });
      } else if (typeof pi.sendUserMessage === "function") {
        pi.sendUserMessage(j.reason, { deliverAs: "followUp" });
      }
    } catch (e: any) {
      console.error("[goalkeeper] 续轮失败:", (e && e.message) || e);
    } finally {
      active = false;
    }
  });

  // /goal <一句话> 命令 —— ⚠ pi 的命令注册 API 待真机核对;不行也不影响核心(见文件头)。
  if (typeof pi.registerCommand === "function") {
    pi.registerCommand("goal", async (args: string, ctx: any) => {
      const dir = (ctx && ctx.cwd) || process.cwd();
      const gk = join(dir, ".goalkeeper");
      const a = (args || "").trim();
      if (!a || a === "status") return judge(gk).done ? "goalkeeper:无活动目标或已达成。" : "goalkeeper 进行中。";
      if (["clear", "stop", "off", "cancel"].includes(a)) {
        try { writeFileSync(join(gk, "goal.sh"), ""); } catch { /* ignore */ }
        return "goalkeeper:目标已清除。";
      }
      const doneCmd = inferDoneCmd(dir);
      setGoal(gk, a, doneCmd);
      return doneCmd
        ? `goalkeeper:目标已设,完成判定 = \`${doneCmd}\` 退出码 0(硬把关,不是你说做完就算)。开始:${a}`
        : `goalkeeper:目标已设,但没推断出完成条件,请在 .goalkeeper/goal.sh 填 DONE_CMD。开始:${a}`;
    });
  }
}
