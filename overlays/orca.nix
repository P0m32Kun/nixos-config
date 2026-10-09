# ============================================================
# orca-ide：Orca 桌面版（stablyai 出品的并行 agent IDE，
# https://www.onorca.dev/ ）
#
# 为什么用 AppImage（同 wechat / zcode / lmclient 一路）：
#   - 上游 Linux 只发 Universal AppImage（无 deb 之外的通用格式），
#     type-2 标准结构，nixpkgs `appimageTools` 直接支持：
#     extractType2 解包 + buildFHSEnv 补齐运行库，无需 FUSE / patchelf。
#   - fetchurl 按 URL+hash 锁定，210MB 二进制不进 git；
#     升级即改 version + hash 两处（./scripts/update-orca.sh 一键完成）。
#
# 为什么留 nix（见 docs/decisions/0001）：
#   - GUI 应用 → 留 nix 声明式管理。
#   - App 自带 electron-updater（resources/app-update.yml 指向 GitHub），
#     但 appimageTools 包装后进程里没有 $APPIMAGE，自更新无法落盘，
#     与 codegraph 同属「自更新但 nix 包装后失效」→ 版本由 nix 锁定。
#
# 属性名为什么是 orca-ide 而不是 orca：
#   nixpkgs 的 pkgs.orca 是 GNOME 屏幕阅读器，overlay 里叫 orca 会把
#   它整仓遮蔽。AppImage 内部可执行名 / desktop 文件名本来就是 orca-ide。
#
# Electron 沙箱：官方 desktop 的 Exec 不带 --no-sandbox（走 namespace
#   sandbox，本机未限制 unprivileged userns），此处保持同款行为。
#   若启动报 SUID sandbox 相关错误，再在下面的 Exec 替换里补 --no-sandbox。
#
# 升级流程（新版本发布时）：
#   ./scripts/update-orca.sh   # 查 GitHub 最新 tag→改 version→重算 hash→nix build 验证
#   sudo nixos-rebuild switch --flake /etc/nixos
# ============================================================
final: prev:

let
  inherit (prev) appimageTools;

  version = "1.4.223";

  # 官方 release 资产名固定为 orca-linux.AppImage（不含版本号），
  # 版本只体现在 tag 上，故 URL 完全由 version 推出。
  # 下载走 nix-daemon 的代理 env（见 docs/decisions/0002）。
  src = prev.fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-linux.AppImage";
    hash = "sha256-Dhis/lwH7Rk6/2A/tja6H8WQeBEgOad5pUQ6jVNIPUs=";
  };

  appimageContents = appimageTools.extractType2 {
    pname = "orca-ide";
    inherit version src;
  };
in
{
  orca-ide = appimageTools.wrapAppImage {
    pname = "orca-ide";
    inherit version;
    # 注意：wrapAppImage 的 src 必须是「解包后的目录」（它内部执行
    # appimage-exec.sh -w <dir>），不是原始 AppImage 文件
    src = appimageContents;

    extraInstallCommands = ''
      # 图标：AppImage 自带 hicolor 全尺寸，整目录搬过来，Icon=orca-ide 即可命中
      mkdir -p $out/share/icons
      cp -r ${appimageContents}/usr/share/icons/hicolor $out/share/icons/

      install -Dm644 ${appimageContents}/orca-ide.desktop \
        $out/share/applications/orca-ide.desktop
      # Exec 指向 FHS wrapper 的可执行名（AppRun → orca-ide），保留官方参数
      substituteInPlace $out/share/applications/orca-ide.desktop \
        --replace-fail 'Exec=AppRun %U' 'Exec=orca-ide %U'
    '';

    meta = {
      description = "Orca — 并行 agent 开发环境（stablyai agent IDE）";
      homepage = "https://www.onorca.dev/";
      # 官方 AppImage 原样取用（非再分发），归类为非自由软件；
      # allowUnfree 已在 modules/packages.nix 打开
      license = prev.lib.licenses.unfreeRedistributable;
      platforms = [ "x86_64-linux" ];
      mainProgram = "orca-ide";
    };
  };
}
