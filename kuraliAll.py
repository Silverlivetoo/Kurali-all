#!/usr/bin/env python3
"""
KuraliAll v2.1 — Python 版
全能 Linux 包管理器 | 纯 Python | 离线工作 | 跨发行版
"""
import os, sys, subprocess, shutil, tarfile, zipfile, tempfile, time, json, stat, re
from pathlib import Path
from datetime import datetime

VERSION = "2.2.0"

# ─── 颜色 ───
class C:
    R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'
    B='\033[1;34m'; CY='\033[1;36m'; BOLD='\033[1m'
    RESET='\033[0m'

# ─── 路径 ───
KURALI_HOME = Path(os.environ.get("KURALI_HOME", "/var/lib/kuraliAll"))
DB_DIR = KURALI_HOME / "db"
LOG_DIR = KURALI_HOME / "logs"
PKG_DIR = KURALI_HOME / "pkg"
BACKUP_DIR = KURALI_HOME / "backup"
CACHE_DIR = KURALI_HOME / "cache"

DISTRO_DB = {
    "debian":    ("Debian", "apt", "apt-get install -y", "apt-get remove -y"),
    "ubuntu":    ("Ubuntu", "apt", "apt-get install -y", "apt-get remove -y"),
    "rhel":      ("RHEL",   "yum", "yum install -y", "yum remove -y"),
    "centos":    ("CentOS", "yum", "yum install -y", "yum remove -y"),
    "fedora":    ("Fedora", "dnf", "dnf install -y", "dnf remove -y"),
    "arch":      ("Arch Linux", "pacman", "pacman -S --noconfirm", "pacman -Rs --noconfirm"),
    "manjaro":   ("Manjaro", "pacman", "pacman -S --noconfirm", "pacman -Rs --noconfirm"),
    "alpine":    ("Alpine", "apk", "apk add", "apk del"),
    "opensuse":  ("openSUSE", "zypper", "zypper install -y", "zypper remove -y"),
    "void":      ("Void Linux", "xbps", "xbps-install -Sy", "xbps-remove -Ry"),
    "gentoo":    ("Gentoo", "emerge", "emerge", "emerge -C"),
}

# ─── 工具函数 ───
def log(level, color, msg):
    ts = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    try:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        with open(LOG_DIR / "kuraliAll.log", "a") as f:
            f.write(f"[{ts}] [{level}] {msg}\n")
    except: pass
    print(f"{color}[{level}]{C.RESET} {msg}", file=sys.stderr)

def info(m): log("INFO", C.B, m)
def ok(m):   log("OK", C.G, m)
def warn(m): log("WARN", C.Y, m)
def err(m):  log("ERROR", C.R, m)
def die(m):  err(m); sys.exit(1)

def confirm(prompt):
    if "--yes" in sys.argv or "-y" in sys.argv: return True
    return input(f"{C.Y}[?]{C.RESET} {prompt} [y/N] ").lower() == 'y'

def run_cmd(cmd, **kw):
    try: return subprocess.run(cmd, capture_output=True, text=True, **kw)
    except: return None

def has_cmd(c): return shutil.which(c) is not None

def ensure_root():
    if os.geteuid() != 0:
        die("需要 root 权限")

def safe_copy(src, dst, backup=True):
    dst = Path(dst)
    if backup and dst.exists():
        bak = BACKUP_DIR / f"{dst}.{int(time.time())}.bak"
        bak.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(dst, bak) if dst.is_file() else shutil.copytree(dst, bak, dirs_exist_ok=True)
    dst.parent.mkdir(parents=True, exist_ok=True)
    if Path(src).is_dir():
        shutil.copytree(src, dst, dirs_exist_ok=True)
    else:
        shutil.copy2(src, dst)

# ─── 格式检测 ───
def detect_format(filename):
    fn = filename.lower()
    if fn.endswith('.deb'): return 'deb'
    if fn.endswith('.rpm'): return 'rpm'
    if fn.endswith('.pacman'): return 'pacman'
    if '.pkg.tar' in fn: return 'pacman'
    if fn.endswith('.kurali'): return 'kurali'
    if fn.endswith('.appimage'): return 'appimage'
    if any(fn.endswith(e) for e in ['.tar.gz','.tar.xz','.tar.bz2','.tar.zst','.tgz','.txz']): return 'tar'
    if fn.endswith('.apk'): return 'apk'     # Alpine Linux 包格式（⚠ 非安卓 APK）
    if fn.endswith('.zip'): return 'zip'
    return 'unknown'

# ─── 发行版检测 ───
def detect_distro():
    os_release = Path("/etc/os-release")
    if os_release.exists():
        for line in os_release.read_text().splitlines():
            if line.startswith("ID="):
                did = line.split("=",1)[1].strip().strip('"').lower()
                if did in DISTRO_DB:
                    return did, DISTRO_DB[did]
    return None, None

# ─── 提取包 ───
def extract_package(filepath, fmt, dest):
    dest = Path(dest); dest.mkdir(parents=True, exist_ok=True)
    info(f"解压: {Path(filepath).name} [{fmt}]")
    try:
        if fmt == 'deb':
            if has_cmd('dpkg-deb'):
                run_cmd(['dpkg-deb', '-x', str(filepath), str(dest)])
            elif has_cmd('ar'):
                tmp = tempfile.mkdtemp()
                run_cmd(['ar', 'x', filepath], cwd=tmp)
                for ext in ['data.tar.xz','data.tar.zst','data.tar.gz','data.tar.bz2']:
                    dt = Path(tmp)/ext
                    if dt.exists():
                        with tarfile.open(dt) as tf: tf.extractall(dest)
                        break
                shutil.rmtree(tmp)
        elif fmt == 'rpm':
            if has_cmd('rpm2cpio'):
                subprocess.run(f"rpm2cpio '{filepath}' | cpio -idm --quiet",
                    shell=True, cwd=str(dest), capture_output=True)
            elif has_cmd('bsdtar'):
                run_cmd(['bsdtar','xf',str(filepath),'-C',str(dest)])
            else:
                return False
        elif fmt == 'pacman':
            if has_cmd('bsdtar'):
                run_cmd(['bsdtar','xf',str(filepath),'-C',str(dest)])
            else:
                with tarfile.open(filepath) as tf: tf.extractall(dest)
            for f in ['.PKGINFO','.MTREE','.INSTALL','.BUILDINFO']:
                (dest/f).unlink(missing_ok=True)
        elif fmt == 'appimage':
            shutil.copy2(filepath, dest)
            st = os.stat(dest/Path(filepath).name)
            os.chmod(dest/Path(filepath).name, st.st_mode | stat.S_IEXEC)
        elif fmt == 'tar':
            with tarfile.open(filepath) as tf: tf.extractall(dest)
        elif fmt == 'zip':
            with zipfile.ZipFile(filepath) as zf: zf.extractall(dest)
        elif fmt == 'apk':
            # Alpine Linux 包格式（⚠ 不是安卓 APK！）
            # 内部是 tar.gz，含 .PKGINFO 元数据 + .SIGN.* 签名 + 实际文件
            with tarfile.open(filepath, 'r:gz') as tf: tf.extractall(dest)
            for meta in ['.PKGINFO','.SIGN.*','.MTREE','.INSTALL','.BUILDINFO']:
                import glob as _glob
                for f in _glob.glob(str(dest / meta)):
                    Path(f).unlink(missing_ok=True)
        elif fmt == 'kurali':
            with tarfile.open(filepath) as tf: tf.extractall(dest)
            # 把 rootfs/ 内容提升到 dest
            rootfs = dest / "rootfs"
            if rootfs.exists():
                for item in rootfs.iterdir():
                    shutil.move(str(item), str(dest / item.name))
                shutil.rmtree(rootfs)
        else:
            return False
        return True
    except Exception as e:
        err(f"解压失败: {e}")
        return False

# ─── 扁平化（递归处理多层嵌套）───
def flatten(dest):
    dest = Path(dest)
    changed = True
    while changed:
        changed = False
        dirs = [d for d in dest.iterdir() if d.is_dir()]
        if len(dirs) == 1:
            top = dirs[0]
            if any((top/d).exists() for d in ['usr','bin']) or (top/'.AppRun').exists():
                tmp = dest.parent / (dest.name + '.__f__')
                shutil.move(str(top), str(tmp))
                shutil.rmtree(dest)
                shutil.move(str(tmp), str(dest))
                changed = True

# ─── RAM 运行模式 ───
def cmd_run(filepath):
    """在内存中临时运行程序，不安装"""
    filepath = Path(filepath).resolve()
    if not filepath.exists():
        die(f"文件不存在: {filepath}")

    # 选择 tmpfs 目录
    ram_base = None
    for candidate in ['/dev/shm', os.environ.get('XDG_RUNTIME_DIR', ''), f'/run/user/{os.getuid()}']:
        if candidate and Path(candidate).is_dir() and os.access(candidate, os.W_OK):
            ram_base = Path(candidate)
            break
    if not ram_base:
        ram_base = Path(tempfile.gettempdir())
        warn("/tmp 非 tmpfs, 安全性稍低")

    ram_dir = ram_base / f"kurali-py-{os.getpid()}-{int(time.time())}"
    ram_dir.mkdir(parents=True)
    pkg_dir = ram_dir / "pkg"
    pkg_dir.mkdir()

    try:
        fmt = detect_format(filepath.name)
        if fmt == 'appimage':
            shutil.copy2(filepath, ram_dir)
            target = ram_dir / filepath.name
            os.chmod(target, target.stat().st_mode | stat.S_IEXEC)
            info(f"RAM 运行: {filepath.name}")
            subprocess.run([str(target)])
            return

        if not extract_package(filepath, fmt, pkg_dir):
            die("解压失败")

        # 设置环境
        env = os.environ.copy()
        ld_paths = [str(pkg_dir / "usr" / "lib"), str(pkg_dir / "usr" / "lib64"),
                    str(pkg_dir / "lib"), str(pkg_dir / "lib64")]
        env["LD_LIBRARY_PATH"] = ":".join(ld_paths) + ":" + env.get("LD_LIBRARY_PATH", "")
        env["PATH"] = ":".join([str(pkg_dir / "usr" / "bin"), str(pkg_dir / "bin"),
                    str(pkg_dir / "usr" / "local" / "bin"), str(pkg_dir)]) + ":" + env["PATH"]

        # 查找可执行文件
        exes = []
        for d in ['usr/bin', 'bin', 'usr/local/bin', 'usr/sbin', 'sbin']:
            dpath = pkg_dir / d
            if dpath.exists():
                for f in dpath.iterdir():
                    if f.is_file() and os.access(f, os.X_OK) and f not in exes:
                        exes.append(f)
        # 限制前20个
        exes = exes[:20]

        if not exes:
            warn("未找到可执行文件")
            info("进入 RAM shell, Ctrl+D 退出清理")
            subprocess.run(["bash", "--norc"], cwd=str(ram_dir), env=env)
            return

        print(f"\n{C.BOLD}可用程序:{C.RESET}")
        for i, ex in enumerate(exes, 1):
            print(f"  {C.CY}{i}{C.RESET} {ex.name}")

        try:
            ch = input(f"{C.Y}[?]{C.RESET} 编号运行 / 'shell' 进交互 [编号/shell]: ")
        except (EOFError, KeyboardInterrupt):
            return

        if ch.strip().lower() == 'shell':
            info("RAM shell, Ctrl+D 退出清理")
            subprocess.run(["bash", "--norc"], cwd=str(ram_dir), env=env)
        elif ch.strip().isdigit() and 1 <= int(ch) <= len(exes):
            info(f"运行: {exes[int(ch)-1].name}")
            subprocess.run([str(exes[int(ch)-1])], env=env)
        else:
            err("无效选择")
    finally:
        shutil.rmtree(ram_dir, ignore_errors=True)
        debug_cleanup = True

# ─── 安装 ───
def cmd_install(filepath, pkg_name=None, system_mode=False):
    filepath = Path(filepath).resolve()
    if not filepath.exists():
        die(f"文件不存在: {filepath}")

    fmt = detect_format(filepath.name)
    if fmt == 'unknown':
        die(f"不支持的格式: {filepath.name}")

    if pkg_name is None:
        if fmt == 'apk':
            # Alpine .apk：从 .PKGINFO 读取 origin（源包名）
            try:
                tmp_a = tempfile.mkdtemp()
                with tarfile.open(filepath, 'r:gz') as tf:
                    try: tf.extract('.PKGINFO', tmp_a)
                    except KeyError: pass
                pkginfo = Path(tmp_a) / '.PKGINFO'
                if pkginfo.exists():
                    for line in pkginfo.read_text().splitlines():
                        if re.match(r'^origin\s*=', line):
                            pkg_name = line.split('=',1)[1].strip()
                            break
                    if not pkg_name:
                        for line in pkginfo.read_text().splitlines():
                            if re.match(r'^pkgname\s*=', line):
                                pkg_name = line.split('=',1)[1].strip()
                                break
                shutil.rmtree(tmp_a, ignore_errors=True)
            except Exception:
                pass
            if not pkg_name:
                pkg_name = filepath.stem.split('-')[0].lower()
        elif fmt == 'deb':
            # deb：优先用 dpkg-deb 提取 Package 字段
            r = run_cmd(['dpkg-deb', '-f', str(filepath), 'Package'])
            pkg_name = r.stdout.strip() if r and r.stdout.strip() else filepath.stem.split('-')[0].lower()
        elif fmt == 'rpm':
            # rpm：优先用 rpm 查询 NAME
            r = run_cmd(['rpm', '-qp', '--qf', '%{NAME}', str(filepath)])
            pkg_name = r.stdout.strip() if r and r.stdout.strip() else filepath.stem.split('-')[0].lower()
        elif fmt == 'pacman':
            r = run_cmd(['bsdtar', 'xf', str(filepath), '-O', '.PKGINFO'])
            if r:
                for line in r.stdout.splitlines():
                    if re.match(r'^pkgname\s*=', line):
                        pkg_name = line.split('=',1)[1].strip()
                        break
            if not pkg_name:
                pkg_name = re.sub(r'\.pkg\.tar.*', '', filepath.name).lower()
        else:
            pkg_name = filepath.stem.split('.')[0].lower()

    pkg_dir = PKG_DIR / pkg_name
    extract_dir = pkg_dir / "rootfs"
    pkg_dir.mkdir(parents=True, exist_ok=True)

    if system_mode:
        ensure_root()
        info("⚠ 直接系统安装模式")

    if not extract_package(filepath, fmt, extract_dir):
        shutil.rmtree(pkg_dir, ignore_errors=True)
        die(f"解压失败: {filepath}")

    flatten(extract_dir)

    # 符号链接
    if not system_mode:
        link_dir = Path("/usr/local/bin")
        if not os.access(link_dir, os.W_OK):
            link_dir = Path.home() / ".local/bin"
            link_dir.mkdir(parents=True, exist_ok=True)

        linked = 0
        for d in ['usr/bin','bin','usr/local/bin','usr/sbin','sbin']:
            dpath = extract_dir / d
            if dpath.exists():
                for f in dpath.iterdir():
                    if f.is_file() and os.access(f, os.X_OK):
                        lnk = link_dir / f.name
                        if not lnk.exists():
                            lnk.symlink_to(f)
                            linked += 1
        if linked:
            info(f"已链接 {linked} 个命令到 {link_dir}")
    else:
        # 系统模式：复制到系统路径
        info("复制文件到系统...")
        count = 0
        for d in ['usr','bin','sbin','lib','lib64','etc','var','opt']:
            src = extract_dir / d
            if src.exists():
                for f in src.rglob('*'):
                    if f.is_file():
                        dst = Path('/') / d / f.relative_to(src)
                        safe_copy(f, dst)
                        count += 1
        info(f"已复制 {count} 个文件")

    # 保存元数据
    pkg_version = "unknown"
    if fmt == 'apk':
        # 从 .PKGINFO 提取版本
        try:
            tmp_a = tempfile.mkdtemp()
            with tarfile.open(filepath, 'r:gz') as tf:
                try: tf.extract('.PKGINFO', tmp_a)
                except KeyError: pass
            pkginfo = Path(tmp_a) / '.PKGINFO'
            if pkginfo.exists():
                for line in pkginfo.read_text().splitlines():
                    if re.match(r'^pkgver\s*=', line):
                        pkg_version = line.split('=',1)[1].strip()
                        break
            shutil.rmtree(tmp_a, ignore_errors=True)
        except Exception:
            pass
    elif fmt == 'deb':
        try:
            r = run_cmd(['dpkg-deb', '-f', str(filepath), 'Version'])
            if r.returncode == 0 and r.stdout.strip():
                pkg_version = r.stdout.strip()
        except Exception:
            pass
    meta = {
        "name": pkg_name, "version": pkg_version, "format": fmt,
        "source": filepath.name, "installed": datetime.now().isoformat(),
        "mode": "system" if system_mode else "sandbox",
        "path": str(extract_dir), "kuraliAll": VERSION
    }
    (pkg_dir / f"{pkg_name}.info").write_text(
        "\n".join(f"{k}={v}" for k,v in meta.items())
    )
    files_list = [str(f.relative_to(extract_dir)) for f in extract_dir.rglob('*') if f.is_file()]
    (pkg_dir / f"{pkg_name}.files").write_text("\n".join(files_list))

    ok(f"安装完成: {pkg_name}")

# ─── 卸载 ───
def cmd_remove(name):
    pkg_dir = PKG_DIR / name
    if not pkg_dir.exists():
        die(f"包不存在: {name}")
    if not confirm(f"卸载 {name}?"):
        return
    # 移除符号链接
    files_file = pkg_dir / f"{name}.files"
    if files_file.exists():
        for line in files_file.read_text().splitlines():
            bn = Path(line).name
            for d in [Path("/usr/local/bin"), Path.home()/"local/bin"]:
                lnk = d / bn
                if lnk.is_symlink() and str(pkg_dir) in str(lnk.resolve()):
                    lnk.unlink()
    # 移除桌面条目
    df = Path.home() / f".local/share/applications/kurali-{name}.desktop"
    df.unlink(missing_ok=True)
    shutil.rmtree(pkg_dir)
    ok(f"已卸载: {name}")

# ─── 列表 ───
def cmd_list():
    entries = []
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
                    entries.append(meta)
                else:
                    entries.append({"name": d.name})
    if not entries:
        info("没有已安装的包")
        return
    print(f"\n{C.BOLD}已安装的包:{C.RESET}\n")
    print(f"  {C.CY}{'包名':<20} {'格式':<10} {'版本':<10} {'模式':<10} {'日期'}{C.RESET}")
    for e in entries:
        name = e.get('name','?')
        fmt = e.get('format','?')
        ver = e.get('version','?')
        mode = e.get('mode','sandbox')
        installed = e.get('installed','?')[:10]
        print(f"  {name:<20} {fmt:<10} {ver:<10} {mode:<10} {installed}")
    print()

# ─── 搜索（修复版）───
def cmd_search(keyword):
    """按关键词搜索已安装的包"""
    if not keyword:
        die("用法: kurali-py s <关键词>")
    keyword_lower = keyword.lower()
    results = []
    if PKG_DIR.exists():
        for d in sorted(PKG_DIR.iterdir()):
            if d.is_dir() and keyword_lower in d.name.lower():
                info_file = d / f"{d.name}.info"
                ver = "?"
                if info_file.exists():
                    for line in info_file.read_text().splitlines():
                        if line.startswith("version="):
                            ver = line.split("=",1)[1]
                results.append((d.name, ver))
    if results:
        print(f"\n{C.BOLD}搜索结果: '{keyword}'{C.RESET}")
        for name, ver in results:
            print(f"  {C.G}{name}{C.RESET} ({ver})")
        print()
    else:
        info(f"未找到匹配 '{keyword}' 的包")

# ─── 详情 ───
def cmd_info(name):
    info_file = PKG_DIR / name / f"{name}.info"
    if not info_file.exists():
        die(f"包不存在: {name}")
    print(f"\n{C.BOLD}包详情: {name}{C.RESET}\n")
    for line in info_file.read_text().splitlines():
        if '=' in line:
            k,v = line.split('=',1)
            print(f"  {C.CY}{k:<12}{C.RESET} {v}")
    files_file = PKG_DIR / name / f"{name}.files"
    if files_file.exists():
        print(f"  {C.CY}{'files':<12}{C.RESET} {len(files_file.read_text().splitlines())} 个文件")
    print()

# ─── 依赖检查 ───
def cmd_deps(target=None):
    if target is None:
        info("系统依赖检查")
        r = run_cmd(['ldd','--version'])
        if r:
            print(f"  glibc: {r.stdout.split(chr(10))[0]}")
        for lib in ['libc.so','libm.so','libdl.so','libpthread.so','libz.so','libssl.so']:
            # 方法1: ldconfig
            r = run_cmd(['ldconfig','-p'])
            found = r and lib.replace('.so','') in r.stdout
            # 方法2: 常见库路径回退
            if not found:
                import os as _os
                for d in ['/lib','/lib64','/usr/lib','/usr/lib64',
                          '/usr/lib/x86_64-linux-gnu','/lib/x86_64-linux-gnu']:
                    if Path(d).is_dir():
                        try:
                            for f in _os.listdir(d):
                                if lib in f:
                                    found = True
                                    break
                        except PermissionError:
                            pass
                    if found:
                        break
            mark = f"{C.G}✓{C.RESET}" if found else f"{C.Y}?{C.RESET}"
            print(f"  {mark} {lib}")
    elif Path(target).exists():
        info(f"依赖检查: {Path(target).name}")
        r = run_cmd(['ldd', target])
        if r:
            for line in r.stdout.splitlines():
                if 'not found' in line:
                    print(f"  {C.R}✗{C.RESET} {line.strip()}")
                elif '=>' in line:
                    lib = line.split()[0]
                    print(f"  {C.G}✓{C.RESET} {lib}")
    else:
        die(f"文件不存在: {target}")

# ─── 打包 .kurali ───
def cmd_pack(filepath, output=None):
    """将任意支持的格式打包为 .kurali 格式"""
    filepath = Path(filepath).resolve()
    if not filepath.exists():
        die(f"文件不存在: {filepath}")

    fmt = detect_format(filepath.name)
    if fmt == 'unknown':
        die(f"不支持的格式: {filepath.name}")
    if fmt == 'kurali':
        die("文件已经是 .kurali 格式")

    # 从实际格式提取包名（而非仅用文件名）
    if fmt == 'deb':
        r = run_cmd(['dpkg-deb', '-f', str(filepath), 'Package'])
        pkg_name = r.stdout.strip().lower() if r and r.stdout.strip() else filepath.stem.split('-')[0].lower()
    elif fmt == 'rpm':
        r = run_cmd(['rpm', '-qp', '--qf', '%{NAME}', str(filepath)])
        pkg_name = r.stdout.strip().lower() if r and r.stdout.strip() else filepath.stem.split('-')[0].lower()
    else:
        pkg_name = filepath.stem.split('.')[0].lower()
    pkg_version = "unknown"
    if output is None:
        output = f"{pkg_name}-{pkg_version}.kurali"

    info(f"打包: {filepath.name} → {output}")

    tmp = Path(tempfile.mkdtemp())
    try:
        rootfs = tmp / "rootfs"
        meta = tmp / ".kurali"
        scripts = tmp / "scripts"
        rootfs.mkdir()
        meta.mkdir()
        scripts.mkdir()

        # 解压源包
        if not extract_package(filepath, fmt, rootfs):
            die("解压失败")
        flatten(rootfs)

        # manifest.json
        import platform
        manifest = {
            "name": pkg_name,
            "version": pkg_version,
            "source_format": fmt,
            "source_file": filepath.name,
            "kurali_version": VERSION,
            "created": datetime.now().isoformat(),
            "arch": platform.machine(),
        }
        (meta / "manifest.json").write_text(
            "{\n" + ",\n".join(f'  "{k}": "{v}"' for k,v in manifest.items()) + "\n}\n"
        )

        # 文件清单
        files_list = sorted(str(f.relative_to(rootfs)) for f in rootfs.rglob('*') if f.is_file())
        (meta / "files.txt").write_text("\n".join(files_list))

        # 提取维护脚本
        deb_dir = rootfs / "DEBIAN"
        for s in ['preinst','postinst','prerm','postrm']:
            if (deb_dir / s).exists():
                shutil.copy2(deb_dir / s, scripts / s)

        # 打包
        with tarfile.open(output, "w:gz") as tar:
            tar.add(str(meta), arcname=".kurali")
            tar.add(str(rootfs), arcname="rootfs")
            if any(scripts.iterdir()):
                tar.add(str(scripts), arcname="scripts")

        file_count = len(files_list)
        ok(f"打包完成: {output} ({file_count} 个文件)")
        info(f"来源: {filepath.name} [{fmt}] → .kurali")
        print(f"  {C.CY}安装:{C.RESET} kurali i {output}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

# ─── 帮助 ───
HELP = """KuraliAll v2.1 — Python 版全能包管理器

用法:  kurali-py <命令> [参数]

命令:
  i  <文件>        安装软件包
  r  <包名>        卸载
  l                 列表
  f  <包名>        详情
  s  <关键词>       搜索已安装的包
  run <文件>        内存模式运行（不安装）
  pack <文件> [输出] 把任意格式打包成 .kurali 格式
  deps [文件]       依赖检查
  help              帮助

选项: --system  --yes/-y  -v

支持: .deb  .rpm  .pkg.tar.*  .apk  AppImage  .tar.*  .zip
"""

# ─── 主入口 ───
def main():
    for d in [DB_DIR, LOG_DIR, PKG_DIR, BACKUP_DIR, CACHE_DIR]:
        d.mkdir(parents=True, exist_ok=True)

    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    flags = set(a for a in sys.argv[1:] if a.startswith('-'))

    if not args:
        print(HELP); return

    cmd = args[0]
    rest = args[1:]

    try:
        if cmd in ('i','install','add'):
            if not rest: die("用法: kurali-py i <文件>")
            system_mode = '--system' in flags
            cmd_install(rest[0], rest[1] if len(rest)>1 else None, system_mode)
        elif cmd in ('r','remove','rm'):
            if not rest: die("用法: kurali-py r <包名>")
            cmd_remove(rest[0])
        elif cmd in ('l','list','ls'):
            cmd_list()
        elif cmd in ('f','info','show'):
            if not rest: die("用法: kurali-py f <包名>")
            cmd_info(rest[0])
        elif cmd in ('s','search','find'):
            if not rest: die("用法: kurali-py s <关键词>")
            cmd_search(rest[0])
        elif cmd in ('run','exec'):
            if not rest: die("用法: kurali-py run <文件>")
            cmd_run(rest[0])
        elif cmd in ('pack',):
            if not rest: die("用法: kurali-py pack <文件> [输出名.kurali]")
            cmd_pack(rest[0], rest[1] if len(rest) > 1 else None)
        elif cmd in ('deps','dep'):
            cmd_deps(rest[0] if rest else None)
        elif cmd in ('help','-h','--help'):
            print(HELP)
        elif cmd in ('version','ver'):
            print(f"KuraliAll v{VERSION} (Python)")
        else:
            die(f"未知命令: {cmd}")
    except KeyboardInterrupt:
        print("\n中断")
    except PermissionError:
        die("权限不足，请使用 sudo")

if __name__ == '__main__':
    main()
