{ config, lib, pkgs, ... }:

# ============================================================
# 指纹识别（fprintd + libfprint）
# ------------------------------------------------------------
# 说明：
#   - services.fprintd 启用守护进程（libfprint 驱动库随依赖自动带入）
#   - 本机传感器：1c7a:05aa EgisTec ETU906Axx，libfprint 官方尚未支持
#     （freedesktop issue #776 仍为 open，无 MR），装上后 fprintd 会报
#     "No devices available"，等官方支持合入 + flake update 后即可用
#   - fprintd-tod 需要厂商私有驱动（elan/goodix 等），本传感器不适用，不启用
# ============================================================
{
  # ============ fprintd 守护进程 ============
  services.fprintd.enable = true;

  # ============ PAM：允许指纹认证 ============
  # 覆盖当前运行中的 GDM/GNOME 与配置里的 Hyprland/SDDM 两种场景
  security.pam.services.login.fprintAuth = true;
  security.pam.services.sddm.fprintAuth = true;
  security.pam.services.gdm-password.fprintAuth = true;
  security.pam.services.sudo.fprintAuth = true;

  # ============ 客户端工具 ============
  # fprintd-enroll 录入指纹 / fprintd-verify 验证 / fprintd-list 查看已录入
  environment.systemPackages = [ pkgs.fprintd ];
}
