# auto_call

自动拨号 App（Flutter / Android）。

## 下载

- **最新版 APK（公开下载，无需登录）**
  https://github.com/banwe1/auto_call/releases/latest
  进入页面后在 `Assets` 中下载 `app-release.apk`。

- 历史 CI 产物（需登录 GitHub，保留 30 天）
  https://github.com/banwe1/auto_call/actions

## 安装

1. 下载 `app-release.apk` 传到手机；
2. 点击安装，如提示"未知来源"请允许；
3. 首次启动后授予「电话」权限。

> 说明：当前使用 debug 签名，仅适合侧载安装；上架应用商店需配置正式签名。

## 构建

推送到 `master` 会自动触发 GitHub Actions 构建并更新 `latest` 发布；
也可在 Actions 页面手动 `Run workflow`。

工具链：Flutter 3.38.10 / Gradle 8.14 / AGP 8.11.1 / Kotlin 2.2.20 / compileSdk 36。

