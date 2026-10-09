{ inputs, ... }:

# ============================================================
# wl-harness：跨设备共享的 agent 层（仓库 git@github.com:P0m32Kun/wl-harness）
#   - pinned 第三方 skills → ~/.agents/skills（Codex/Pi）+ ~/.zcode/skills（zcode）
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
  # 这些同名 skill 已由 agent-skills（~/.local/share/agent-skills，吸收自 mattpocock/skills）
  # 装进 ~/.codex/skills 与 ~/.pi/agent/skills，本机不再重复链接，避免同名冲突。
  wl-harness.skills.exclude = [ "code-review" "grill-with-docs" "grilling" "tdd" "wayfinder" ];
  # agy（Antigravity CLI，前端车道）：二进制按决策 0001 走官方安装脚本自管（~/.local/bin/agy，经 nix-ld 运行）。
  # 模块只在 ~/.gemini 存在时「只增不改」写 ~/.gemini/config/skills.json 与 mcp_config.json。
  # 额外把 agent-skills 管理的 ~/.codex/skills 加进 agy 的 skills.json，使 agy 与 Codex/Pi 看到同一批 skill。
  wl-harness.antigravity.extraSkillDirs = [ ".codex/skills" ];
  # 其他可覆盖项见 wl-harness/nixos/hm-module.nix：
  # wl-harness.mcp.codegraph.enable = false;
}
