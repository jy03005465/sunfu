# 2048 Solo 正式签名配置与发布包准备

本文档用于把当前项目从“可测试构建”推进到“可正式提审的发布包准备状态”。

---

## 1. 当前仓库已经完成的内容

当前 Android 构建已支持以下逻辑：

- 优先读取 `game_app/android/key.properties`
- 若未提供正式签名信息，则回退到 debug 签名，方便继续测试
- 支持通过环境变量注入正式签名信息，便于本地或 CI 使用

支持的环境变量：

- `ANDROID_KEYSTORE_PATH`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

---

## 2. 正式签名文件放置位置

建议使用以下目录结构：

- 签名配置文件：`game_app/android/key.properties`
- keystore 文件目录：`game_app/android/keystore/`

仓库中已提供：

- `game_app/android/key.properties.example`
- `game_app/android/keystore/.gitignore`

请注意：

- `key.properties` 不应提交到仓库
- `.jks` / `.keystore` 文件不应提交到仓库

---

## 3. 生成 keystore 示例命令

如果你还没有正式签名证书，可在本地先生成一份：

```bash
keytool -genkeypair \
  -v \
  -keystore game_app/android/keystore/2048-solo-release.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias 2048-solo-release
```

执行后请保存好：

- keystore 文件
- store password
- key alias
- key password

这些信息丢失后会影响后续更新版本。

---

## 4. key.properties 填写方式

把示例文件复制为正式文件：

```bash
cp game_app/android/key.properties.example game_app/android/key.properties
```

然后填写真实信息：

```properties
storeFile=keystore/2048-solo-release.jks
storePassword=你的store密码
keyAlias=你的alias
keyPassword=你的key密码
```

说明：

- `storeFile` 可以是相对路径，也可以是绝对路径
- 相对路径默认相对于 `game_app/android/`

---

## 5. 环境变量方式（可选）

如果你不想在本地落 `key.properties`，也可以直接使用环境变量：

```bash
export ANDROID_KEYSTORE_PATH="/absolute/path/to/2048-solo-release.jks"
export ANDROID_KEYSTORE_PASSWORD="your-store-password"
export ANDROID_KEY_ALIAS="2048-solo-release"
export ANDROID_KEY_PASSWORD="your-key-password"
```

这种方式更适合：

- CI
- 云构建
- 不希望在工作目录保留签名配置明文的场景

---

## 6. 构建正式 APK

在 `game_app` 目录执行：

```bash
flutter build apk --release
```

输出路径：

```text
game_app/build/app/outputs/flutter-apk/app-release.apk
```

---

## 7. 构建 App Bundle（可选）

如果后续某些渠道或流程需要 AAB，可执行：

```bash
flutter build appbundle --release
```

输出路径通常为：

```text
game_app/build/app/outputs/bundle/release/app-release.aab
```

注意：

- 中国安卓市场通常更常见直接上传 APK
- 但你仍可保留 AAB 作为归档或未来渠道使用

---

## 8. 发布前还要检查什么

正式提审前，至少建议再确认：

1. 包名是否为最终包名  
   当前仍是：`com.sunfu.game_app`

2. 版本号是否为正式版本  
   建议同步更新 `pubspec.yaml` 中的 `version`

3. 是否已切换到正式签名  
   不要用 debug fallback 去正式提审

4. 隐私政策链接是否已经是公网正式地址

5. App 内隐私弹窗、用户协议、设置页入口是否与最终文案一致

6. 若按游戏提交，是否已确认软著 / 版号 / 主体策略

---

## 9. 当前项目的现实建议

对当前版本最实际的做法是：

1. 先确定最终包名
2. 生成正式 keystore
3. 配好 `key.properties`
4. 构建正式签名 APK
5. 再进入国内各市场提审流程

---

## 10. 风险提醒

- keystore 一旦用于正式发布，后续版本更新应持续使用同一套签名
- 不要把 keystore 和 `key.properties` 提交到仓库
- 如果准备多渠道投放，建议统一维护一套正式签名体系

