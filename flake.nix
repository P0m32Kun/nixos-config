{
  description = "NixOS 配置（国内镜像 + GitHub 管理）";

  # noctalia 官方 Cachix 二进制缓存（避免本地编译 C++ 项目）
  nixConfig = {
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [ "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=" ];
  };

  inputs = {
    # nixpkgs 用官方 GitHub 的 git 协议（shallow）：锁里是真实 commit + 时间戳，
    # 杜绝 channel tarball「无版本号 + 假时间戳（1980）」造成的锁漂移。
    # 不用 github: 简写——它会走 GitHub REST API，代理共享出口 IP 的匿名限额
    # （60 次/时）经常被打爆（实测 HTTP 403）；git+https 直连没有这个限制。
    # 下载经代理（shell env 或 nix-daemon env，见 decisions/0002）；日常 rebuild
    # 用已缓存的锁不碰网络，只有 `nix flake update` 需要代理在线；
    # 二进制 substituters 仍走 TUNA store 镜像，不受影响。
    # 国内无代理环境的替代（实测 TUNA git 服务晚高峰排队严重，非急勿用）：
    #   "git+https://mirrors.tuna.tsinghua.edu.cn/git/nixpkgs.git?ref=nixos-26.05&shallow=1"
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs.git?ref=nixos-26.05&shallow=1";

    # home-manager：声明式管理用户级配置，随系统一起更新
    # 分支与 nixpkgs 的 26.05 对齐；nixpkgs 跟随主输入
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # noctalia v5（C++ 版，官方当前推荐版本；nixpkgs 里的 noctalia-shell 是
    # v4 Quickshell 旧版，配置不兼容）。用官方 cachix 分支保证二进制缓存命中，
    # 避免本地编译整个 C++ 项目。**不要**加 inputs.nixpkgs.follows，
    # 否则 derivation 改变会导致缓存 miss（见官方文档）。
    noctalia = {
      url = "github:noctalia-dev/noctalia/cachix";
    };

    # lmclient（龙猫云_Lite）：本地独立 flake 打包的 ClashMeta 代理客户端
    # （AppImage 在 lmclient-nix/ 目录，保持单一来源，不复制进本仓库）。
    # nixpkgs 跟随主输入，避免其内部默认的 TUNA tarball 输入在锁图里
    # 再生一个假时间戳节点（锁漂移来源之一）
    lmclient = {
      url = "path:/home/kun/Projects/lmclient-nix";
      flake = true;
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # wl-harness：跨 Mac / NixOS 共享的 agent 层（pinned skills + codegraph MCP 合并）
    # 只提供 home-manager 模块，不装任何 agent 二进制（见 docs/decisions/0004）。
    # 私有仓库：用本地 clone 的 git+file（只取已提交文件，root 下 nixos-rebuild 也能读，
    # 不依赖 root 的 GitHub 凭据）。更新：git -C ~/Projects/wl-harness pull
    #   && nix flake update wl-harness
    wl-harness.url = "git+file:///home/kun/Projects/wl-harness";
  };

  outputs = { self, nixpkgs, home-manager, noctalia, ... }@inputs:
    let
      system = "x86_64-linux";

      # 自定义包（不在 nixpkgs 的），按程序拆分子 overlay
      overlays = [
        (import ./overlays/pi-tools.nix) # codegraph（vendored node 需 autoPatchelf）
        (import ./overlays/herdr.nix)
        (import ./overlays/wechat.nix) # wechat：src 覆盖为官方 CDN（见 overlays/wechat.nix）
        (import ./overlays/zcode.nix) # zcode：官方 AppImage + appimageTools FHS 包装（见 overlays/zcode.nix）
        (import ./overlays/orca.nix) # orca-ide：官方 AppImage + appimageTools FHS 包装（见 overlays/orca.nix）
        (import ./overlays/grok-bot.nix) # grok-bot：Cursor/xAI Grok Bot 桌面版（官方 AppImage，见 overlays/grok-bot.nix）
      ];
    in
    {
      # 主机名是 "nixos"（见 hosts/nixos/default.nix 的 networking.hostName）
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          # 自定义包 overlay（新版 nixpkgs 用模块选项，而非 nixosSystem 顶层参数）
          { nixpkgs.overlays = overlays; }

          ./hosts/nixos

          # home-manager 集成：useGlobalPkgs 让 HM 复用系统 nixpkgs，避免重复编译
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.kun = import ./home;
              # 把 flake inputs 传给 home 模块（hyprland.nix 需要 noctalia）
              extraSpecialArgs = { inherit inputs; };
            };
          }
        ];
      };
    };
}
