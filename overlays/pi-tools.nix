# ============================================================
# pi 生态里需要 nix patchelf 的 MCP 服务器二进制
# context-mode 已改 npm -g 自管（见 docs/decisions/0001）；此处只保留 codegraph：
#   它的 vendored node 是通用发行版动态链接，NixOS 必须 autoPatchelfHook
#   才能跑，npm 自装是坏的，故保留 nix 打包。
# 用法：flake.nix 的 overlays 列表里引用本文件
# ============================================================
final: prev:

let
  lib = final.lib;
in
{
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
