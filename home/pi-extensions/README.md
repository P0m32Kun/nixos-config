# pi 扩展目录

把自写的 pi 扩展源码放在这里，home-manager 会把它符号链接到
`~/.pi/agent/extensions/`，pi 启动时自动发现，`/reload` 可热重载。

支持的两种结构（与 pi 官方一致）：

- 单文件：`my-ext.ts`
- 多文件：`my-ext/index.ts` + 辅助模块

扩展依赖 npm 包时，在 `my-ext/` 里放 `package.json` 并在该目录执行
`npm install`（生成 node_modules 一并提交或本地保留），imports 自动解析。

开发调试（不想 rebuild 时快速试）：
```bash
pi -e ./pi-extensions/my-ext.ts
```
