{ config, lib, pkgs, ... }:

{
  # ============================================================
  # 虚拟化：KVM/libvirt + Podman（国内源）
  # ============================================================

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

  # ============ kali3 端口转发：host:9080 → kali3:192.168.122.120:9080 ============
  # kali3 在 virbr0（192.168.122.0/24, NAT）上固定 IP 192.168.122.120。
  # 注意：libvirt 的网络 XML 没有 portForward 元素（`net-define` 会把未知元素静默丢弃；
  # domain XML 里的 `portForward` 只适用于 type='user' 用户态网络），
  # 所以 NAT 桥下的端口转发必须在宿主机防火墙层做 DNAT +
  # 放行 libvirt FORWARD 链对 virbr0 入站的新连接（libvirt 默认 REJECT）。
  # 用 systemd oneshot 声明式管理：只增不改，不影响 libvirt 自身规则。
  # 访问方式（宿主机 9080 对外可达，已验证 HTTP 200）：
  #   - 局域网其他设备：http://192.168.0.41:9080（PREROUTING DNAT）
  #   - 宿主机本机：    http://192.168.0.41:9080（OUTPUT DNAT；本机发包不经过 PREROUTING）
  #   - 不要用 127.0.0.1:回环直通 VM 是内核 NAT 回包关联的已知深坑，不支持
  systemd.services.kvm-kali3-portforward = {
    description = "Port forward host:9080 -> kali3 (192.168.122.120:9080)";
    wantedBy = [ "multi-user.target" ];
    after = [ "libvirtd.service" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    path = [ pkgs.iptables ];
    script = ''
      # 自愈：清掉实验性的 127.0.0.1 MASQUERADE 规则（回环直通不支持，勿重新添加）
      iptables -t nat -D POSTROUTING -s 127.0.0.1 -d 192.168.122.120 -p tcp --dport 9080 -j MASQUERADE 2>/dev/null || true
      # 幂等：规则已存在则跳过（iptables -C 检查）
      iptables -t nat -C PREROUTING -p tcp --dport 9080 -j DNAT --to-destination 192.168.122.120:9080 2>/dev/null \
        || iptables -t nat -A PREROUTING -p tcp --dport 9080 -j DNAT --to-destination 192.168.122.120:9080
      # 本机访问自己的局域网 IP 走 OUTPUT 链（本机发包不经过 PREROUTING）
      iptables -t nat -C OUTPUT -p tcp --dport 9080 -j DNAT --to-destination 192.168.122.120:9080 2>/dev/null \
        || iptables -t nat -A OUTPUT -p tcp --dport 9080 -j DNAT --to-destination 192.168.122.120:9080
      # libvirt 的 FORWARD 链对 virbr0 入站新连接默认 REJECT，需在顶部放行到 VM 的新连接
      iptables -C FORWARD -d 192.168.122.120 -p tcp --dport 9080 -m conntrack --ctstate NEW -j ACCEPT 2>/dev/null \
        || iptables -I FORWARD 1 -d 192.168.122.120 -p tcp --dport 9080 -m conntrack --ctstate NEW -j ACCEPT
    '';
    preStop = ''
      iptables -D FORWARD -d 192.168.122.120 -p tcp --dport 9080 -m conntrack --ctstate NEW -j ACCEPT 2>/dev/null || true
      iptables -t nat -D OUTPUT -p tcp --dport 9080 -j DNAT --to-destination 192.168.122.120:9080 2>/dev/null || true
      iptables -t nat -D PREROUTING -p tcp --dport 9080 -j DNAT --to-destination 192.168.122.120:9080 2>/dev/null || true
    '';
  };
}
