{ config, lib, pkgs, inputs, ... }:

# ============================================================
# 用户级软件包
# 拆分原则（见 docs/decisions/0001）：
#   - 稳定工具 / 系统依赖 / LSP 服务器 / GUI → 留在 nix 声明式
#   - 自带更新机制的（pi 本体、pi 插件、MCP 二进制 context-mode/rtk）→
#     已改 npm -g / 官方 release 自管到 ~/.local
# ============================================================
{
  home.packages = with pkgs; [
    # ---- LSP 语言服务器（pi 的 pi-lsp.json 会引用，二进制由 nix 提供）----
    typescript-language-server # TS/JS：typescript-language-server --stdio
    pyright                    # Python：pyright-langserver --stdio
    rust-analyzer              # Rust（也是 pi-lsp 默认目录）
    gopls                      # Go（也是 pi-lsp 默认目录）

    # ---- MCP 服务器 ----
    codegraph       # overlay 打包：vendored node 需 autoPatchelf（见 overlays/pi-tools.nix）
    playwright-mcp  # nixpkgs：浏览器自动化 MCP（浏览器由 nix 托管）

    python3          # Python 解释器
    gcc              # C 编译器
    gnumake          # make 工具
    nodejs                 # Node.js 运行时
    pnpm                   # ✅ 直接在顶层
    yarn                   # ✅ 直接在顶层
    typescript             # ✅ 直接在顶层
    pkg-config       # 帮助找依赖库

    # ---- herdr（AI agent 终端工作区管理器，overlay 打包）----
    herdr
    # ---- dsh（DeepSeek Harness CLI，overlay 打包）----
    # npm 包 + --expose-internals wrapper（绕开 linux addon 的 HMR 故障，见 overlays/dsh.nix）
    dsh
    # ---- hermes-agent（Nous Research AI agent）----
    # 来自 flake 输入 hermes-agent 的 overlay（官方 nix-setup 文档方案）。
    # 首次构建较久（uv2nix 打包全部 Python 依赖，~700MB closure）。
    # 密钥/配置在 ~/.hermes/（imperative，不进 nix store），
    # 首次使用运行 `hermes setup`
    hermes-agent

    # ---- 龙猫云_Lite（ClashMeta 代理客户端，本地 flake lmclient-nix 打包）----
    # 来自 flake 输入 lmclient（path:/home/kun/lmclient-nix）的 default 包
    inputs.lmclient.packages.x86_64-linux.default

    # ---- 通讯/会议（nixpkgs 现有包；unfree 已在 modules/packages.nix 允许）----
    wechat # 微信（官方 Linux 版）
    wemeet # 腾讯会议
    wpsoffice-cn # WPS Office（中文版，原生中文界面；字体/输入法已就绪）
  ];

  # playwright 浏览器：nixpkgs 托管，指向 playwright-driver 的浏览器包
  # （否则 playwright-mcp 运行时找不到浏览器）
  home.sessionVariables = {
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
  };
}
