// goalkeeper · opencode 完整 goal 插件(A 版)
//
// 学三个现成实现(watzon / prevalentWare / willytop8)的"壳":
//   /goal <自然语言> 命令 + event/isIdle 被动续轮 + 防重入 Set + 节流。
// 换 goalkeeper 的"芯":
//   完成判定不是让 LLM 自报(那三个都这么干、都会假绿),而是跑 DONE_CMD 看退出码 —— 硬把关。
//   DONE_CMD 从项目自动推断,用户只说一句自然语言目标,不碰配置文件。
//
// 续轮 API 兼容两种:watzon/prevalentWare 用 client.session.promptAsync,willytop8 用 client.session.prompt。
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";

export const Goalkeeper = async ({ client, directory }) => {
  const root = directory || process.cwd();
  const gkDir = join(root, ".goalkeeper");
  const active = new Set();          // 防重入,按 sessionID
  let lastContinueAt = 0;
  const MIN_DELAY_MS = 1500;         // 节流(同 willytop8 默认)

  // 从项目自动推断完成条件命令 —— vibe 的关键:不让用户手写 DONE_CMD
  function inferDoneCmd() {
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
    } catch { /* 推不出就返回空,提示用户填 */ }
    return "";
  }

  // 写 goal 配置:objective 自然语言 + 自动推断的 DONE_CMD(check-goal.sh 会读它)
  function setGoal(objective, doneCmd) {
    mkdirSync(gkDir, { recursive: true });
    const body =
      `GOAL=${JSON.stringify(objective)}\n` +
      `DONE_CMD=${JSON.stringify(doneCmd || "false")}\n` +
      `MAX_TURNS=30\nMAX_SECONDS=0\nDONE_TIMEOUT=120\n`;
    writeFileSync(join(gkDir, "goal.sh"), body);
  }

  // goalkeeper 判定核心:退出码 0 = 达成(check-goal 无输出);否则返回 block 的 reason
  function judge() {
    try {
      const out = execFileSync(join(gkDir, "check-goal.sh"), { encoding: "utf8", input: "" }).trim();
      if (!out) return { done: true };               // 达成或撞刹车 → 放行,不续轮
      const d = JSON.parse(out);                      // {"decision":"block","reason":...}
      return { done: false, reason: d.reason };
    } catch (e) {
      console.error("[goalkeeper] check-goal 执行失败,本轮不拦截:", (e && e.message) || e);
      return { done: true };                          // 守门员坏了 → 放行,别卡死 agent
    }
  }

  const isIdle = (event) =>
    event?.type === "session.idle" ||
    (event?.type === "session.status" && event?.properties?.status?.type === "idle");

  const sidOf = (event) => {
    const p = event?.properties ?? event;
    return p?.sessionID ?? p?.info?.sessionID ?? p?.part?.sessionID;
  };

  async function sendContinue(sessionID, text) {
    const path = { id: sessionID };
    const body = { parts: [{ type: "text", text, synthetic: true }] };
    try { await client.session.promptAsync({ path, body }); }   // watzon/prevalentWare
    catch { await client.session.prompt({ path, body }); }      // willytop8,兼容回退
  }

  return {
    // 注册 /goal 命令
    config: async (config) => {
      config.command ??= {};
      config.command.goal ??= {
        description: "goalkeeper:设目标,跑到 DONE_CMD 退出码 0 才算完(硬把关,治 LLM 自报假绿)",
        template: "$ARGUMENTS",
        agent: "build",
      };
    },

    // 处理 /goal <自然语言> 及子命令
    "command.execute.before": async (input, output) => {
      if (input.command !== "goal") return;
      const args = (input.arguments || "").trim();
      if (!args || args === "status") {
        const j = judge();
        output.parts = [{ type: "text", text: j.done ? "goalkeeper:无活动目标或已达成。" : "goalkeeper 进行中 —— " + j.reason }];
        return;
      }
      if (["clear", "stop", "off", "cancel", "reset"].includes(args)) {
        try { writeFileSync(join(gkDir, "goal.sh"), ""); } catch { /* ignore */ }
        output.parts = [{ type: "text", text: "goalkeeper:目标已清除。" }];
        return;
      }
      // 创建:args = 自然语言目标,DONE_CMD 自动推断
      const doneCmd = inferDoneCmd();
      setGoal(args, doneCmd);
      const note = doneCmd
        ? `完成判定 = \`${doneCmd}\` 退出码 0(我会真跑它,没过就把"还差什么"塞回去让你继续 —— 不是你说做完就算)。`
        : `没从项目推断出完成条件,请在 .goalkeeper/goal.sh 把 DONE_CMD 改成你的(如 npm test / pytest -q),否则退化成无硬把关。`;
      output.parts = [{ type: "text", text: `goalkeeper 目标已设。${note}\n\n现在开始:${args}` }];
    },

    // 空闲时:跑退出码判定,没达成就续轮(防重入 + 节流)
    event: async ({ event }) => {
      if (!isIdle(event)) return;
      const sessionID = sidOf(event);
      if (!sessionID || active.has(sessionID)) return;
      if (!existsSync(join(gkDir, "goal.sh"))) return;     // 没设目标就不管
      if (Date.now() - lastContinueAt < MIN_DELAY_MS) return;
      active.add(sessionID);
      try {
        const j = judge();                                  // 跑 DONE_CMD 看退出码
        if (j.done) return;                                 // 达成 / 撞刹车 → 放行
        lastContinueAt = Date.now();
        await sendContinue(sessionID, j.reason);            // 没达成 → 把"还差什么"投回续轮
      } catch (e) {
        console.error("[goalkeeper] 续轮失败:", (e && e.message) || e);
      } finally {
        setTimeout(() => active.delete(sessionID), MIN_DELAY_MS);
      }
    },
  };
};

// opencode 插件 export(三实现的形状: default { id, server })
export default { id: "goalkeeper", server: Goalkeeper };
