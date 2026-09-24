{ config, lib, pkgs, ... }:

{
  # ============ Tailscale（Mesh VPN） ============
  # 启用后由 nixpkgs 模块提供：
  #   - tailscaled.service（常驻守护进程，NetworkManager-wait-online 之后启动）
  #   - tailscale CLI（自动进 environment.systemPackages）
  #
  # 登录：认证是交互式的（浏览器打开登录 URL 授权），密钥类不进 nix store：
  #   sudo tailscale up
  #   tailscale status
  # 认证状态保存在 /var/lib/tailscale（普通文件，由 tailscaled 自管）。
  # 本机 networking.firewall.enable = false，故不设 openFirewall。
  #
  # 后续按需开启（需要时再取消注释）：
  #   - 使用出口节点 / 接受子网路由：useRoutingFeatures = "client";
  #   - 作为子网路由或出口节点转发：useRoutingFeatures = "server";
  #   - 免 sudo 执行 tailscale 命令（imperative，非 nix 管理）：
  #       sudo tailscale set --operator=kun
  services.tailscale.enable = true;
}
