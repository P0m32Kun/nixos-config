{ config, lib, pkgs, ... }:

# ============================================================
# agent-skills：自有 skill 平台（pi / codex / hermes 三宿主）
# ------------------------------------------------------------
# 集成方式（NixOS + home-manager 接管，遵循仓库 docs/nixos.md）：
#   - 源码：flake 输入 agent-skills（git+ssh，见 flake.nix），
#     仓库自带 flake（overlays.default 纯别名）打成 store 包，
#     `kun`/`agent-skills` 命令由 home.packages 提供（进 HM profile）
#   - 部署：激活时跑 `kun init --layout home-manager`，把三宿主 skills
#     与策略写入 ~/.local/state/agent-skills/（可变，CLI 可写）；
#     kun init 只读 store 包，不依赖 git checkout
#   - host 可见路径是 out-of-store 符号链接：home-manager 只声明指针，
#     真身在 state 目录（sync-policy 要求目标是普通文件，拒绝 store 链接）
#   - 日常更新：agent-skills 仓库 commit+push 后
#       nix flake update agent-skills && ./rebuild.sh
#     即完成"拉新源码 + 重建 CLI + 重新部署"，不用 kun update
#     （store 里的 kun 无 git checkout，kun update 会报 KUN_UPDATE_SOURCE）
#   - 首次部署前无需手工建目录：kun init 自建 state 目录
# ============================================================
let
  stateDir = "${config.home.homeDirectory}/.local/state/agent-skills";
  link = config.lib.file.mkOutOfStoreSymlink;
in
{
  # ---- kun / agent-skills 命令（store 包，随 flake 输入版本更新） ----
  home.packages = [ pkgs.agent-skills ];

  # ---- 激活时用新版本 kun 重新部署三宿主 skills + 策略到 state 目录 ----
  # （entryBefore linkGeneration：先有真身文件，再生成 out-of-store 链接；
  #   fail-fast：某次提交校验失败则 switch 中止，旧 generation 保持生效；
  #   想预览可先跑 `kun init --check --layout home-manager`）
  home.activation.deployAgentSkills = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    ${pkgs.agent-skills}/bin/kun init --layout home-manager
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

  # ---- 只读检查三宿主部署状态（替代旧 agent-skills-sync 的检查角色） ----
  programs.fish.functions.kun-doctor = {
    description = "只读检查 agent-skills 三宿主部署状态（home-manager 布局）";
    body = ''
      kun doctor --layout home-manager
    '';
  };
}
