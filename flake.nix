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

    # 系统本体保持 stable；个别需要追新的包（如 pi-coding-agent）从这里取
    nixpkgs-unstable.url = "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixos-unstable/nixexprs.tar.xz";

    # home-manager：声明式管理用户级配置（如 pi 的插件），随系统一起更新
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

    # 自有的 agent-skills 技能平台：私有仓库，仓库自带 flake.nix
    # （packages.default / overlays.default，打包与 hash 在源码仓库维护）。
    # nixpkgs 跟随本仓库输入（TUNA 镜像），避免双份 nixpkgs。
    # 更新：agent-skills 仓库 commit+push 后 `nix flake update agent-skills`
    agent-skills = {
      url = "git+ssh://git@github.com/P0m32Kun/agent-skills.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, hermes-agent, noctalia, agent-skills, ... }@inputs:
    let
      system = "x86_64-linux";
      # unstable nixpkgs 的包集合，通过 specialArgs 传给模块
      pkgsUnstable = nixpkgs-unstable.legacyPackages.${system};

      # 自定义包（不在 nixpkgs 的 npm 工具等），按程序拆分子 overlay
      overlays = [
        (import ./overlays/pi-tools.nix)
        agent-skills.overlays.default
        (import ./overlays/rtk.nix)
        (import ./overlays/herdr.nix)
        # hermes-agent 官方 overlay：pkgs.hermes-agent = 其 flake 的 default 包
        # （纯别名，构建用 hermes 自己锁定的 nixpkgs-unstable + uv2nix）
        hermes-agent.overlays.default
      ];
    in
    {
      # 主机名是 "nixos"（见 hosts/nixos/default.nix 的 networking.hostName）
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit pkgsUnstable; };
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
              # （agent-skills 不走输入，见 home/agent-skills.nix）
              users.kun = import ./home;
              # 把 flake inputs 传给 home 模块（hyprland.nix 需要 noctalia）
              extraSpecialArgs = { inherit inputs; };
            };
          }
        ];
      };
    };
}
