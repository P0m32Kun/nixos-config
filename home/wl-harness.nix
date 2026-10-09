{ inputs, ... }:

# ============================================================
# wl-harness：跨设备共享的 agent 层（仓库 git@github.com:P0m32Kun/wl-harness）
#   - pinned 第三方 + vendored skills → ~/.agents/skills（Codex/Pi/zcode/agy 共用一份）
#   - Orca pick-agent 路由 skill
#   - codegraph MCP「只增不改」合并进 ~/.codex/config.toml、~/.pi/agent/mcp.json、
#     ~/.zcode/cli/config.json（文件仍是 agent 自管的普通文件，符合决策 0001）
# 不装任何二进制：codex/zcode/orca-ide/codegraph 仍由本仓库 nixpkgs/overlay 提供，
# pi 仍是 npm -g 自管。详见 docs/decisions/0004-wl-harness-shared-agent-layer.md
# ============================================================
{
  imports = [ inputs.wl-harness.homeManagerModules.default ];

  wl-harness.enable = true;
  # skill 清单来自 wl-harness/shared/skills/manifest.txt（与 Mac 同一份）。
  # agent-skills 的 12 个 skill 已 vendored 进 wl-harness（shared/skills/vendored），
  # 统一链到 ~/.agents/skills，Codex/Pi/zcode/agy 都只读这一份；不再排除任何同名 skill。
  # 不要再用 agent-skills 的 `kun init` / `agent-skills install` 往 ~/.codex/skills、~/.pi/agent/skills 装副本（会重复）。
  # agy（Antigravity CLI，前端车道）：二进制按决策 0001 走官方安装脚本自管（~/.local/bin/agy，经 nix-ld 运行）。
  # 模块只在 ~/.gemini 存在时「只增不改」写 ~/.gemini/config/skills.json 与 mcp_config.json。
  # 其他可覆盖项见 wl-harness/nixos/hm-module.nix：
  # wl-harness.mcp.codegraph.enable = false;
}
