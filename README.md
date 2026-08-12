# NixOS 配置仓库

使用 **flake** + **模块化** 管理 NixOS 配置，配置托管在 **GitHub**，国内使用 **清华 TUNA 镜像**。

## 目录结构

```
nixos-config/
├── flake.nix                    # flake 入口（nixpkgs 来源、主机定义）
├── flake.lock                   # 版本锁定（提交到 GitHub，保证可复现）
├── hosts/                       # 每台机器一份配置
│   └── nixos/                   #   本机（主机名 nixos）
│       ├── default.nix          #     入口：导入模块 + 本机特有配置
│       └── hardware-configuration.nix  # 硬件配置（生成，勿手改）
├── modules/                     # 可复用的功能模块
│   ├── base.nix                 #   时区 / 中文 / 网络 / SSH / 打印
│   ├── mirrors.nix              #   国内镜像（TUNA）
│   ├── packages.nix             #   系统软件包 + 允许 unfree
├── modules/                     # 可复用的功能模块
│   ├── base.nix                 #   时区 / 中文 / 网络 / SSH / 打印
│   ├── mirrors.nix              #   国内镜像（TUNA）
│   ├── packages.nix             #   系统软件包 + 允许 unfree
│   ├── desktop/
│   │   ├── hyprland.nix         #   Hyprland 桌面（SDDM / fcitx5 / 字体 / portal）
│   │   └── audio.nix            #   PipeWire 声音
│   └── users/
│       └── kun.nix              #   用户 kun（shell = fish）
├── home/                        # home-manager 用户级配置
│   ├── default.nix              #   入口（imports 注册处）
│   ├── pi.nix                   #   pi 插件/MCP/LSP 声明
│   ├── packages.nix             #   用户级软件包（含 hermes-agent）
│   ├── hyprland.nix             #   Hyprland dotfiles（waybar/rofi/awww/hyprlock...）
│   ├── apps.nix                 #   Alacritty / Helix / Fish / Yazi / uv / Obsidian
│   ├── agent-skills.nix         #   agent-skills 技能平台（out-of-store 链接）
│   └── pi-extensions/           #   自写 pi 扩展
├── rebuild.sh                   # 一键重建脚本
└── README.md
```

**设计思想**：
- 所有机器共享 `modules/`，差异只体现在 `hosts/<主机>/default.nix` 的 imports 和"本机特有配置"
- 新增功能 = 新建一个模块文件 → 在主机入口 import 它
- 新增软件 = 把包名加进 `modules/packages.nix` 的列表

## 日常使用

```bash
# 本机重建/升级
sudo nixos-rebuild switch --flake /etc/nixos

# 更新 nixpkgs 到镜像最新版本（在配置目录里执行）
cd /etc/nixos && nix flake update nixpkgs
sudo nixos-rebuild switch --flake /etc/nixos

# 添加新软件：编辑 modules/packages.nix 的 environment.systemPackages
# 然后执行上面第一条命令

# 测试构建（不生效）
sudo nixos-rebuild build --flake /etc/nixos

# 回滚到上一个版本
sudo nixos-rebuild switch --rollback
```

## 国内镜像说明

- **nixpkgs 源**：`flake.nix` 中直接使用 TUNA 的 channel tarball
  `https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixos-26.05/nixexprs.tar.xz`
- **二进制缓存**：`modules/mirrors.nix` 的 `nix.settings.substituters` 优先 TUNA，官方兜底

> 想换中科大 USTC？把 flake.nix 中的 URL 前缀换成 `https://mirrors.ustc.edu.cn/nix-channels/`，
> 并把 `modules/mirrors.nix` 中 `substituters` 第一条改为 `https://mirrors.ustc.edu.cn/nix-channels/store`。

## 上传 GitHub

```bash
cd ~/nixos-config
git remote add origin git@github.com:你的用户名/nixos-config.git
git push -u origin main
```

之后每次改配置：

```bash
cd ~/nixos-config
git add -A && git commit -m "描述你的改动"
git push
sudo nixos-rebuild switch --flake /etc/nixos   # 在本机应用
```

> SSH 公钥（`cat ~/.ssh/id_ed25519.pub`）需提前添加到 GitHub：
> Settings → SSH and GPG keys → New SSH key

## 在新机器上恢复这套配置

```bash
# 1. 克隆仓库
git clone git@github.com:你的用户名/nixos-config.git /etc/nixos

# 2. 生成新机器的硬件配置
sudo nixos-generate-config --show-hardware-config > /etc/nixos/hosts/<主机名>/hardware-configuration.nix

# 3. 复制 hosts/nixos 为新主机（或直接复用）
cp -r /etc/nixos/hosts/nixos /etc/nixos/hosts/<新主机名>
#    编辑 default.nix：调整 imports 里的模块、hostname、bootloader 等

# 4. 重建（临时开启 flakes，因为新机配置里还没启用）
sudo NIX_CONFIG='experimental-features = nix-command flakes' nixos-rebuild switch --flake /etc/nixos#<新主机名>
```
