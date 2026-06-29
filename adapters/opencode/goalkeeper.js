// goalkeeper · opencode 适配(档2 · 插件)— 🧪 实验性,未在真 opencode 端到端验证
// 机制:监听 session.idle 事件,spawn .goalkeeper/check-goal.sh 判定;未达成它输出
//       {"decision":"block","reason":...},插件把 reason 当续轮 prompt 投回会话。
//
// 装到: <项目>/.opencode/plugins/goalkeeper.js(复数 plugins/,install.sh 自动做)。
// ⚠ 续轮 API client.session.prompt 的方法签名,官方 plugins 文档未明确记录;这里按 SDK 形状 +
//   现成 goal 插件推断,落地前务必在真 opencode 上核对一次 —— 见 TESTING.md。
//   参考: https://github.com/prevalentWare/opencode-goal-plugin
import { execFileSync } from "node:child_process";
import { join } from "node:path";

export const Goalkeeper = async ({ client, directory }) => ({
  // opencode 是一个 event 处理器,内部按 event.type 分发(不是顶层 "session.idle" 键)
  event: async ({ event }) => {
    if (!event || event.type !== "session.idle") return;
    const dir = directory || process.cwd();
    const sessionID = event?.properties?.sessionID || event?.sessionID;

    let out = "";
    try {
      out = execFileSync(join(dir, ".goalkeeper", "check-goal.sh"), { encoding: "utf8", input: "" });
    } catch (e) {
      // 守门员自身坏了:不静默,记一笔让用户能发现(放行,避免 agent 卡死)
      console.error("[goalkeeper] check-goal.sh 执行失败,本轮不拦截:", (e && e.message) || e);
      return;
    }
    if (!out.trim()) return; // 无输出 = 已达成或撞刹车,放行

    let decision;
    try { decision = JSON.parse(out); } // 用 JSON.parse,不用正则(reason 里含 "}  会截断)
    catch { console.error("[goalkeeper] 判定输出非 JSON,跳过:", out); return; }
    if (!decision || decision.decision !== "block" || !decision.reason) return;
    if (!sessionID) { console.error("[goalkeeper] 拿不到 sessionID,无法续轮"); return; }

    const parts = [{ type: "text", text: decision.reason }];
    try {
      await client.session.prompt({ path: { id: sessionID }, body: { parts } });
    } catch (e) {
      console.error("[goalkeeper] 续轮失败(API 签名可能不符,见 TESTING.md):", (e && e.message) || e);
    }
  },
});
