{ config, lib, pkgs, ... }:

# ============================================================
# sudo 规则
# ------------------------------------------------------------
# 目的：kun（本机唯一 wheel 成员）的 sudo 全免密，
#       供 pi 等自动化工具免密执行 `sudo nixos-rebuild` 等管理命令。
# 信任模型：能登录 kun = 能拿到 root；能改本仓库 flake = 能拿到 root。
#       这是有意为之（agent 需要管理系统），不是漏洞。
#       决策记录与残余风险见 docs/decisions/0003-passwordless-sudo.md。
# ============================================================
{
  # ==== 核心开关：wheel 组免密 sudo ====
  # 本机 wheel 成员只有 kun（modules/users/kun.nix），故等价于「kun 免密」。
  # 副作用：日后若新增 wheel 用户，也会自动继承免密。
  security.sudo.wheelNeedsPassword = false;

  # 下面这条 nixos-rebuild 的 NOPASSWD 规则已被上面的
  # wheelNeedsPassword = false 覆盖（后者是 ALL:ALL），保留无副作用。
  security.sudo.extraRules = [
    {
      users = [ "kun" ];
      commands = [
        {
          # 必须写 /run/current-system/sw/bin/nixos-rebuild 这个稳定路径，
          # 不能写 ${pkgs.nixos-rebuild} 的 store 路径：
          # sudo 按字面路径匹配（不解析符号链接），裸命令 `sudo nixos-rebuild`
          # 经 secure_path 解析到的正是 /run/current-system/sw/bin/nixos-rebuild
          #（软链，每个 generation 都指向当次构建的 nixos-rebuild）。
          # 该二进制由 NixOS 系统默认包提供，稳定存在于每个 generation。
          command = "/run/current-system/sw/bin/nixos-rebuild";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
  # 代理穿透 sudo：nixos-rebuild 前端的 flake 抓取（github 等）也要走代理；
  security.sudo.extraConfig = ''
    Defaults env_keep += "http_proxy https_proxy all_proxy no_proxy"
  '';
}
