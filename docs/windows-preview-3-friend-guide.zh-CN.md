# Campus Dashboard Windows Preview 3 朋友测试指南

这是一份面向 Windows 11 x64 测试者的简明指南。Preview 3 是未签名的测试版本，包含只读 Canvas 同步和高级 SIweb 课表测试功能，不包含 iCloud、Apple Calendar、Outlook、Microsoft Graph、Google Calendar、CalDAV 或其他外部日历连接。

## 1. 下载并核对文件

只从项目的 GitHub `v0.1.0-windows-preview.3` 预发布页面下载：

- `CampusDashboard-Windows-0.1.0-portable-x64.zip`
- `SHA256SUMS.txt`

在下载目录打开 PowerShell，运行：

```powershell
$expected = (Get-Content .\SHA256SUMS.txt).Split()[0].ToLower()
$actual = (Get-FileHash .\CampusDashboard-Windows-0.1.0-portable-x64.zip -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $expected) { throw "SHA-256 不一致，请停止并重新下载。" }
"校验通过：$actual"
```

正确的 Preview 3 ZIP SHA-256 是：

```text
d18b32e760a19acd4d81e0d07abfd884c3a15736a5e90b0db637c94ac99b2c7d
```

如果结果不一致，不要解压或运行文件。

## 2. 首次启动

1. 把 ZIP 完整解压到一个新文件夹，不要只取出 `CampusDashboard.exe`。
2. 运行 `CampusDashboard.exe`。
3. 如果提示缺少 Windows App Runtime，先运行同一文件夹内的 `WindowsAppRuntimeInstaller.exe`，再启动应用。
4. 这是未签名测试版，Windows 可能显示未知发布者警告。只有在下载来源和 SHA-256 都正确时才继续。
5. 未连接学校来源前，确认界面明确标记当前内容是示例数据。

测试电脑不需要安装 Swift、Visual Studio 或其他开发工具。

## 3. 基础界面测试

请只记录通过或失败，不要在截图或报告里暴露学校资料。

- 打开 Today、Schedule、Tasks、Announcements、Needs Review、Settings 六个页面。
- 切换简体中文和英文，关闭应用后重新打开，确认语言选择被保留。
- 用键盘切换和激活主要控件。
- 分别在 Windows 显示缩放 100%、125%、150% 下检查按钮或文字是否被截断。
- 检查 Today 的提醒只在应用打开时显示，并明确说明目前没有后台提醒。

## 4. Canvas 只读测试

只在 Settings 中输入你获授权使用的 Canvas HTTPS 地址和个人访问令牌。令牌保存在 Windows Credential Manager，不会写入普通配置或离线快照。

1. 执行只读同步，确认 Today、Tasks 和 Announcements 能显示预期内容。
2. 完全关闭并重新打开应用，确认离线快照仍存在且不必重新输入令牌。
3. 断开网络后重开应用，确认缓存内容仍可查看，同时界面显示清楚的离线或错误状态。
4. 如果同时已连接 SIweb，选择 **Forget Canvas**，确认 Canvas 数据和凭据消失，但 SIweb 课表仍保留。

## 5. SIweb 只读高级测试

应用不会自动登录 SIweb，也不会绕过 SSO、验证码、MFA 或其他访问控制。

1. 在 Settings 选择 **Open SIweb in browser**，在系统浏览器中正常登录。
2. 打开浏览器开发者工具的 **Network** 面板，重新载入课表页并选择 `time_stud.asp` 请求。
3. 在 **Request Headers** 中，只复制 `Cookie:` 后面的值，不要复制 `Cookie:` 标签、密码、Authorization 请求头或完整请求。
4. 把 Cookie 值粘贴到应用的安全输入框，选择 **Save session and sync**。
5. 只核对课表数量和来源健康状态，不要把课程名称或课表内容写进报告。
6. 完全关闭并重开应用，确认课表快照仍存在。
7. 选择 **Forget SIweb**，确认 SIweb 凭据和课表消失，但 Canvas 数据仍保留。

Cookie 只应输入应用的安全字段，绝不能发送到 GitHub、聊天、截图、终端命令或问题报告。

## 6. 确认产品边界

请确认 Windows 版本中没有任何 iCloud 或外部日历设置、登录入口或权限请求。以下功能尚未包含，不能记为通过：

- 自动 SIweb 登录；
- DeepSeek；
- 后台刷新；
- Windows 原生后台通知；
- 已签名安装程序。

## 7. 反馈失败

在项目 GitHub Issues 提交反馈时，只提供：

- 版本 `v0.1.0-windows-preview.3`；
- ZIP SHA-256；
- Windows 版本、应用语言和显示缩放；
- 失败的是上面哪一步；
- 不含敏感资料的复现步骤和错误类别。

不要提交访问令牌、Cookie、学校网址、课程或任务内容、原始 API 响应、离线快照、Credential Manager 内容或包含私人资料的截图。需要截图时，请先退出学校来源并只使用示例数据。

更完整的升级、卸载、数据位置和隐私说明见 [Windows preview testing](windows-preview-testing.md)。
