# ============================================================
# herdr：AI coding agent 的终端工作区管理器（terminal workspace manager）
# 官方 release 提供 x86_64-linux 静态链接二进制（static-pie，无动态依赖），
# 直接 fetchurl + install 即可；nixpkgs 里没有此包。
# 版本锁定：v0.8.0（2026-08 检查的 latest release）
# ============================================================
final: prev:

let
  lib = final.lib;
in
{
  herdr = prev.stdenv.mkDerivation {
    pname = "herdr";
    version = "0.8.0";

    src = prev.fetchurl {
      url = "https://github.com/herdrdev/herdr/releases/download/v0.8.0/herdr-linux-x86_64";
      hash = "sha256-uHLqfkD6LLF+hXrJtisb8m23tAPGIvXS8/WzX26azSg=";
    };

    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      install -m755 $src $out/bin/herdr
      runHook postInstall
    '';

    meta = {
      description = "Terminal workspace manager for AI coding agents";
      homepage = "https://github.com/herdrdev/herdr";
      license = lib.licenses.asl20;
      mainProgram = "herdr";
    };
  };
}
