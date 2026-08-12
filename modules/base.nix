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
}
