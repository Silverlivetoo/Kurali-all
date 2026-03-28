# MEMORY.md — KuraliAll 项目长期记忆

## 项目概述
- **名称**：KuraliAll v2.2.0，全能 Linux 包管理器
- **路径**：`c:\Users\SilverKurali\Downloads\kuraliall\kurali-all-main\`
- **功能**：在任意 Linux 发行版上离线安装任意格式软件包
- **版本**：Shell版 / Python版 / curses-GUI版 / WebUI版（四合一）

## 架构
- `kuraliAll.sh` —— 主程序（Shell），通过 `source` 加载 modules/ 模块
- `kuraliAll.py` —— Python 等价实现
- `kuraliAll-gui.py` —— curses 终端 GUI
- `kuraliAll-webui.py` —— 纯 Python 标准库 WebUI（60.5KB）
- `modules/` —— core / pkg-handler / ram-run / docker-run / desktop / service
- `hooks/` —— pre-install / post-install

## 支持格式
.deb .rpm .pkg.tar.* .apk(Alpine，非安卓) .kurali(自研) .AppImage .tar.* .zip

## 已修复的历史 Bug（2026-03-28）
详见 `2026-03-28.md`，共修复 ~15 处 Bug，覆盖 Python 版和 Shell 版

## 新增修复（2026-03-28 15:00）
1. **桌面图标问题**：即使没有图标文件也创建 .desktop 启动器（Shell版 + Python版 + WebUI版）
2. **RAM运行体验**：cmd_run 显示 PID 并提示如何关闭（kill命令）
3. **.kurali打包**：添加打包结果验证，显示直接运行命令，修复版本提取
4. **Python版桌面集成**：新增 install_desktop_entry_py / remove_desktop_entry_py 函数

## WebUI 修复（2026-03-28 15:08）
1. **数据目录路径**：自动检测操作系统，Windows 使用用户目录，Linux 使用 /var/lib/kuraliAll
2. **依赖检查逻辑**：修复 lib.replace('.so','') 错误，改为前缀匹配
3. **桌面图标集成**：WebUI 安装时自动创建 .desktop 启动器

## GUI 模式修复（2026-03-28 15:16）
1. **数据目录路径**：自动检测操作系统，Windows 使用用户目录
2. **安装功能**：修复调用错误，调用 kuraliAll.py 而不是自身
3. **卸载功能**：同样修复调用错误
4. **RAM 模式**：同样修复调用错误
5. **list 功能**：实现了显示已安装列表功能
6. **CLI 跳转**：使用 os.execv 正确跳转到 kuraliAll.py
