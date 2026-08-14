{
  description = "NixOS 配置（国内镜像 + GitHub 管理）";

  # noctalia 官方 Cachix 二进制缓存（避免本地编译 C++ 项目）
  nixConfig = {
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [ "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=" ];
  };

  inputs = {
    # 使用清华 TUNA 镜像的 nixpkgs（国内拉取速度快）
    # 可选替代：
    #   - 官方 GitHub（需要科学上网或较慢）："github:NixOS/nixpkgs/nixos-26.05"
    #   - 中科大镜像： "https://mirrors.ustc.edu.cn/nix-channels/nixos-26.05/nixexprs.tar.xz"
    nixpkgs.url = "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixos-26.05/nixexprs.tar.xz";

    # unstable 输入只给 hermes-agent 的 nixpkgs follow 用（国内可达 + 版本语义一致）
    nixpkgs-unstable.url = "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixos-unstable/nixexprs.tar.xz";

    # home-manager：声明式管理用户级配置，随系统一起更新
    # 分支与 nixpkgs 的 26.05 对齐；nixpkgs 跟随主输入（TUNA 镜像）
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # hermes-agent（Nous Research）：通过 overlay 暴露 pkgs.hermes-agent，
    # 声明式装进 home.packages（官方文档：
    #   https://hermes-agent.nousresearch.com/docs/getting-started/nix-setup）
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      # nixpkgs 跟随本仓库的 TUNA 镜像 unstable 输入：
      #   1) 国内可达，避免 github.com 大文件下载被墙中断
      #   2) 与自己的 nixpkgs-unstable 同一 channel（版本语义一致）
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # noctalia v5（C++ 版，官方当前推荐版本；nixpkgs 里的 noctalia-shell 是
    # v4 Quickshell 旧版，配置不兼容）。用官方 cachix 分支保证二进制缓存命中，
    # 避免本地编译整个 C++ 项目。**不要**加 inputs.nixpkgs.follows，
    # 否则 derivation 改变会导致缓存 miss（见官方文档）。
    noctalia = {
      url = "github:noctalia-dev/noctalia/cachix";
    };

    # lmclient（龙猫云_Lite）：本地独立 flake 打包的 ClashMeta 代理客户端
    # （AppImage 在 lmclient-nix/ 目录，保持单一来源，不复制进本仓库）
    lmclient = {
      url = "path:/home/kun/Projects/lmclient-nix";
      flake = true;
    };
  };

  outputs = { self, nixpkgs, home-manager, hermes-agent, noctalia, ... }@inputs:
    let
      system = "x86_64-linux";

      # 自定义包（不在 nixpkgs 的），按程序拆分子 overlay
      overlays = [
        (import ./overlays/pi-tools.nix) # codegraph（vendored node 需 autoPatchelf）
        (import ./overlays/herdr.nix)
        (import ./overlays/wechat.nix) # wechat：src 覆盖为官方 CDN（见 overlays/wechat.nix）
        (import ./overlays/dsh.nix) # dsh：npm 打包 + --expose-internals wrapper（见 overlays/dsh.nix）
        # hermes-agent 官方 overlay：pkgs.hermes-agent = 其 flake 的 default 包
        # （纯别名，构建用 hermes 自己锁定的 nixpkgs-unstable + uv2nix）
        hermes-agent.overlays.default
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
