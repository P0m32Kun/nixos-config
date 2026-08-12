{ config, lib, pkgs, p-skills, ... }:

# ============================================================
# pi 插件 / 扩展 / MCP / LSP 声明式管理
# ------------------------------------------------------------
# 原理：pi 的一切用户态配置都在 ~/.pi/agent/（不在 nix store），
# 所以 home-manager 直接接管这些文件即可；二进制一律走 nix
# （nixpkgs 或 overlays/pi-tools.nix），不 curl、不 npm i -g。
#
# 接管后的行为变化：
#   - 不要再用 `pi install` / `pi remove` / `pi config` 增删插件，
#     写入会被静默丢弃。改插件一律改这里 + rebuild。
#   - pi 内切主题/默认模型不会持久化（settings.json 只读），改 piSettings。
#   - 升级 pi 后若每次启动都弹 changelog，更新 lastChangelogVersion。
# ============================================================
let
  # pi 第三方插件清单（npm 包），格式与 `pi install` 一致。
  # 包体由 pi 首次启动自动装到 ~/.pi/agent/npm/，之后随系统更新。
  piPackages = [
    "npm:pi-mcp-adapter"          # MCP 适配层（读取下方 mcp.json）
    "npm:context-mode"            # 持久知识库/上下文管理（MCP 二进制见 overlay）
    "npm:pi-subagents"            # 子 agent 编排
    "npm:@dietrichgebert/ponytail" # 审查/债务/收益 skill 套件
    "npm:@narumitw/pi-lsp"        # LSP 集成（读取下方 pi-lsp.json）
    "npm:pi-cache-optimizer"      # 缓存优化
    "npm:pi-rtk-optimizer"        # RTK 优化
    "npm:pi-hashline-edit-pro"    # hash 行编辑
  ];

  # p-skills（自有 agent-skills 仓库）：目录结构与 p-skills/skills/ 一致
  # （core 直接平铺，optional 在 skills/optional/ 下）
  pSkillsCore = [
    "fix-bug" "github-flow" "grill-me" "retrospective"
    "subagent-driven-development" "tdd" "verify" "writing-plans" "writing-skills"
  ];
  pSkillsOptional = [
    "openspec" "security-integrate" "security-poc" "security-research"
  ];

  # pi 全局设置（对应原 ~/.pi/agent/settings.json）
  # 参考字段：theme / defaultProvider / defaultModel / defaultThinkingLevel /
  #           compaction / retry / defaultProjectTrust / npmCommand ...
  piSettings = {
    lastChangelogVersion = "0.84.0"; # 当前 pi 版本，升级后按需更新
    defaultProvider = "opencode-go";
    defaultModel = "deepseek-v4-flash";
    defaultThinkingLevel = "high";
    theme = "dark";
    packages = piPackages;
  };

  # MCP 服务器清单（pi-mcp-adapter 读取）
  # 所有 command 都是 nix 声明式的二进制（home/packages.nix）
  mcpSettings = {
    mcpServers = {
      # pi 知识库：CLI 默认启动 MCP server (stdio)
      context-mode = { command = "context-mode"; };
      # 浏览器自动化：nixpkgs playwright-mcp + PLAYWRIGHT_BROWSERS_PATH
      playwright = {
        command = "playwright-mcp";
        lifecycle = "lazy";
      };
      # 代码图谱
      codegraph = {
        command = "codegraph";
        args = [ "serve" "--mcp" ];
        lifecycle = "lazy";
      };
    };
  };

  # pi-lsp 服务器映射（@narumitw/pi-lsp 读取，覆盖内置默认目录）
  # 注意：自定义配置会整体替换默认目录，所以把要用的都写全
  piLspSettings = {
    typescript = {
      command = [ "typescript-language-server" "--stdio" ];
      extensions = [
        ".ts" ".tsx" ".mts" ".cts" ".js" ".jsx" ".mjs" ".cjs"
        ".json" ".jsonc" ".vue" ".astro" ".svelte"
      ];
    };
    pyright = {
      command = [ "pyright-langserver" "--stdio" ];
      extensions = [ ".py" ".pyi" ];
    };
    rust-analyzer = {
      command = [ "rust-analyzer" ];
      extensions = [ ".rs" ];
    };
    gopls = {
      command = [ "gopls" ];
      extensions = [ ".go" ];
    };
  };

  # 模型 compat 覆盖（pi 读取 ~/.pi/agent/models.json）
  # 说明：opencode-go 是 pi 内置 provider，模型列表由官方 catalog 拉取
  # （缓存在 models-store.json）。pi-cache-optimizer 提示 deepseek-v4-flash
  # 缺 2 个缓存兼容标志，这里用 modelOverrides 只补 compat，不替换完整模型列表。
  piModelsJson = {
    providers = {
      opencode-go = {
        modelOverrides = {
          "deepseek-v4-flash" = {
            compat = {
              supportsLongCacheRetention = true;
              sendSessionAffinityHeaders = true;
            };
          };
        };
      };
    };
  };

in
{
  home.file = {
    # ---- pi 接管文件（home-manager 符号链接，见文件头说明）----

    # 接管 pi 自己生成的 settings.json（首次激活会覆盖），
    # 防止 pi 升级/重置后再生成同名普通文件导致 rebuild 失败
    ".pi/agent/settings.json" = {
      text = builtins.toJSON piSettings;
      force = true;
    };

    # MCP 服务器配置（pi-mcp-adapter 读取）
    ".pi/agent/mcp.json" = {
      text = builtins.toJSON mcpSettings;
    };

    # LSP 服务器映射（pi-lsp 读取）
    ".pi/agent/pi-lsp.json" = {
      text = builtins.toJSON piLspSettings;
    };

    # 模型 compat 覆盖（pi 读取；models.json 不含密钥，key 在 auth.json）
    ".pi/agent/models.json" = {
      text = builtins.toJSON piModelsJson;
    };

    # ponytail skill 默认模式（~/.config/ponytail/config.json，插件读取）
    # off = 默认不激活；需要时 /ponytail full 临时开启
    ".config/ponytail/config.json" = {
      text = builtins.toJSON { defaultMode = "off"; };
    };

    # 自写扩展目录（*.ts 或 子目录/index.ts），符号链接到 ~/.pi/agent/extensions/
    # 注意：nix store 只读，扩展写不了自己的 config.json。pi-rtk-optimizer 的
    # 配置已按默认值预置在 pi-extensions/pi-rtk-optimizer/config.json（声明式接管，
    # 改配置 = 改这个文件 + rebuild；不要在 /rtk TUI 里改，保存会失败）。
    ".pi/agent/extensions" = {
      source = ./pi-extensions;
    };
  }
  // builtins.listToAttrs (map (name: {
    name = ".pi/agent/skills/${name}";
    value.source = "${p-skills}/skills/${name}";
  }) pSkillsCore)
  // builtins.listToAttrs (map (name: {
    name = ".pi/agent/skills/${name}";
    value.source = "${p-skills}/skills/optional/${name}";
  }) pSkillsOptional);
}
