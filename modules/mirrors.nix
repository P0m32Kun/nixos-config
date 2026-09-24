{ config, lib, pkgs, ... }:

{
  # ============ 国内镜像源（清华 TUNA） ============
  # 本机从 TUNA 镜像拉取二进制缓存，官方 cache.nixos.org 作为兜底
  nix.settings = {
    # 二进制缓存：优先 TUNA，失败时自动回退官方
    substituters = lib.mkForce [ # mkForce：去掉 NixOS 默认附加导致的重复 cache.nixos.org
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
      "https://cache.nixos.org"
      # noctalia 官方 Cachix（v5 C++ 版，避免本地编译）
      "https://noctalia.cachix.org"
    ];
    # TUNA 镜像代理的是官方缓存，使用官方密钥即可
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
    # 启用 flakes 与 nix 命令（GitHub 管理配置的基础）
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  # ============ 网络代理（本机 127.0.0.1:7892） ============
  # 让 nix-daemon 的下载（github tarball、PyPI、TUNA 镜像等）走代理。
  # 机制：fetchurl 把 proxy 变量与 NIX_CURL_FLAGS 声明为 impureEnvVars，
  #       nix 从 **daemon** 的环境取值注入构建沙箱（实测：客户端 env 无效）。
  #       所以代理只需在这里配，不需要 overlay 包裹 fetchurl。
  # 没有代理时删掉这个 block 即可。
  systemd.services.nix-daemon.environment = {
    https_proxy = "http://127.0.0.1:7892";
    http_proxy = "http://127.0.0.1:7892";
    all_proxy = "http://127.0.0.1:7892";
    no_proxy = "localhost,127.0.0.1";
    # 慢连接快速失败：fetchurl 的 curl 只有 --connect-timeout，没有速度超时，
    # 半死连接（实测 326 B/s）会无限挂起而不触发重试。持续 <1KB/s 达 60s 即中止，
    # 由 nix 的 download-attempts=5 重试（curl 侧 -C - 续传）。
    NIX_CURL_FLAGS = "--speed-limit 1000 --speed-time 60";
  };

  # 换中科大 USTC：把 substituters 第一条改为
  #   "https://mirrors.ustc.edu.cn/nix-channels/store"
  # （nixpkgs 源在 flake.nix 中同步修改）
}
