# ============================================================
# dsh：DeepSeek Harness CLI（npm 包 + --expose-internals wrapper）
# 为什么用 nix 打包：
#   dsh 的 HMR 依赖 node-addon-require-builtin 的 linux-x64-gnu 预编译
#   addon，它在所有 Node 版本（22/24/26 实测）上都因 V8 布局不兼容崩掉
#   （"x64 sysv getter is not a recognized this->field accessor"），
#   只能给 node 加 --expose-internals 走官方内部模块路径绕开。
# 打包方式：
#   buildNpmPackage 打 npm 官方包依赖树（含预编译前端 dist），
#   postInstall 用 makeWrapper 生成 dsh = node --expose-internals <bin.js>。
# 版本锁定：
#   overlays/dsh/package.json + package-lock.json（npmmirror 解析）。
# 升级流程（新版本发布时）：
#   ./scripts/update-dsh.sh   # 自动：查版本→改版本号→重生成 lockfile→重算 hash→nix build 验证
#   sudo nixos-rebuild switch --flake /etc/nixos
# ============================================================
final: prev:

let
  lib = final.lib;
  nodejs = prev.nodejs;
in
{
  dsh = prev.buildNpmPackage {
    pname = "dsh";
    version = "0.1.0-rc.6";

    # 包装项目：package.json + package-lock.json（锁定 @deepseek-ai/dsh 及全部传递依赖）
    src = ./dsh;

    # 依赖树 hash（prefetch-npm-deps 计算，升级时由 scripts/update-dsh.sh 自动更新）
    npmDepsHash = "sha256-E7XK8h8ub+oq8dJT51PfDGVpjSQkno7bUxBcESeScBI=";

    # dsh 发布包无 build 脚本（lib/ 已预编译）
    dontNpmBuild = true;

    # node-pty 无 linux 预编译，需现场 node-gyp 编译（nodedir 由 nixpkgs npm 钩子自动设置）；
    # koffi/sharp 用预编译平台包（dlopen 加载，不读 /lib64 解释器），沙箱内可用
    nativeBuildInputs = [ prev.gcc prev.gnumake prev.makeWrapper ];

    # 生成 dsh 命令：node --expose-internals <bin.js>（绕开坏掉的 linux addon）
    postInstall = ''
      makeWrapper ${nodejs}/bin/node $out/bin/dsh \
        --add-flags "--expose-internals $out/lib/node_modules/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js"
    '';

    meta = {
      description = "DeepSeek Harness CLI (wrapped with --expose-internals for HMR on Linux)";
      homepage = "https://github.com/deepseek-ai/deepseek-harness";
      license = lib.licenses.mit;
      mainProgram = "dsh";
    };
  };
}
