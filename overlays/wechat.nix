# ============================================================
# wechat（微信官方 Linux 版，官方 AppImage）src 覆盖
# nixpkgs 上游把 x86_64 源固定在 web.archive.org 快照（国内被墙，
# 且 sudo nixos-rebuild 的 root 构建沙箱不带代理环境变量，必然失败）。
# 改为直连腾讯官方 CDN（dldir1v6.qq.com，国内直连可达），
# 文件为官方原版；hash 于 2026-09-23 更新：腾讯替换了 CDN 上的 AppImage，
# 旧 hash 失配（nix 报 got: sha256-T1StKQLs1vb9xWgLc1R/gNVCO/RwsBI3pXmi5bPK7us=）。
# 注意：版本标签仍写 4.1.1，若上游已升版需同步 pname/version。
#
# by-name 包装不接受 override { src = ... }，故按上游
# pkgs/by-name/we/wechat/linux.nix 原样重建，仅 src 不同：
# 现役 CDN 文件无 libtiff.so.5 依赖（readelf 实测），故省略上游的
# patchelf 步骤。
# ============================================================
final: prev:

let
  inherit (prev) appimageTools;
  src = prev.fetchurl {
    url = "https://dldir1v6.qq.com/weixin/Universal/Linux/WeChatLinux_x86_64.AppImage";
    hash = "sha256-T1StKQLs1vb9xWgLc1R/gNVCO/RwsBI3pXmi5bPK7us=";
  };
  appimageContents = appimageTools.extract {
    pname = "wechat";
    version = "4.1.1";
    inherit src;
  };
in
{
  wechat = appimageTools.wrapAppImage {
    pname = "wechat";
    version = "4.1.1";
    meta = prev.wechat.meta;
    src = appimageContents;
    extraInstallCommands = ''
      mkdir -p $out/share/applications
      cp ${appimageContents}/wechat.desktop $out/share/applications/
      mkdir -p $out/share/icons/hicolor/256x256/apps
      cp ${appimageContents}/wechat.png $out/share/icons/hicolor/256x256/apps/
      substituteInPlace $out/share/applications/wechat.desktop --replace-fail AppRun wechat
    '';
  };
}
