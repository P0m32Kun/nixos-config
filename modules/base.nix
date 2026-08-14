{ config, lib, pkgs, ... }:

{
  # ============ 时区 ============
  time.timeZone = "Asia/Shanghai";

  # ============ 国际化（中文） ============
  i18n.defaultLocale = "zh_CN.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "zh_CN.UTF-8";
    LC_IDENTIFICATION = "zh_CN.UTF-8";
    LC_MEASUREMENT = "zh_CN.UTF-8";
    LC_MONETARY = "zh_CN.UTF-8";
    LC_NAME = "zh_CN.UTF-8";
    LC_NUMERIC = "zh_CN.UTF-8";
    LC_PAPER = "zh_CN.UTF-8";
    LC_TELEPHONE = "zh_CN.UTF-8";
    LC_TIME = "zh_CN.UTF-8";
  };

  # ============ 网络 ============
  networking.networkmanager.enable = true;

  # ============ SSH 服务 ============
  # ClientAliveInterval/CountMax：网络抖动（WiFi 切换、客户端休眠）导致 TCP 半开时，
  # 让 sshd 快速（30s×3=90s）探测并断开僵尸连接，否则 pty 输出队列会被填满，
  # 阻塞其上运行的 TUI（如 pi）的渲染管线，造成"整个终端冻结"。
  services.openssh = {
    enable = true;
    settings = {
      ClientAliveInterval = 30;
      ClientAliveCountMax = 3;
    };
  };

  # TCP keepalive 探测间隔从默认 2 小时缩短到 60s，配合上面 sshd 探活，
  # 让半开连接尽早被内核发现并回收。
  boot.kernel.sysctl."net.ipv4.tcp_keepalive_time" = 60;
  # ============ 打印 ============
  services.printing.enable = true;

  # ============ USB 存储（udisks2） ============
  # U 盘挂载基础设施；实际自动挂载由 home/apps.nix 的 udiskie 完成
  services.udisks2.enable = true;
  boot.supportedFilesystems = [ "exfat" ];

  # ============ 回滚记录保留策略 ============
  # 只保留最近 10 个 system generation（`nixos-rebuild --rollback` 的回滚点）。
  # generation 是 GC root：每多一代，/nix/store 就多一份完整系统快照，
  # 不回滚时无限堆积（本机 35 代曾占 32G）。
  #
  # 每周一 03:30 自动清理：
  #   1) nix-env --delete-generations +10 把 system profile 修剪到最近 10 代
  #      （+N 语义 = 保留最近 N 代，见 nix-env 手册）
  #   2) nix-collect-garbage 回收被删代际变成不可达的 store 路径
  # 注意：不用 -d（--delete-old），否则会把 home-manager / 用户 profile 的
  # 旧代际也一并删掉，超出本策略范围。
  # 引导菜单侧由 hosts/*/default.nix 的 boot.loader.systemd-boot.configurationLimit
  # 限制（systemd-boot 专属选项，故不放这里）。
  systemd.services.nix-generations-cleanup = {
    description = "Keep only the 10 most recent NixOS system generations";
    serviceConfig = {
      Type = "oneshot";
      # 绝对路径防 PATH 篡改；nix-env 需 root 写 /nix/var/nix/profiles
      ExecStart = [
        "${pkgs.nix}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +10"
        "${pkgs.nix}/bin/nix-collect-garbage"
      ];
    };
    # 自动生成 nix-generations-cleanup.timer
    startAt = "Mon 03:30";
  };
  # 错过触发时间（睡眠/关机）时，下次启动补跑
  systemd.timers."nix-generations-cleanup".timerConfig.Persistent = true;
}
