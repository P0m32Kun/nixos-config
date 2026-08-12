{ config, lib, pkgs, ... }:

# ============================================================
# pi 配套二进制（LSP 服务器 + MCP 服务器），全部 nix 声明式管理
# 原则：能用 nixpkgs 的用 nixpkgs；不在 nixpkgs 的由 flake overlay
#       （overlays/pi-tools.nix）打包。禁止 curl|sh / npm i -g。
# ============================================================
{
  home.packages = with pkgs; [
    # ---- pi-lsp 的语言服务器（~/.pi/agent/pi-lsp.json 会引用，见 home/pi.nix）----
    typescript-language-server # TS/JS：typescript-language-server --stdio
    pyright                    # Python：pyright-langserver --stdio
    rust-analyzer              # Rust（也是 pi-lsp 默认目录）
    gopls                      # Go（也是 pi-lsp 默认目录）

    # ---- MCP 服务器（~/.pi/agent/mcp.json 会引用）----
    context-mode    # overlay 打包：pi 知识库 MCP
    codegraph       # overlay 打包：代码图谱 MCP（自带 vendored node，体积较大）
    playwright-mcp  # nixpkgs：浏览器自动化 MCP

    # ---- pi 扩展配套二进制（overlay 打包）----
    rtk             # Rust Token Killer：pi-rtk-optimizer 的命令改写（`which rtk` 可找到）

    python3          # Python 解释器
    gcc              # C 编译器
    gnumake          # make 工具
    nodejs                 # Node.js 运行时
    pnpm                   # ✅ 直接在顶层
    yarn                   # ✅ 直接在顶层
    typescript             # ✅ 直接在顶层
    pkg-config       # 帮助找依赖库

    # ---- hermes-agent（Nous Research AI agent）----
    # 来自 flake 输入 hermes-agent 的 overlay（官方 nix-setup 文档方案）。
    # 首次构建较久（uv2nix 打包全部 Python 依赖，~700MB closure）。
    # 密钥/配置在 ~/.hermes/（imperative，不进 nix store），
    # 首次使用运行 `hermes setup`
    hermes-agent
  ];

  # playwright 浏览器：nixpkgs 托管，指向 playwright-driver 的浏览器包
  # （否则 playwright-mcp 运行时找不到浏览器）
  home.sessionVariables = {
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
  };
}
