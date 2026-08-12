{ config, lib, pkgs, ... }:

{
  # ============================================================
  # 虚拟化：VMware Workstation + KVM/libvirt + Podman（国内源）
  # ============================================================

  # ============ VMware Workstation ============
  # nixpkgs 自带的 vmware-workstation + vmmon/vmnet 内核模块
  # （内核模块会针对 boot.kernelPackages 自动编译，首次构建较久）
  #
  # 注意：bundle 源默认从 archive.org 拉取（国内被墙）。
  # 本机已用 `nix store add-file` 把文件预置进 store，
  # 路径与 fetchurl 输出一致，构建时自动跳过下载：
  #   nix store add-file \
  #     --name VMware-Workstation-Full-25H2u1-25219725.x86_64.bundle \
  #     ~/VMware-Workstation-Full-25H2u1-25219725.x86_64.bundle
  virtualisation.vmware.host.enable = true;

  # vmware-vmx 会触发 kcompactd0 高占用（内核透明大页问题），
  # nixpkgs 的 vmware-host 模块官方建议加此参数；如不需要可删掉
  boot.kernelParams = [ "transparent_hugepage=never" ];

  # ============ KVM / libvirt（virt-manager 图形管理） ============
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;

  # ============ Podman ============
  virtualisation.podman = {
    enable = true;
    # docker CLI 兼容：提供 docker 命令（内部调用 podman）
    dockerCompat = true;
    # 提供 docker API socket：/run/podman/podman.sock
    dockerSocket.enable = true;
    # 每周自动清理无用镜像/容器
    autoPrune.enable = true;
  };

  # ---- Podman 国内镜像源（清华 TUNA / DaoCloud 等加速）----
  # 26.05 的 containers 模块只生成旧格式 registries.conf（无 mirror 支持），
  # 这里用 mkForce 整体覆盖，写成现代格式：docker.io 优先走镜像链，失败兜底原站
  environment.etc."containers/registries.conf" = lib.mkForce {
    text = ''
      unqualified-search-registries = ["docker.io", "quay.io"]

      [[registry]]
      prefix = "docker.io"
      location = "docker.io"

      # 按顺序尝试镜像，全部失败才回退 docker.io 原站
      [[registry.mirror]]
      location = "docker.m.daocloud.io"

      [[registry.mirror]]
      location = "docker.1ms.run"

      [[registry.mirror]]
      location = "docker.1panel.live"

      [[registry.mirror]]
      location = "hub.rat.dev"
    '';
  };
}
