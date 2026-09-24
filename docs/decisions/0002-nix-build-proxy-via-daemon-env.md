# 0002. nix 构建的代理走 daemon env，不包裹 fetchurl

- Status: accepted
- Date: 2026-09-23

## Context

`nixos-rebuild` 变慢，排查后确认是两个叠加原因：TUNA 镜像被 `no_proxy` 放行直连却
实测病态（13s / 3 B/s，走代理 0.5s），以及 `sudo` 剥离代理变量导致 flake 抓取直连
GitHub 超时（20s）。修完后仍出现一次 **12 分钟零进展的构建挂起**：两个 `fetchurl`
（herdr、obsidian）卡在 GitHub 上，实测全机下行 326 B/s。

排查中我基于一个**错误前提**动手：以为「nix-daemon 的代理 env 进不了 fetch 沙箱，
所以要用 overlay 包裹 `fetchurl` 注入 `--proxy`」。写完 overlay 才发现前提是错的，
且实现本身也是坏的。被争议的问题是：

> **nix 构建沙箱里的下载，代理与 curl 参数该从哪里注入？**

## Decision

**走 nix-daemon 的环境变量，靠 nixpkgs 已有的 `impureEnvVars` 机制。不要包裹
`fetchurl`，不要用 overlay。**

实测结论（三条，都可复现）：

1. **代理本来就进得了 fetch 沙箱**。nixpkgs 的 fetchurl 早已把代理声明为
   impure env vars，derivation 里可见：

   ```
   impureEnvVars = [http_proxy https_proxy ftp_proxy all_proxy no_proxy
                    HTTP_PROXY ... NIX_SSL_CERT_FILE NIX_CURL_FLAGS
                    NIX_HASHED_MIRRORS NIX_CONNECT_TIMEOUT NIX_MIRRORS_*]
   ```

2. **取值来源是 daemon 的环境，不是客户端的环境**。判别实验：用 `postFetch` 把
   builder 内的 env 打进构建日志，客户端 env 带/不带代理两种情况下，沙箱里拿到的
   都是 daemon 的值（`no_proxy=localhost,127.0.0.1`，与客户端 shell 的
   `localhost,127.0.0.1,::1` 不同）。所以：

   - 构建沙箱内的下载 → 配 `systemd.services.nix-daemon.environment`
   - 客户端侧原生下载器（flake 抓取、`nix flake update`）→ 需要 `sudo env_keep`
     代理变量（`modules/security/sudo.nix`）

   两者是不同路径，缺一不可。

3. **`NIX_CURL_FLAGS` 是 nixpkgs 预留的 curl 参数口子**，同样在 impureEnvVars 里，
   由 daemon env 注入后，fetchurl 的 `builder.sh` 会把它拼进 curl 命令行。慢连接
   保护就挂在这里，无需碰任何包定义。

**不要包裹 `fetchurl`**：`pkgs.fetchurl` 不是普通 lambda，而是
`lib.extendMkDerivation` 返回的**带 `__functor` 的 attrset**。用
`args: prev.fetchurl (args // {...})` 这种写法替换它，会破坏其
`__functor` / `__functionArgs` 协议，连空 merge（`args // {}`）都会让求值报
`error: expected a set but found a function`（同 harness A/B：纯透传
`args: prev.fetchurl args` 正常）。要扩展现有 fetchurl 行为，优先用它的参数
（`curlOptsList` / `curlOpts`）或 env 口子，而不是替换整个属性。

## Consequences

- 代理与慢连接保护集中在 `modules/mirrors.nix` 的 `nix-daemon.environment` 一个
  block 里；没有代理时删掉该 block 即可回滚。
- `NIX_CURL_FLAGS = "--speed-limit 1000 --speed-time 60"` 让半死连接（curl 只有
  `--connect-timeout`，没有速度超时，trickle 不触发重试）在 60s 内中止，交由 nix 的
  `download-attempts=5` 重试（curl 侧 `-C -` 续传）。
- 慢连接保护的**收益是推断而非实测**：没能复现 post-fix 的慢构建，所以"能防住复发"
  未经实测验证；阈值（持续 <1KB/s 达 60s）取得宽松，正常下载不受影响。
- **失效机理仍未定论**：曾据以判断"构建期间零代理连接"的那条 `ss` 过滤命令是坏的
  （它连既有连接都不显示），该证据无效。现有线索指向代理端 lmclient 自身 DNS 卡死
  （当时抓到 `lmclientCore` 对 `8.8.8.8:443` / `8.8.4.4:443` 处于 `SYN-SENT`）。
- 排查方法论教训：**先验证机制假设再动手**。本轮 overlay 是纯粹由未经验证的前提
  造出来的返工；一条 `postFetch` env 探针就能提前证伪。
