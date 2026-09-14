# ============================================================
# zcode：智谱 ZCode 桌面版（GLM 官方 Harness，Electron 应用）
#
# 为什么用 AppImage（而不是官方 .deb / .rpm / 手动解包）：
#   - NixOS 没有 dpkg/rpm 数据库，`dpkg -i` 属命令式安装，违反仓库硬约定，
#     且 rebuild 后状态漂移；要进 nix 就得 `dpkg -x` 拆包 + autoPatchelf
#     手工凑 gtk3/nss/dbus/libgbm… 一长串运行库（Electron 主二进制 196MB）。
#   - 官方 AppImage 是标准 type-2，nixpkgs `appimageTools` 直接支持：
#     extractType2 解包 + buildFHSEnv 补齐运行库，**无需 FUSE、无需 patchelf**
#     （与本仓库 wechat / lmclient 同一路子）。
#   - fetchurl 按 URL+hash 锁定，199MB 二进制不进 git；升级即改 version+hash。
#
# 为什么留 nix（见 docs/decisions/0001）：
#   官方 app-update.yml 的更新源是占位 `http://localhost:8081`，即它不自更新，
#   GUI + 不自更新 = 留在 nix 声明式管理。
#
# Electron 沙箱：官方自带 desktop 是 `Exec=AppRun --no-sandbox %U`（store 里
#   无法给 chrome-sandbox setuid），此处保留同款行为。终端直接跑 `zcode` 是否
#   需要补 --no-sandbox 以实测为准（本机 userns 可用，多半走 namespace sandbox）。
#
# 升级流程（新版本发布时）：
#   ./scripts/update-zcode.sh   # 抓官网最新版→改 version→重算 hash→nix build 验证
#   sudo nixos-rebuild switch --flake /etc/nixos
# ============================================================
final: prev:

let
  inherit (prev) appimageTools;

  version = "3.11.2";

  # 官方 CDN 直链（国内可直连，实测 200）。URL 由 version 推出，
  # 故升级脚本只需改本文件的 version + hash 两处。
  src = prev.fetchurl {
    url = "https://cdn-zcode.z.ai/zcode/electron/releases/${version}/linux-x64/ZCode-${version}-linux-x64.AppImage";
    hash = "sha256-/EzIUShqQOqAkM6/qsGp+b3ETqs0njbu8NOzIZ85MD8=";
  };

  appimageContents = appimageTools.extractType2 {
    pname = "zcode";
    inherit version src;
  };
in
{
  zcode = appimageTools.wrapAppImage {
    pname = "zcode";
    inherit version;
    # 注意：wrapAppImage 的 src 必须是「解包后的目录」（它内部执行
    # appimage-exec.sh -w <dir>），不是原始 AppImage 文件——传错会退化成 usage 报错
    src = appimageContents;

    # buildFHSEnv 把二进制装成 $out/bin/zcode（executableName = pname），
    # 这里再补官方 desktop 条目与图标（AppImage 自带，从解包内容里取）
    extraInstallCommands = ''
      install -Dm644 ${appimageContents}/zcode.desktop \
        $out/share/applications/zcode.desktop
      install -Dm644 ${appimageContents}/usr/share/icons/hicolor/1024x1024/apps/zcode.png \
        $out/share/icons/hicolor/1024x1024/apps/zcode.png
      install -Dm644 ${appimageContents}/usr/share/icons/hicolor/1024x1024/apps/zcode.png \
        $out/share/pixmaps/zcode.png
      # Exec 指向 FHS wrapper 里的可执行名（AppRun → zcode），保留官方 --no-sandbox
      substituteInPlace $out/share/applications/zcode.desktop \
        --replace-fail 'AppRun --no-sandbox' 'zcode --no-sandbox'
    '';

    meta = {
      description = "ZCode Desktop（智谱 GLM 官方 Harness）";
      homepage = "https://zcode.z.ai/";
      # 官方 AppImage 原样取用（非再分发），归类为非自由软件；
      # allowUnfree 已在 modules/packages.nix 打开
      license = prev.lib.licenses.unfreeRedistributable;
      platforms = [ "x86_64-linux" ];
    };
  };
}
