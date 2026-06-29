// goalkeeper · pi 适配(档2 · 扩展)
// 机制:监听 agent_end(整个 agent 循环跑完,最贴"agent 想停"的语义),
//       spawn .goalkeeper/check-goal.sh 判定;未达成它会输出 {"decision":"block","reason":...},
//       插件就用 pi.sendUserMessage(reason, { deliverAs: "followUp" }) 等 agent idle 后投回续轮。
//
// 装到全局: pi install npm:goalkeeper-pi  或开发期 pi -e ./goalkeeper.ts
// 参考现成实现: https://github.com/code-yeongyu/pi-goal —— 落地前核对方法签名。
import { execFileSync } from "node:child_process";
import { join } from "node:path";

export default function (pi: any) {
  pi.on("agent_end", async (_event: any, ctx: any) => {
    const dir = (ctx && ctx.cwd) || process.cwd();
    let out = "";
    try {
      out = execFileSync(join(dir, ".goalkeeper", "check-goal.sh"), {
        encoding: "utf8",
        input: "",
      });
    } catch {
      return; // 脚本不存在 / 出错 -> 不干预,放行
    }
    const m = out.match(/"reason":"(.+?)"\}/);
    if (!m) return; // 无 block 输出 = 已达成或撞刹车,放行
    pi.sendUserMessage(m[1], { deliverAs: "followUp" });
  });
}
