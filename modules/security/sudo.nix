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
}
