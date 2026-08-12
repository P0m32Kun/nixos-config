{ config, lib, pkgs, ... }:

{
  # ============ 用户 kun ============
  # 注意：密码用 `passwd kun` 设置，不保存在配置里
  users.users."kun" = {
    isNormalUser = true;
    description = "kun";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
      # 用户级软件包放这里（也可留空，用 home-manager 更彻底）
    ];
  };
}
