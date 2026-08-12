{ config, lib, pkgs, ... }:

{
  # ============ 国内镜像源（清华 TUNA） ============
  # 本机从 TUNA 镜像拉取二进制缓存，官方 cache.nixos.org 作为兜底
  nix.settings = {
    # 二进制缓存：优先 TUNA，失败时自动回退官方
    substituters = [
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
      "https://cache.nixos.org"
    ];
    # TUNA 镜像代理的是官方缓存，使用官方密钥即可
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
    # 启用 flakes 与 nix 命令（GitHub 管理配置的基础）
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  # 换中科大 USTC：把 substituters 第一条改为
  #   "https://mirrors.ustc.edu.cn/nix-channels/store"
  # （nixpkgs 源在 flake.nix 中同步修改）
}
