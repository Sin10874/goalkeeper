// goalkeeper · opencode 适配(档2 · 插件)
// 机制:监听 session.idle(agent 跑完一轮变空闲,= Claude Code Stop 的等价物),
//       spawn .goalkeeper/check-goal.sh 判定;未达成它会输出 {"decision":"block","reason":...},
//       插件就用 client.session.promptAsync() 把 reason 当续轮 prompt 投回,强制再跑一轮。
//
// 装到: <项目>/.opencode/plugin/goalkeeper.js,并在 opencode.json 注册(install.sh 自动做)。
// 注意:opencode 的程序化续轮 API(promptAsync)以官方 plugins 文档 + 现成 goal 插件源码为准,
//       见 https://github.com/prevalentWare/opencode-goal-plugin —— 落地前核对一遍方法签名。
import { execFileSync } from "node:child_process";
import { join } from "node:path";

export const Goalkeeper = async ({ client, directory }) => ({
  "session.idle": async ({ sessionID }) => {
    const dir = directory || process.cwd();
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
    const reason = m[1];
    const parts = [{ type: "text", text: reason }];
    try {
      await client.session.promptAsync({ sessionID, parts });
    } catch {
      await client.session.prompt({ sessionID, parts }); // 老版本回退
    }
  },
});
