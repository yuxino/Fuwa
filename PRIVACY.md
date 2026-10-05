# Privacy · Fuwa MyGo preview

## English

Fuwa MyGo captures only an explicitly selected window. Live frames and independent frozen images stay in native memory, and are cleared on unpin, quit, sleep, lock, session deactivation or recording-permission revocation. It does not save or upload captured pixels, window titles, process identities or the pin list. It has no analytics.

Screen Recording permission is requested on a pin attempt; Accessibility is requested only when you ask to reveal the original source. Matching uses public Accessibility APIs, not private window IDs or synthetic clicks. Ordinary app preferences (language, Dock behavior, shortcut and whether a screen permission request was attempted) are saved locally. macOS controls login-item registrations and system permission records.

Only a manual update check contacts GitHub's release API and the dedicated MyGo update feed. An explicit installation downloads the signed archive to a temporary local directory for verification and replacement. GitHub receives normal network request metadata, not screen content. There are no automatic checks. The stable Swift appcast is never consumed by this preview.

App identity and preferences are separate from stable Fuwa. Native UI test screenshots contain fixture data, not user captures. Operating-system diagnostics and permission records are managed by macOS.

## 中文

Fuwa MyGo 只捕获明确选中的窗口。实时画面和独立冻结图像仅保存在原生内存中，取消置顶、退出、睡眠、锁屏、会话切换或撤销录屏权限时清除。不保存或上传画面、窗口标题、进程身份或置顶列表，也没有使用统计。

置顶时才请求录屏权限，跳转原窗口时才请求辅助功能权限。窗口匹配使用公开辅助功能 API，不使用私有窗口 ID 或模拟点击。语言、Dock、快捷键及是否请求过录屏授权等普通偏好保存在本地，登录项和系统授权记录由 macOS 管理。

仅手动检查更新时访问 GitHub 发布 API 和独立 MyGo 更新源，明确点击安装后才下载签名包到本地临时目录用于验证和替换。GitHub 会接收普通网络请求信息，不会接收画面。没有自动检查，预览版不使用旧 Swift 更新源。

应用身份与设置和正式版独立。界面测试截图只含测试数据。操作系统诊断和权限记录由 macOS 管理。
