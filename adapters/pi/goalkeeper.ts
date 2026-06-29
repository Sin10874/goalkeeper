// goalkeeper · pi 适配(档2 · 扩展)— 🧪 实验性,未在真 pi 端到端验证
// 机制:监听 agent_end(整个 agent 循环跑完),spawn .goalkeeper/check-goal.sh 判定;
//       未达成用 sendMessage(.., {triggerTurn:true, deliverAs:"followUp"}) 等 idle 后投回续轮。
//
// 装到全局: pi install npm:goalkeeper-pi  或开发期 pi -e ./goalkeeper.ts
// ⚠ sendMessage 的方法签名按现成 pi-goal 推断,落地前核对 —— 见 TESTING.md。
//   参考: https://github.com/code-yeongyu/pi-goal
import { execFileSync } from "node:child_process";
import { join } from "node:path";

export default function (pi: any) {
  pi.on("agent_end", async (_event: any, ctx: any) => {
    const dir = (ctx && ctx.cwd) || process.cwd();

    let out = "";
    try {
      out = execFileSync(join(dir, ".goalkeeper", "check-goal.sh"), { encoding: "utf8", input: "" });
    } catch (e: any) {
      // 守门员坏了:不静默,记一笔(放行,避免 agent 卡死)
      console.error("[goalkeeper] check-goal.sh 执行失败,本轮不拦截:", (e && e.message) || e);
      return;
    }
    if (!out.trim()) return; // 无输出 = 已达成或撞刹车,放行

    let decision: any;
    try { decision = JSON.parse(out); } // JSON.parse,不用正则(reason 含 "} 会截断)
    catch { console.error("[goalkeeper] 判定输出非 JSON,跳过:", out); return; }
    if (!decision || decision.decision !== "block" || !decision.reason) return;

    try {
      // pi-goal 参考实现用 sendMessage(...{ triggerTurn, deliverAs:"followUp" });旧版回退 sendUserMessage
      if (typeof pi.sendMessage === "function") {
        pi.sendMessage({ content: decision.reason, display: true }, { deliverAs: "followUp", triggerTurn: true });
      } else if (typeof pi.sendUserMessage === "function") {
        pi.sendUserMessage(decision.reason, { deliverAs: "followUp" }); // 旧版 pi 回退
      }
    } catch (e: any) { console.error("[goalkeeper] 续轮失败(API 签名可能不符,见 TESTING.md):", (e && e.message) || e); }
  });
}
