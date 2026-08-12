{ config, lib, pkgs, ... }:

# ============================================================
# sudo 规则
# ------------------------------------------------------------
# 目的：允许 pi 等自动化工具免密执行 `sudo nixos-rebuild`，
#       其余 sudo 命令仍要求密码。
# 信任模型：能改本仓库 flake = 能通过 nixos-rebuild 拿到 root，
#       这是有意为之（agent 需要管理系统），不是漏洞。
# ============================================================
{
  security.sudo.extraRules = [
    {
      users = [ "kun" ];
      commands = [
        {
          command = "${pkgs.nixos-rebuild}/bin/nixos-rebuild";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
