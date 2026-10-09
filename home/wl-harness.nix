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
  # 其他可覆盖项见 wl-harness/nixos/hm-module.nix：
  # wl-harness.mcp.codegraph.enable = false;
}
