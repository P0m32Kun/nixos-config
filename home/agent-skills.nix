{ config, lib, pkgs, ... }:

# ============================================================
# agent-skills：自有 skill 平台（pi / codex / hermes 三宿主）
# ------------------------------------------------------------
# 集成方式遵循仓库 docs/nixos.md（私有仓库，不能进 nix store）：
#   - 真实文件（CLI 可写）：~/.local/state/agent-skills/
#       hosts/{pi,codex,hermes}/{AGENTS.md,SOUL.md}
#       skills/{pi,codex,hermes}/
#   - home-manager 只声明 out-of-store 符号链接，指向真实文件；
#     sync-policy 要求目标是普通文件（拒绝 nix store 符号链接）
#   - 仓库本体 clone 到 ~/.local/share/agent-skills（git 更新），
#     依赖用 `npm ci` 装（ajv/yaml），首次一次性执行：
#       git clone git@github.com:P0m32Kun/agent-skills.git ~/.local/share/agent-skills
#       cd ~/.local/share/agent-skills && npm ci
#   - 日常同步：`agent-skills-sync`（先只读检查，APPLY=1 才写入）
# ============================================================
let
  stateDir = "${config.home.homeDirectory}/.local/state/agent-skills";
  link = config.lib.file.mkOutOfStoreSymlink;
in
{
  # ---- 激活前建好 state 目录骨架（保证 out-of-store 链接目标存在）----
  home.activation.createAgentSkillsState = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    mkdir -p "${stateDir}/hosts/pi" "${stateDir}/hosts/codex" "${stateDir}/hosts/hermes"
    mkdir -p "${stateDir}/skills/pi" "${stateDir}/skills/codex" "${stateDir}/skills/hermes"
    ${pkgs.coreutils}/bin/touch \
      "${stateDir}/hosts/pi/AGENTS.md" \
      "${stateDir}/hosts/codex/AGENTS.md" \
      "${stateDir}/hosts/hermes/SOUL.md"
  '';

  # ---- 宿主可见路径 → 真实文件（out-of-store 链接） ----
  home.file = {
    ".pi/agent/AGENTS.md".source = link "${stateDir}/hosts/pi/AGENTS.md";
    ".codex/AGENTS.md".source = link "${stateDir}/hosts/codex/AGENTS.md";
    ".hermes/SOUL.md".source = link "${stateDir}/hosts/hermes/SOUL.md";

    ".pi/agent/skills".source = link "${stateDir}/skills/pi";
    ".codex/skills".source = link "${stateDir}/skills/codex";
    ".hermes/skills".source = link "${stateDir}/skills/hermes";
  };

  # ---- 同步函数（等价 docs/nixos.md 的 profiles/local/sync.sh） ----
  programs.fish.functions.agent-skills-sync = {
    description = "同步 agent-skills（build + install + sync-policy 三宿主）";
    body = ''
      set -l root "$HOME/.local/share/agent-skills"
      set -l state "$HOME/.local/state/agent-skills"
      if not test -d "$root"
        echo "agent-skills 仓库不存在，先执行：" >&2
        echo "  git clone git@github.com:P0m32Kun/agent-skills.git $root" >&2
        echo "  cd $root && npm ci" >&2
        return 1
      end
      node "$root/src/cli/index.js" build "$root"
      for host in pi codex hermes
        set -l policy "$state/hosts/$host/AGENTS.md"
        if test "$host" = hermes
          set policy "$state/hosts/hermes/SOUL.md"
        end
        node "$root/src/cli/index.js" install "$host" "$state/skills/$host" "$root"
        if set -q APPLY
          node "$root/src/cli/index.js" sync-policy "$host" "$root" --target "$policy" --apply
        else
          node "$root/src/cli/index.js" sync-policy "$host" "$root" --target "$policy"
        end
      end
      echo ""
      echo "检查通过后，用 APPLY=1 agent-skills-sync 真正写入策略文件"
    '';
  };
}
