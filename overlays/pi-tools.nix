# ============================================================
# pi 生态的 MCP 服务器二进制（不在 nixpkgs 的，在这里打包）
# 原则：所有软件都走 nix 声明式，不 curl 脚本、不 npm i -g
# 用法：flake.nix 的 overlays 列表里引用本文件
# ============================================================
final: prev:

let
  lib = final.lib;
in
{
  # context-mode：pi 知识库/上下文管理的 MCP 服务器 + CLI
  # 说明：
  #   - npm 包自带 cli.bundle.mjs（esbuild 打包，唯一外部依赖 better-sqlite3
  #     在 Node >= 22.5 时会被内置 node:sqlite 替代，nixpkgs nodejs 24 满足）
  #   - 因此无需 npm install，直接拷全量文件 + node 包装即可
  #   - 它同时也是 pi 插件（见 home/pi.nix 的 piPackages），两者互补：
  #     插件负责 pi 集成，这里提供 PATH 上的 context-mode 命令给 MCP 用
  context-mode = prev.stdenv.mkDerivation {
    pname = "context-mode";
    version = "1.0.169";

    src = prev.fetchurl {
      url = "https://registry.npmjs.org/context-mode/-/context-mode-1.0.169.tgz";
      hash = "sha256-CcQeTPd7IVZsdrjqL9vX89gjBV/uLwLCFm/Vu1ddryw=";
    };

    nativeBuildInputs = [ prev.makeWrapper ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/context-mode $out/bin
      # 全量拷贝（cli.bundle.mjs 按 __dirname 引用 hooks/ skills/ configs/ 等）
      cp -r ./* $out/lib/context-mode/
      makeWrapper ${prev.nodejs}/bin/node $out/bin/context-mode \
        --add-flags $out/lib/context-mode/cli.bundle.mjs
      runHook postInstall
    '';

    meta = {
      description = "Pi context-mode MCP server (knowledge base / context management)";
      license = lib.licenses.mit;
      mainProgram = "context-mode";
    };
  };

  # codegraph：代码图谱 MCP 服务器
  # 说明：npm 主包是 shim，真正的工件是平台包 @colbymchenry/codegraph-linux-x64
  #   （自带 vendored node + 应用，自包含）。直接打包平台包，运行官方 bin/codegraph。
  codegraph = prev.stdenv.mkDerivation {
    pname = "codegraph";
    version = "1.5.0";

    src = prev.fetchurl {
      url = "https://registry.npmjs.org/@colbymchenry/codegraph-linux-x64/-/codegraph-linux-x64-1.5.0.tgz";
      hash = "sha256-ZQFSDvM3LrdO5KhTfYsu5jyz2VU2+O3oUOdF6wam0aI=";
    };

    # vendored node 是按通用发行版动态链接的，NixOS 没有 /lib64，
    # 用 autoPatchelfHook 自动把解释器/依赖指向 nixpkgs 的 glibc
    nativeBuildInputs = [ prev.autoPatchelfHook ];
    # 运行时缺的 C++ 运行时库（libstdc++ / libgcc_s）
    buildInputs = [ prev.stdenv.cc.cc.lib ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      # package 根目录含 bin/、lib/、vendored node，保持原布局整体拷入
      cp -r ./* $out/
      chmod +x $out/bin/codegraph
      runHook postInstall
    '';

    meta = {
      description = "CodeGraph MCP server (code graph indexing for agents)";
      license = lib.licenses.mit;
      mainProgram = "codegraph";
    };
  };
}
