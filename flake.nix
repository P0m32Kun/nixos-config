{
  description = "NixOS 配置（国内镜像 + GitHub 管理）";

  inputs = {
    # 使用清华 TUNA 镜像的 nixpkgs（国内拉取速度快）
    # 可选替代：
    #   - 官方 GitHub（需要科学上网或较慢）："github:NixOS/nixpkgs/nixos-26.05"
    #   - 中科大镜像： "https://mirrors.ustc.edu.cn/nix-channels/nixos-26.05/nixexprs.tar.xz"
    nixpkgs.url = "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixos-26.05/nixexprs.tar.xz";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
    in
    {
      # 主机名是 "nixos"（见 hosts/nixos/default.nix 的 networking.hostName）
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./hosts/nixos ];
      };
    };
}
