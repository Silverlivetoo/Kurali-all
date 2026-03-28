#!/usr/bin/env python3
"""
KuraliAll v2.2.0 — 终端 GUI 版 (curses)
无需 X11/tkinter，纯终端图形界面
"""
import os, sys, curses, subprocess, time, tempfile, shutil, tarfile, zipfile, stat
from pathlib import Path

VERSION = "2.2.0"

# 自动检测数据目录路径（支持 Linux 和 Windows）
if os.name == 'nt' or os.path.exists("/var/lib/kuraliAll"):
    default_home = os.environ.get("KURALI_HOME")
    if default_home:
        KURALI_HOME = Path(default_home)
    elif os.name == 'nt':
        KURALI_HOME = Path(os.environ.get("LOCALAPPDATA", str(Path.home() / "AppData" / "Local"))) / "kuraliAll"
    else:
        KURALI_HOME = Path("/var/lib/kuraliAll")
else:
    KURALI_HOME = Path("/var/lib/kuraliAll")

PKG_DIR = KURALI_HOME / "pkg"

# ─── 颜色对 ───
def init_colors():
    curses.start_color()
    curses.use_default_colors()
    curses.init_pair(1, curses.COLOR_GREEN, -1)   # OK
    curses.init_pair(2, curses.COLOR_RED, -1)      # Error
    curses.init_pair(3, curses.COLOR_YELLOW, -1)   # Warning
    curses.init_pair(4, curses.COLOR_CYAN, -1)     # Info
    curses.init_pair(5, curses.COLOR_WHITE, curses.COLOR_BLUE)   # Header
    curses.init_pair(6, curses.COLOR_BLACK, curses.COLOR_CYAN)   # Selected
    curses.init_pair(7, curses.COLOR_WHITE, -1)    # Normal

# ─── 界面 ───
def draw_header(win, title):
    h, w = win.getmaxyx()
    win.attron(curses.color_pair(5) | curses.A_BOLD)
    header = f" KuraliAll v{VERSION} — {title} "
    win.addstr(0, (w - len(header))//2, header[:w-1])
    win.attroff(curses.color_pair(5) | curses.A_BOLD)

def draw_footer(win, text):
    h, w = win.getmaxyx()
    win.attron(curses.color_pair(4))
    win.addstr(h-1, 1, text[:w-2])
    win.attroff(curses.color_pair(4))

def draw_box(win, y, x, h, w, title=""):
    win.addch(y, x, curses.ACS_ULCORNER)
    win.addch(y, x+w-1, curses.ACS_URCORNER)
    win.addch(y+h-1, x, curses.ACS_LLCORNER)
    win.addch(y+h-1, x+w-1, curses.ACS_LRCORNER)
    for i in range(1, w-1):
        win.addch(y, x+i, curses.ACS_HLINE)
        win.addch(y+h-1, x+i, curses.ACS_HLINE)
    for i in range(1, h-1):
        win.addch(y+i, x, curses.ACS_VLINE)
        win.addch(y+i, x+w-1, curses.ACS_VLINE)
    if title:
        win.attron(curses.A_BOLD)
        win.addstr(y, x+2, f" {title} ")
        win.attroff(curses.A_BOLD)

def get_packages():
    packages = []
    if PKG_DIR.exists():
        for d in sorted(PKG_DIR.iterdir()):
            if d.is_dir():
                info_file = d / f"{d.name}.info"
                if info_file.exists():
                    meta = {}
                    for line in info_file.read_text().splitlines():
                        if '=' in line:
                            k,v = line.split('=',1)
                            meta[k] = v
                    packages.append(meta)
                else:
                    packages.append({"name": d.name, "format":"?", "version":"?", "mode":"?"})
    return packages

def run_cmd(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except:
        return None

def detect_format(filename):
    fn = filename.lower()
    if fn.endswith('.deb'): return 'deb'
    if fn.endswith('.rpm'): return 'rpm'
    if fn.endswith('.pacman'): return 'pacman'
    if '.pkg.tar' in fn: return 'pacman'
    if fn.endswith('.kurali'): return 'kurali'
    if fn.endswith('.appimage'): return 'appimage'
    if any(fn.endswith(e) for e in ['.tar.gz','.tar.xz','.tar.bz2','.tar.zst','.tgz','.txz']): return 'tar'
    if fn.endswith('.apk'): return 'apk'      # Alpine Linux 包格式（⚠ 非安卓 APK）
    if fn.endswith('.zip'): return 'zip'
    return 'unknown'

def extract_package(filepath, fmt, dest):
    dest = Path(dest); dest.mkdir(parents=True, exist_ok=True)
    try:
        if fmt == 'deb':
            subprocess.run(['dpkg-deb','-x',str(filepath),str(dest)], capture_output=True)
        elif fmt == 'rpm':
            subprocess.run(f"rpm2cpio '{filepath}' | cpio -idm", shell=True, cwd=str(dest), capture_output=True)
        elif fmt == 'pacman':
            with tarfile.open(filepath) as tf: tf.extractall(dest)
            for f in ['.PKGINFO','.MTREE','.INSTALL']:
                p = dest/f; p.unlink(missing_ok=True)
        elif fmt == 'appimage':
            shutil.copy2(filepath, dest)
            os.chmod(dest/Path(filepath).name, (dest/Path(filepath).name).stat().st_mode | stat.S_IEXEC)
        elif fmt == 'tar':
            with tarfile.open(filepath) as tf: tf.extractall(dest)
        elif fmt == 'zip':
            with zipfile.ZipFile(filepath) as zf: zf.extractall(dest)
        elif fmt == 'apk':
            # Alpine Linux 包格式（⚠ 不是安卓 APK！）
            with tarfile.open(filepath, 'r:gz') as tf: tf.extractall(dest)
            import glob as _glob
            for meta in ['.PKGINFO','.MTREE','.INSTALL','.BUILDINFO']:
                for f in _glob.glob(str(dest / meta)):
                    Path(f).unlink(missing_ok=True)
            for f in _glob.glob(str(dest / '.SIGN.*')):
                Path(f).unlink(missing_ok=True)
        elif fmt == 'kurali':
            with tarfile.open(filepath) as tf: tf.extractall(dest)
            rootfs = dest / "rootfs"
            if rootfs.exists():
                for item in rootfs.iterdir():
                    shutil.move(str(item), str(dest / item.name))
                shutil.rmtree(rootfs)
        else:
            return False
        return True
    except:
        return False

# ─── 主菜单 ───
def main_menu(stdscr):
    init_colors()
    curses.curs_set(0)
    selected = 0
    packages = []
    last_refresh = 0
    status_msg = ""
    status_color = 1

    menu_items = [
        ("📦  安装软件包",   "install"),
        ("🗑️   卸载软件包",   "remove"),
        ("📋  已安装列表",   "list"),
        ("🔍  搜索软件包",   "search"),
        ("ℹ️   查看详情",     "info"),
        ("🧪  依赖检查",     "deps"),
        ("⚡  内存模式运行", "ram"),
        ("🔄  刷新列表",     "refresh"),
        ("❓  帮助",         "help"),
        ("🚪  退出",         "quit"),
    ]

    while True:
        stdscr.clear()
        h, w = stdscr.getmaxyx()

        # Header
        draw_header(stdscr, "全能 Linux 包管理器")

        # 包列表
        now = time.time()
        if now - last_refresh > 5 or not packages:
            packages = get_packages()
            last_refresh = now

        # 左侧：菜单
        menu_w = 30
        draw_box(stdscr, 2, 0, len(menu_items)+2, menu_w, "菜单")
        for i, (label, _) in enumerate(menu_items):
            y = 3 + i
            if i == selected:
                stdscr.attron(curses.color_pair(6) | curses.A_BOLD)
                stdscr.addstr(y, 1, f" {label:<{menu_w-3}} ")
                stdscr.attroff(curses.color_pair(6) | curses.A_BOLD)
            else:
                stdscr.attron(curses.color_pair(7))
                stdscr.addstr(y, 1, f" {label:<{menu_w-3}} ")
                stdscr.attroff(curses.color_pair(7))

        # 右侧：包列表
        list_x = menu_w + 2
        list_w = w - list_x - 1
        list_h = min(len(packages)+3, h-6) if packages else 5
        if list_h < 4: list_h = 4
        draw_box(stdscr, 2, list_x, list_h, list_w, f"已安装 ({len(packages)})")

        if packages:
            stdscr.attron(curses.color_pair(4) | curses.A_BOLD)
            stdscr.addstr(3, list_x+2, f"{'包名':<18} {'格式':<8} {'版本':<8} {'模式'}")
            stdscr.attroff(curses.color_pair(4) | curses.A_BOLD)
            for i, p in enumerate(packages[:list_h-4]):
                name = p.get('name','?')[:17]
                fmt = p.get('format','?')[:7]
                ver = p.get('version','?')[:7]
                mode = p.get('mode','sandbox')
                stdscr.addstr(4+i, list_x+2, f"{name:<18} {fmt:<8} {ver:<8} {mode}")
        else:
            stdscr.attron(curses.color_pair(3))
            stdscr.addstr(3, list_x+2, "暂无已安装的包")
            stdscr.attroff(curses.color_pair(3))

        # 状态栏
        if status_msg:
            stdscr.attron(curses.color_pair(status_color))
            stdscr.addstr(h-2, 1, f" {status_msg} "[:w-2])
            stdscr.attroff(curses.color_pair(status_color))

        # 底部
        draw_footer(stdscr, "↑↓ 选择 | Enter 确认 | q 退出 | r 刷新")

        # 输入
        try:
            key = stdscr.getch()
        except:
            continue

        if key == ord('q') or key == ord('Q'):
            break
        elif key == curses.KEY_UP:
            selected = (selected - 1) % len(menu_items)
        elif key == curses.KEY_DOWN:
            selected = (selected + 1) % len(menu_items)
        elif key == ord('r') or key == ord('R'):
            packages = get_packages()
            last_refresh = time.time()
            status_msg = "已刷新"
            status_color = 1
        elif key == curses.KEY_ENTER or key == 10 or key == 13:
            action = menu_items[selected][1]

            if action == "quit":
                break
            elif action == "list":
                # 显示已安装列表
                if not packages:
                    status_msg = "暂无已安装的包"
                    status_color = 3
                else:
                    lines = ["已安装的软件包:", ""]
                    for p in packages:
                        name = p.get('name', '?')
                        ver = p.get('version', '?')
                        fmt = p.get('format', '?')
                        mode = p.get('mode', 'sandbox')
                        lines.append(f"  {name} ({ver}) [{fmt}] {mode}")
                    pop_h = min(len(lines)+4, h-6)
                    pop_w = min(50, w-4)
                    py = (h-pop_h)//2; px = (w-pop_w)//2
                    draw_box(stdscr, py, px, pop_h, pop_w, "已安装列表")
                    for i, line in enumerate(lines[:pop_h-3]):
                        stdscr.addstr(py+1+i, px+2, line[:pop_w-4])
                    draw_footer(stdscr, "按任意键返回")
                    stdscr.getch()
                continue
            elif action == "refresh":
                packages = get_packages()
                last_refresh = time.time()
                status_msg = "已刷新"
                status_color = 1
            elif action == "install":
                curses.curs_set(1)
                stdscr.addstr(h-2, 1, " 文件路径: ")
                curses.echo()
                filepath = stdscr.getstr(h-2, 12, 80).decode()
                curses.noecho()
                curses.curs_set(0)
                if filepath:
                    stdscr.addstr(h-2, 1, " 安装中...".ljust(w-2))
                    stdscr.refresh()
                    # 调用 kuraliAll.py 而不是 gui 自身
                    gui_path = Path(__file__).parent / "kuraliAll.py"
                    r = run_cmd(["python3", str(gui_path), "i", filepath, "-y"])
                    if r and r.returncode == 0:
                        status_msg = f"安装成功: {filepath}"
                        status_color = 1
                    else:
                        err_msg = r.stderr[:80] if r and r.stderr else r.stdout[:80] if r and r.stdout else '未知错误'
                        status_msg = f"安装失败: {err_msg}"
                        status_color = 2
                    packages = get_packages()
            elif action == "remove":
                if not packages:
                    status_msg = "没有可卸载的包"
                    status_color = 3
                    continue
                curses.curs_set(1)
                stdscr.addstr(h-2, 1, " 包名: ")
                curses.echo()
                name = stdscr.getstr(h-2, 8, 40).decode()
                curses.noecho()
                curses.curs_set(0)
                if name:
                    gui_path = Path(__file__).parent / "kuraliAll.py"
                    r = run_cmd(["python3", str(gui_path), "r", name, "-y"])
                    if r and r.returncode == 0:
                        status_msg = f"已卸载: {name}"
                        status_color = 1
                    else:
                        err_msg = r.stderr[:80] if r and r.stderr else r.stdout[:80] if r and r.stdout else '未知错误'
                        status_msg = f"卸载失败: {err_msg}"
                        status_color = 2
                    packages = get_packages()
            elif action == "info":
                if not packages:
                    status_msg = "没有已安装的包"
                    status_color = 3
                    continue
                curses.curs_set(1)
                stdscr.addstr(h-2, 1, " 包名: ")
                curses.echo()
                name = stdscr.getstr(h-2, 8, 40).decode()
                curses.noecho()
                curses.curs_set(0)
                if name:
                    info_file = PKG_DIR / name / f"{name}.info"
                    if info_file.exists():
                        info_text = info_file.read_text()
                        lines = info_text.splitlines()
                        pop_h = min(len(lines)+4, h-6)
                        pop_w = min(50, w-4)
                        py = (h-pop_h)//2
                        px = (w-pop_w)//2
                        draw_box(stdscr, py, px, pop_h, pop_w, f" {name} 详情 ")
                        for i, line in enumerate(lines[:pop_h-3]):
                            stdscr.addstr(py+1+i, px+2, line[:pop_w-4])
                        draw_footer(stdscr, "按任意键返回")
                        stdscr.getch()
                    else:
                        status_msg = f"未找到: {name}"
                        status_color = 2
            elif action == "deps":
                curses.curs_set(1)
                stdscr.addstr(h-2, 1, " 文件路径 (空=系统检查): ")
                curses.echo()
                target = stdscr.getstr(h-2, 28, 80).decode()
                curses.noecho()
                curses.curs_set(0)
                if target:
                    r = run_cmd(["ldd", target])
                    if r:
                        lines = r.stdout.splitlines()
                        pop_h = min(len(lines)+4, h-6)
                        pop_w = min(50, w-4)
                        py = (h-pop_h)//2
                        px = (w-pop_w)//2
                        draw_box(stdscr, py, px, pop_h, pop_w, "依赖检查")
                        for i, line in enumerate(lines[:pop_h-3]):
                            color = 2 if 'not found' in line else 1
                            stdscr.attron(curses.color_pair(color))
                            stdscr.addstr(py+1+i, px+2, line[:pop_w-4])
                            stdscr.attroff(curses.color_pair(color))
                        draw_footer(stdscr, "按任意键返回")
                        stdscr.getch()
                    else:
                        status_msg = "ldd 不可用"
                        status_color = 2
                else:
                    # 系统依赖检查
                    r = run_cmd(["ldd", "--version"])
                    glibc = r.stdout.split("\n")[0] if r else "unknown"
                    lines = [f"glibc: {glibc}", ""]
                    for lib in ['libc.so','libm.so','libdl.so','libpthread.so','libz.so']:
                        r2 = run_cmd(["ldconfig","-p"])
                        found = r2 and lib in r2.stdout
                        mark = "✓" if found else "✗"
                        lines.append(f"  {mark} {lib}")
                    pop_h = min(len(lines)+4, h-6)
                    pop_w = min(50, w-4)
                    py = (h-pop_h)//2; px = (w-pop_w)//2
                    draw_box(stdscr, py, px, pop_h, pop_w, "系统依赖")
                    for i, line in enumerate(lines[:pop_h-3]):
                        color = 1 if '✓' in line else 2 if '✗' in line else 4
                        stdscr.attron(curses.color_pair(color))
                        stdscr.addstr(py+1+i, px+2, line[:pop_w-4])
                        stdscr.attroff(curses.color_pair(color))
                    draw_footer(stdscr, "按任意键返回")
                    stdscr.getch()
            elif action == "ram":
                curses.curs_set(1)
                stdscr.addstr(h-2, 1, " 文件路径: ")
                curses.echo()
                filepath = stdscr.getstr(h-2, 12, 80).decode()
                curses.noecho()
                curses.curs_set(0)
                if filepath:
                    # 退出 curses 执行 RAM 模式，结束后恢复
                    curses.endwin()
                    print(f"\n{'='*50}")
                    print(f"  RAM 模式运行: {filepath}")
                    print(f"{'='*50}\n")
                    gui_path = Path(__file__).parent / "kuraliAll.py"
                    r = subprocess.run(["python3", str(gui_path), "run", filepath])
                    input("\n按回车返回 GUI...")
                    stdscr.refresh()
                    stdscr.clear()
            elif action == "help":
                lines = [
                    "KuraliAll v2.1 快捷帮助",
                    "",
                    "i  安装软件包      r  卸载软件包",
                    "l  列出已安装      f  查看包详情",
                    "s  搜索软件包      deps 依赖检查",
                    "run 内存模式运行   q  退出",
                    "",
                    "快捷键: ↑↓ 导航 | Enter 确认",
                    "        r 刷新    | q 退出",
                    "",
                    "支持格式: .deb .rpm .pkg.tar",
                    "          AppImage .tar.* .zip",
                ]
                pop_h = min(len(lines)+3, h-6)
                pop_w = min(44, w-4)
                py = (h-pop_h)//2; px = (w-pop_w)//2
                draw_box(stdscr, py, px, pop_h, pop_w, "帮助")
                for i, line in enumerate(lines[:pop_h-3]):
                    stdscr.attron(curses.A_BOLD if i==0 else 0)
                    stdscr.addstr(py+1+i, px+2, line[:pop_w-4])
                    stdscr.attroff(curses.A_BOLD if i==0 else 0)
                draw_footer(stdscr, "按任意键返回")
                stdscr.getch()
            elif action == "search":
                curses.curs_set(1)
                stdscr.addstr(h-2, 1, " 搜索关键词: ")
                curses.echo()
                kw = stdscr.getstr(h-2, 15, 40).decode().lower()
                curses.noecho()
                curses.curs_set(0)
                if kw:
                    results = [p for p in packages if kw in p.get('name','').lower()]
                    if results:
                        lines = [f"搜索: '{kw}'"]
                        for p in results:
                            lines.append(f"  {p['name']} ({p.get('version','?')})")
                        pop_h = min(len(lines)+3, h-6)
                        pop_w = min(40, w-4)
                        py = (h-pop_h)//2; px = (w-pop_w)//2
                        draw_box(stdscr, py, px, pop_h, pop_w, "搜索结果")
                        for i, line in enumerate(lines[:pop_h-3]):
                            stdscr.addstr(py+1+i, px+2, line[:pop_w-4])
                    else:
                        status_msg = f"未找到匹配 '{kw}'"
                        status_color = 3
                    if results:
                        draw_footer(stdscr, "按任意键返回")
                        stdscr.getch()

        stdscr.refresh()

def main():
    if len(sys.argv) > 1 and sys.argv[1] in ('i','install','r','remove','run','exec'):
        # CLI 模式支持从 GUI 调用 - 跳转到 kuraliAll.py
        gui_dir = Path(__file__).parent
        cli_path = gui_dir / "kuraliAll.py"
        # 使用 subprocess 调用而不是 import，避免模块状态混乱
        os.execv(sys.executable, [sys.executable, str(cli_path)] + sys.argv[1:])

    PKG_DIR.mkdir(parents=True, exist_ok=True)
    curses.wrapper(main_menu)

if __name__ == '__main__':
    main()
