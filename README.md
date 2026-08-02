# AskAIDemo v2.1 · iPhone 本机大模型 + Siri 替代

> 完整可运行 iOS Demo
>
> 适用设备:**iPhone 17 Pro Max / 16 Pro / 15 Pro**(有 Action Button,8GB+ RAM)
>
> 目标系统:**iOS 18.0+**
>
> 技术栈:SwiftUI + App Intents + MLX Swift(Apple 官方本地推理)

## 两种运行模式

| 模式 | LLM 位置 | 优点 | 缺点 |
|---|---|---|---|
| **本机推理 (MLX)** | iPhone 内部 | 离线、隐私、即时 | 速度中等 |
| **云端 API** | Ollama / DeepSeek / OpenAI | 强、快 | 需联网 |

设置里切换。

## 编译方式

| 方式 | 系统 | 说明 |
|---|---|---|
| **Xcode 直连** | macOS | 开发首选(详见下面 Mac 教程) |
| **GitHub Actions 云端编译** | **Windows / Linux / Mac 都行** | 跑云端 Mac runner,出 ipa,AltStore 装 iPhone |

---

# A. Windows 用户路线:GitHub Actions + AltStore(零 Mac)

完整 Windows 流程,**不需要 Mac**。

## A.1 准备 GitHub 账号

- 注册 https://github.com
- 建个空仓库:`AskAIDemo`,**不要勾选** Add README / .gitignore / license

## A.2 推代码到 GitHub

**Windows PowerShell**:

```powershell
# 1. 装 Git:https://git-scm.com/download/win
# 2. 解压 zip
Expand-Archive .\AskAIDemo.zip
cd AskAIDemo

# 3. 初始化 + 提交
git init
git config user.email "你的邮箱"
git config user.name "你的名字"
git add .
git commit -m "init"

# 4. 推到 GitHub(替换你的用户名)
git remote add origin https://github.com/你的用户名/AskAIDemo.git
git branch -M main
git push -u origin main
```

**认证**:GitHub 现在不让用密码,需要 [Personal Access Token](https://github.com/settings/tokens):
- Settings → Developer settings → Personal access tokens → Tokens (classic)
- Generate new token,勾 `repo`
- 复制 token,推送时密码贴这个

## A.3 触发构建

两种方式触发 GitHub Actions:

**方式 1:push 自动触发**(刚 push 完就触发)
- 推送后 GitHub 仓库页面 → **Actions** tab
- 看到 "Build AskAIDemo iOS" 在跑
- 第一次 **10-15 分钟**(MLX 依赖大)
- 后续 3-5 分钟(有缓存)

**方式 2:手动触发**
- 仓库 → Actions → "Build AskAIDemo iOS" → **Run workflow** → 选 Release/Debug → Run

## A.4 下载 ipa

- 仓库 → Actions → 点完成的 run
- 底部 **Artifacts** 区域
- 下载 **AskAIDemo-unsigned.zip**(包含 .ipa 文件)
- 解压得到 `AskAIDemo.ipa`

## A.5 AltStore 装到 iPhone

### 装 AltStore 前置

1. **Windows 装 iTunes** (从 Microsoft Store 装,**不是** Apple 官网那个)
2. **Windows 装 iCloud**(Microsoft Store)—— 仅登录用
3. **iPhone 开启开发者模式**:
   - iPhone → 设置 → 隐私与安全 → **开发者模式** → 开
   - 重启 iPhone

### 装 AltStore

1. **下载 AltServer**:https://altstore.io/ → 点 Windows 图标
2. 解压,运行 `AltInstaller.exe`(管理员)
3. 完成后桌面 / 开始菜单会有 AltServer
4. 运行 AltServer(右下角托盘有图标)
5. **数据线连 iPhone** 到 Windows,iTunes 弹"信任此电脑"→ iPhone 也点信任
6. AltServer 托盘图标 → **Install AltStore** → 选你的 iPhone
7. 弹窗填 **Apple ID + 密码**(免费 ID 就行,只用于签名)
8. 30 秒后 iPhone 桌面出现 **AltStore** App
9. 如果 Apple ID 没用过 2FA,要 App 专用密码:https://appleid.apple.com → App-Specific Passwords

### 用 AltStore 装 ipa

1. iPhone 打开 **AltStore** App
2. **My Apps** tab
3. 左上角 **+** 号
4. 选 **AskAIDemo.ipa** 文件(可以通过 iCloud Drive / Files / AirDrop 传到 iPhone)
5. 装好!

### 信任开发者

iPhone 装好后会闪退一次,正常:
1. iPhone → **设置** → **通用** → **VPN 与设备管理**
2. 找到你的 Apple ID → **信任**
3. 重新打开 AskAIDemo

## A.6 续期(7 天过期)

免费 Apple ID 签名 **只有 7 天**,过期需要续签:

- iPhone **连 Windows + 打开 AltServer**
- AltStore App → My Apps → 看到 **"Expires in X days"**
- 过期前会提醒,**点 Refresh** 自动续
- 续期需要 AltServer 在 Windows 后台跑 + iPhone 连着

**或者** GitHub Actions 重新构建(改动任意文件 push 一下),下载新 ipa 重新装。

## A.7 装好后的配置(同 macOS)

1. 打开 **问 AI** App
2. 允许麦克风 + 语音识别
3. 点 **⚙️ 设置**
4. 模式选 **云端 API**(本机模式在 Windows 路线下用不到)
5. 预设选 **Ollama 全本地(Mac)**,改 endpoint 为你的 Windows Ollama IP
6. Model 填 `qwen2.5:7b`,API Key 留空
7. 保存

## A.8 Windows 跑 Ollama

如果还没配 Windows Ollama,见本文档 §"C. Windows 跑 Ollama"。

---

# B. Mac 用户路线(开发首选)

## B.1 Mac 装工具

```bash
xcode-select --install
brew install xcodegen
```

## B.2 打开工程

```bash
cd AskAIDemo
xcodegen generate
open AskAIDemo.xcodeproj
```

Xcode 首次打开会下载 SwiftPM 依赖(mlx-swift,1-3 分钟)。

## B.3 签名 + 选设备

- 选 `AskAIDemo` target → **Signing & Capabilities**
- Team:选 Apple ID
- Bundle ID:改唯一
- Scheme 选 iPhone

## B.4 Run

- 数据线连 iPhone
- ▶ Run(⌘R)
- 第一次编译 1-2 分钟
- 装好后 iPhone 弹"无法验证 App" → 设置 → 通用 → VPN与设备管理 → 信任

**后续流程同 A.5 之后**。

---

# C. Windows 跑 Ollama(本机 LLM 后端)

## C.1 装 Ollama

**前置**:Windows 11 22H2+,推荐 NVIDIA 独显

```powershell
# 官网下载:https://ollama.com/download/OllamaSetup.exe
# 或 winget
winget install Ollama.Ollama
```

## C.2 拉模型

```powershell
ollama pull qwen2.5:7b
# 4.5GB,5-30 分钟
```

## C.3 允许局域网访问

**Win+R** → `sysdm.cpl` → 高级 → 环境变量 → 系统变量 → 新建:

| 变量名 | 变量值 |
|---|---|
| `OLLAMA_HOST` | `0.0.0.0` |
| `OLLAMA_ORIGINS` | `*` |

重启 Ollama(任务栏图标右键 → Quit,再开)。

## C.4 防火墙放行

**管理员 PowerShell**:
```powershell
New-NetFirewallRule -DisplayName "Ollama" -Direction Inbound `
  -LocalPort 11434 -Protocol TCP -Action Allow
```

## C.5 查 IP + 测试

```powershell
ipconfig
# 记下 IPv4,例:192.168.1.20
```

iPhone 浏览器(同一 WiFi)打开 `http://192.168.1.20:11434` → 应返回 `Ollama is running`

---

# D. 故障排查

## D.1 GitHub Actions 构建失败

| 报错 | 原因 | 修法 |
|---|---|---|
| `brew: command not found` | 罕见,缓存问题 | 重跑 workflow |
| `xcodebuild: error` | 项目未生成 | 检查 xcodegen 步骤 |
| `No such module 'MLX'` | SwiftPM 没下载完 | 等 Resolve packages 步骤完成 |
| `archivePath not found` | archive 失败 | 看上面日志 |
| 缓存命中失败 | 第一次,正常 | 不用管,会自动下 |

**手动重跑**:
- Actions → 失败的 run → 右上 **Re-run jobs**

## D.2 ipa 装不上

| 现象 | 原因 | 修法 |
|---|---|---|
| AltStore 装时白屏 | Apple ID 错 | 重新填,注意用 App-Specific Password |
| "无法连接到服务器" | iTunes 没装 | Microsoft Store 装最新版 |
| 装完闪退 | 没信任开发者 | 设置 → 通用 → VPN与设备管理 → 信任 |
| "证书无效" | 7 天过期 | AltStore Refresh 续签 |
| 提示"Unable to install" | Bundle ID 冲突 | 改 project.yml 的 bundleIdPrefix |

## D.3 iPhone 找不到 AltStore App

- 装完可能要 1-2 分钟才出现在桌面
- Spotlight 搜"AltStore"
- 设置 → 通用 → iPhone 存储空间,看是否真装了

## D.4 运行时 LLM 调不通

- iPhone 和 Windows 同一 WiFi?
- Windows 防火墙挡了 11434?(看 C.4)
- OLLAMA_HOST 配了 0.0.0.0?(看 C.3)
- iPhone 浏览器能访问 Windows 的 11434 吗?

## D.5 7 天签名过期频繁

AltStore 在 Windows 上跑时,**iPhone 必须能跟 Windows 通信**(USB 连着或同一 WiFi)。
- 不用时拔数据线 OK
- 续签前连上数据线
- 实在嫌烦:考虑 Apple Developer $99/年,1 年有效

---

# E. 性能数据

| 设备 | 模式 | 短回答(50字) | 长回答(200字) |
|---|---|---|---|
| iPhone 17 Pro Max + 本机 MLX | 离线 | 1-5 秒 | 10-30 秒 |
| iPhone + Windows Ollama (RTX 3060) | 局域网 | 1-2 秒 | 5-8 秒 |
| iPhone + Windows Ollama (CPU only) | 局域网 | 5-15 秒 | 30-60 秒 |
| iPhone + DeepSeek 云端 | 互联网 | 2-4 秒 | 6-10 秒 |

---

# F. 项目结构

```
AskAIDemo/
├── .github/
│   ├── workflows/
│   │   └── build-ios.yml     # ⭐ GitHub Actions 编译工作流
│   └── ISSUE_TEMPLATE/
├── project.yml                # XcodeGen 配置 + SwiftPM 依赖
├── README.md                  # 本文件
├── .gitignore
└── AskAIDemo/
    ├── AskAIDemoApp.swift     # 入口
    ├── VoiceChatView.swift    # 全屏语音 UI
    ├── VoiceController.swift  # ASR + LLM + TTS
    ├── ContentView.swift      # 文字聊天 + 设置 + 模型管理
    ├── LocalLLMEngine.swift   # MLX 本地推理(本机模式)
    ├── LLMClient.swift        # 统一客户端
    ├── LLMConfig.swift        # 远程配置
    ├── ConversationStore.swift
    ├── AskAIIntent.swift      # Siri 触发
    ├── Info.plist
    └── Assets.xcassets/
```

---

# G. 升级 / 二次开发

## G.1 改 Swift 代码

1. 在 GitHub 网页直接改(简单)或 clone 到本地
2. commit + push
3. GitHub Actions 自动构建
4. 下载新 ipa,AltStore 装(会覆盖旧版)

## G.2 换 Bundle ID

改 `project.yml` 里 `bundleIdPrefix: com.example` → `bundleIdPrefix: com.你的域名`,重跑 workflow。

## G.3 换签名方式(用付费 Apple Developer)

把 `.github/workflows/build-ios.yml` 里:
```yaml
CODE_SIGNING_ALLOWED=NO
```
改成:
```yaml
CODE_SIGN_IDENTITY="Apple Development"
```
并加 secrets(Apple ID + 团队 ID),复杂,不推荐免费用。

## G.4 加 MLX 流式

`LocalLLMEngine.swift` 的 `generate(messages:onToken:)` 已经支持流式 token 回调,可以接 TTS 边生成边朗读。

---

# H. License

企业内部 Demo,自由使用。

**祝玩得开心,有问题随时问!**
