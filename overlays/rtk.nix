# ============================================================
# rtk (Rust Token Killer)：pi-rtk-optimizer 扩展依赖的命令改写二进制
# （扩展用 `rtk rewrite` 把 bash 命令改写成压缩输出版本）
# 官方 release 提供 x86_64-linux musl 静态二进制，直接 fetchurl + 解包，
# 无需 cargo 构建；nixpkgs 里没有此包。
# ============================================================
final: prev:

let
  lib = final.lib;
in
{
  rtk = prev.stdenv.mkDerivation {
    pname = "rtk";
    version = "0.45.0";

    src = prev.fetchurl {
      url = "https://github.com/rtk-ai/rtk/releases/download/v0.45.0/rtk-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-xMA2+/GB/FXvMpeGyMF+DUJ5crBTuCWUTZaKaq/vG6Q=";
    };

    sourceRoot = ".";
    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      install -m755 rtk $out/bin/rtk
      runHook postInstall
    '';

    meta = {
      description = "Rust Token Killer - CLI proxy that compresses bash output for LLM agents";
      homepage = "https://github.com/rtk-ai/rtk";
      license = lib.licenses.asl20;
      mainProgram = "rtk";
    };
  };
}
