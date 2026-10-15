{
  config,
  lib,
  pkgs,
  ...
}:

# ============================================================
# 用户级软件包（慢层，nix 声明式）
# 快慢分层原则见 docs/decisions/0001 + 0005：
#   - 稳定工具 / 系统依赖 / LSP 服务器 / GUI → 留在本文件
#   - 自带更新机制的（pi 全家桶、hermes-agent、context-mode/rtk、agy）→
#     npm -g / uv tool 自管到 ~/.local，不进 nix
# ============================================================
{
  home.packages = with pkgs; [
    # ---- LSP 语言服务器（pi 的 pi-lsp.json 会引用，二进制由 nix 提供）----
    typescript-language-server # TS/JS：typescript-language-server --stdio
    pyright # Python：pyright-langserver --stdio
    rust-analyzer # Rust（也是 pi-lsp 默认目录）
    gopls # Go（也是 pi-lsp 默认目录）

    # ---- MCP 服务器 ----
    codegraph # overlay 打包：vendored node 需 autoPatchelf（见 overlays/pi-tools.nix）
    playwright-mcp # nixpkgs：浏览器自动化 MCP（浏览器由 nix 托管）

    python3 # Python 解释器
    gcc # C 编译器
    gnumake # make 工具
    nodejs # Node.js 运行时
    pnpm # ✅ 直接在顶层
    yarn # ✅ 直接在顶层
    typescript # ✅ 直接在顶层
    pkg-config # 帮助找依赖库

    # ---- 通讯/会议（nixpkgs 现有包；unfree 已在 modules/packages.nix 允许）----
    wechat # 微信（官方 Linux 版）
    wemeet # 腾讯会议
    wpsoffice-cn # WPS Office（中文版，原生中文界面；字体/输入法已就绪）

    # ---- 图形文件管理器（nixpkgs 现有包）----
    thunar # XFCE 文件管理器（GUI；Super+T 启动，见 hyprland 键位）
    tumbler # 缩略图守护：thunar 的图片/视频缩略图靠它，不装就没缩略图
    gvfs # 回收站/网络位置；gvfsd 守护由 modules/base.nix 的 services.gvfs 起

    # ---- AI 编程客户端（overlay 打包，见 overlays/zcode.nix / overlays/orca.nix）----
    zcode # 智谱 ZCode Desktop（GLM 官方 Harness）
    orca-ide # Orca agent IDE（stablyai，官方 AppImage）
    grok-bot # Grok Bot（Cursor/xAI 常驻 AI 队友桌面客户端，官方 AppImage）

    # ---- 开发/安全工具（nixpkgs 现有包）----
    go # Go 工具链（gopls 已在 LSP 列表单独声明）
    jdk21 # Java 21 LTS 工具链（java/javac；JAVA_HOME 见下方 sessionVariables）
    visualvm # Java 分析 GUI：打开 .hprof 堆转储 / JFR / 远程 JMX 监控
    nmap # 网络扫描器
    metasploit # Metasploit 框架（msfconsole）
    gh # GitHub 官方命令行工具
    rclone # S3 兼容存储 CLI（provider=ChinaMobile 对移动云 EOS；STS 凭证填 session_token）
    rclone-browser # rclone 的 Qt GUI：可视化浏览/下载桶内对象
    awscli2 # AWS CLI v2：--endpoint-url + AWS_SESSION_TOKEN 做 S3 兼容取证
    redis # redis-cli：连远端/虚拟机里的 Redis 调试（顺带含 server 二进制）
    psmisc # fuser/pkill 系：查块设备/挂载点被哪个进程占用（排查 U 盘无法弹出类问题）
    lsof # 列出进程打开的文件/socket：与 psmisc 互补的占用排查工具
    jq # JSON 处理：wl-harness agent-check.sh 与 agent 配置合并的依赖（checklists 也直接调用）

    # ---- 录屏/直播（nixpkgs 现有包）----
    obs-studio # OBS Studio：录屏/推流；硬编依赖 intel-media-driver（见 modules/desktop/hyprland.nix）

    # ---- 远程连接（nixpkgs 现有包）----
    freerdp # FreeRDP 3 CLI（xfreerdp/wlfreerdp）：RDP 直连 KVM 里的 Windows；升级后可测 wlfreerdp 原生前端是否修复
    remmina # RDP/VNC/SPICE GUI 客户端：Win11 虚拟机日常连接（原生 Wayland，HiDPI/缩放/输入/光标均由 GTK 层正确处理）
  ];

  # playwright 浏览器：nixpkgs 托管，指向 playwright-driver 的浏览器包
  # （否则 playwright-mcp 运行时找不到浏览器）
  home.sessionVariables = {
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    JAVA_HOME = "${pkgs.jdk21.home}";
  };
}
