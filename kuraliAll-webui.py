#!/usr/bin/env python3
"""
KuraliAll WebUI v2.2.0 — 全能 Linux 包管理器 Web 界面
纯 Python 标准库实现，零外部依赖 | 单文件 | 离线可用
"""

import http.server
import json
import os
import subprocess
import sys
import threading
import time
import io
import shutil
import tarfile
import zipfile
import tempfile
import stat
import re
import signal
from pathlib import Path
from datetime import datetime
from urllib.parse import urlparse, parse_qs, unquote

# ═══════════════════════════════════════════════════════
#  配置
# ═══════════════════════════════════════════════════════

VERSION = "2.2.0"
WEBUI_PORT = int(os.environ.get("KURALI_WEBUI_PORT", "8080"))
KURALI_HOME = Path(os.environ.get("KURALI_HOME", "/var/lib/kuraliAll"))
PKG_DIR = KURALI_HOME / "pkg"
LOG_DIR = KURALI_HOME / "logs"
BACKUP_DIR = KURALI_HOME / "backup"
CACHE_DIR = KURALI_HOME / "cache"
DB_DIR = KURALI_HOME / "db"

_SCRIPT_DIR = Path(__file__).resolve().parent
KURALI_SH = _SCRIPT_DIR / "kuraliAll.sh"
if not KURALI_SH.exists():
    KURALI_SH = KURALI_HOME / "kuraliAll.sh"

tasks = []
task_lock = threading.Lock()
task_counter = 0

op_logs = []
op_logs_lock = threading.Lock()
MAX_LOGS = 500


# ═══════════════════════════════════════════════════════
#  工具函数
# ═══════════════════════════════════════════════════════

def add_log(level, msg):
    ts = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    entry = {"time": ts, "level": level, "message": msg}
    with op_logs_lock:
        op_logs.append(entry)
        if len(op_logs) > MAX_LOGS:
            del op_logs[:len(op_logs) - MAX_LOGS]
    try:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        with open(LOG_DIR / "kuraliAll.log", "a") as f:
            f.write(f"[{ts}] [{level}] {msg}\n")
    except:
        pass


def run_cmd(cmd, timeout=60):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except:
        return None


def has_cmd(c):
    return shutil.which(c) is not None


def detect_format(filename):
    fn = filename.lower()
    if fn.endswith('.deb'): return 'deb'
    if fn.endswith('.rpm'): return 'rpm'
    if fn.endswith('.pacman'): return 'pacman'
    if '.pkg.tar' in fn: return 'pacman'
    if fn.endswith('.kurali'): return 'kurali'
    if fn.endswith('.appimage'): return 'appimage'
    if any(fn.endswith(e) for e in ['.tar.gz','.tar.xz','.tar.bz2','.tar.zst','.tgz','.txz']): return 'tar'
    if fn.endswith('.apk'): return 'apk'
    if fn.endswith('.zip'): return 'zip'
    return 'unknown'


def _parse_multipart(body_bytes, content_type):
    """手动解析 multipart/form-data（零外部依赖）"""
    m = re.search(r'boundary=(.+)', content_type)
    if not m:
        raise ValueError("No boundary in Content-Type")
    boundary = m.group(1).strip().strip('"')
    delimiter = ('--' + boundary).encode()
    parts = body_bytes.split(delimiter)
    fields = {}
    for part in parts:
        part = part.strip(b'\r\n')
        if not part or part == b'--':
            continue
        sep = b'\r\n\r\n'
        idx = part.find(sep)
        if idx < 0:
            continue
        header_section = part[:idx].decode('utf-8', errors='replace')
        body = part[idx + 4:]
        if body.endswith(b'\r\n'):
            body = body[:-2]
        fname_m = re.search(r'filename="([^"]*)"', header_section)
        name_m = re.search(r'name="([^"]*)"', header_section)
        if not name_m:
            continue
        name = name_m.group(1)
        if fname_m:
            fields[name] = {'filename': fname_m.group(1), 'data': body, 'is_file': True}
        else:
            fields[name] = body.decode('utf-8', errors='replace')
    return fields


# ═══════════════════════════════════════════════════════
#  包管理核心
# ═══════════════════════════════════════════════════════

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
                            k, v = line.split('=', 1)
                            meta[k] = v
                    try:
                        size = sum(f.stat().st_size for f in d.rglob('*') if f.is_file())
                        if size > 1073741824: meta['size'] = f"{size/1073741824:.1f} GB"
                        elif size > 1048576: meta['size'] = f"{size/1048576:.1f} MB"
                        elif size > 1024: meta['size'] = f"{size/1024:.1f} KB"
                        else: meta['size'] = f"{size} B"
                    except: meta['size'] = '?'
                    try:
                        fl = d / f"{d.name}.files"
                        meta['file_count'] = str(len(fl.read_text().splitlines())) if fl.exists() else '?'
                    except: meta['file_count'] = '?'
                    packages.append(meta)
                else:
                    packages.append({"name": d.name, "format": "?", "version": "?", "mode": "?"})
    return packages


def extract_package(filepath, fmt, dest):
    dest = Path(dest); dest.mkdir(parents=True, exist_ok=True)
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
                subprocess.run(f"rpm2cpio '{filepath}' | cpio -idm --quiet", shell=True, cwd=str(dest), capture_output=True)
            elif has_cmd('bsdtar'):
                run_cmd(['bsdtar', 'xf', str(filepath), '-C', str(dest)])
            else: return False
        elif fmt == 'pacman':
            if has_cmd('bsdtar'):
                run_cmd(['bsdtar', 'xf', str(filepath), '-C', str(dest)])
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
            with tarfile.open(filepath, 'r:gz') as tf: tf.extractall(dest)
            for meta in ['.PKGINFO','.MTREE','.INSTALL','.BUILDINFO']:
                for f in dest.glob(meta): f.unlink(missing_ok=True)
            for f in dest.glob('.SIGN.*'): f.unlink(missing_ok=True)
        elif fmt == 'kurali':
            with tarfile.open(filepath) as tf: tf.extractall(dest)
            rootfs = dest/"rootfs"
            if rootfs.exists():
                for item in rootfs.iterdir(): shutil.move(str(item), str(dest/item.name))
                shutil.rmtree(rootfs)
        else: return False
        return True
    except Exception as e:
        add_log("ERROR", f"解压失败: {e}")
        return False


def flatten(dest):
    dest = Path(dest)
    changed = True
    while changed:
        changed = False
        dirs = [d for d in dest.iterdir() if d.is_dir()]
        if len(dirs) == 1:
            top = dirs[0]
            if any((top/d).exists() for d in ['usr','bin']) or (top/'.AppRun').exists():
                tmp = dest.parent/(dest.name+'.__f__')
                shutil.move(str(top), str(tmp)); shutil.rmtree(dest); shutil.move(str(tmp), str(dest))
                changed = True


def get_pkg_name_from_file(filepath, fmt):
    filepath = Path(filepath)
    if fmt == 'deb':
        r = run_cmd(['dpkg-deb', '-f', str(filepath), 'Package'])
        if r and r.stdout.strip(): return r.stdout.strip().lower()
    elif fmt == 'rpm':
        r = run_cmd(['rpm', '-qp', '--qf', '%{NAME}', str(filepath)])
        if r and r.stdout.strip(): return r.stdout.strip().lower()
    elif fmt == 'apk':
        try:
            tmp_a = tempfile.mkdtemp()
            with tarfile.open(filepath, 'r:gz') as tf:
                try: tf.extract('.PKGINFO', tmp_a)
                except KeyError: pass
            pi = Path(tmp_a)/'.PKGINFO'
            if pi.exists():
                for line in pi.read_text().splitlines():
                    if re.match(r'^origin\s*=', line):
                        v = line.split('=',1)[1].strip(); shutil.rmtree(tmp_a,ignore_errors=True); return v
                    if re.match(r'^pkgname\s*=', line):
                        v = line.split('=',1)[1].strip(); shutil.rmtree(tmp_a,ignore_errors=True); return v
            shutil.rmtree(tmp_a, ignore_errors=True)
        except: pass
    elif fmt == 'pacman':
        if has_cmd('bsdtar'):
            r = run_cmd(['bsdtar','xf',str(filepath),'-O','.PKGINFO'])
            if r:
                for line in r.stdout.splitlines():
                    if re.match(r'^pkgname\s*=', line): return line.split('=',1)[1].strip()
    return filepath.stem.split('.')[0].lower()


def get_pkg_version_from_file(filepath, fmt):
    filepath = Path(filepath)
    if fmt == 'deb':
        r = run_cmd(['dpkg-deb', '-f', str(filepath), 'Version'])
        if r and r.stdout.strip(): return r.stdout.strip()
    elif fmt == 'rpm':
        r = run_cmd(['rpm', '-qp', '--qf', '%{VERSION}', str(filepath)])
        if r and r.stdout.strip(): return r.stdout.strip()
    return "unknown"


def do_install(filepath, mode="sandbox"):
    filepath = Path(filepath).resolve()
    if not filepath.exists(): return False, f"文件不存在: {filepath}"
    fmt = detect_format(filepath.name)
    if fmt == 'unknown': return False, f"不支持的格式: {filepath.name}"

    pkg_name = get_pkg_name_from_file(filepath, fmt)
    if not pkg_name or pkg_name == 'unknown':
        pkg_name = filepath.stem.split('.')[0].lower()

    pkg_dir = PKG_DIR/pkg_name
    extract_dir = pkg_dir/"rootfs"
    pkg_dir.mkdir(parents=True, exist_ok=True)

    add_log("INFO", f"开始安装: {pkg_name} [{fmt}] 模式={mode}")

    if mode == "system" and os.geteuid() != 0:
        return False, "系统安装模式需要 root 权限"

    if not extract_package(filepath, fmt, extract_dir):
        shutil.rmtree(pkg_dir, ignore_errors=True)
        return False, f"解压失败: {filepath.name}"

    flatten(extract_dir)

    if mode == "system":
        add_log("INFO", "复制文件到系统路径...")
        count = 0
        for d in ['usr','bin','sbin','lib','lib32','lib64','libx32','etc','var','opt']:
            src = extract_dir/d
            if src.exists():
                for f in src.rglob('*'):
                    if f.is_file():
                        dst = Path('/')/d/f.relative_to(src)
                        try:
                            dst.parent.mkdir(parents=True, exist_ok=True)
                            if dst.exists():
                                bak = BACKUP_DIR/f"{dst}.{int(time.time())}.bak"
                                bak.parent.mkdir(parents=True, exist_ok=True)
                                shutil.copy2(dst, bak)
                            shutil.copy2(f, dst); count += 1
                        except Exception as e:
                            add_log("WARN", f"复制失败: {e}")
        add_log("INFO", f"已复制 {count} 个文件到系统")
    elif mode == "ram":
        add_log("INFO", f"RAM 模式: {pkg_name} 已就绪")
    else:
        link_dir = Path("/usr/local/bin")
        if not os.access(link_dir, os.W_OK):
            link_dir = Path.home()/".local/bin"; link_dir.mkdir(parents=True, exist_ok=True)
        linked = 0
        for d in ['usr/bin','bin','usr/local/bin','usr/sbin','sbin']:
            dpath = extract_dir/d
            if dpath.exists():
                for f in dpath.iterdir():
                    if f.is_file() and os.access(f, os.X_OK):
                        lnk = link_dir/f.name
                        if not lnk.exists():
                            try: lnk.symlink_to(f); linked += 1
                            except: pass
        if linked: add_log("INFO", f"已链接 {linked} 个命令到 {link_dir}")

    pkg_version = get_pkg_version_from_file(filepath, fmt)
    meta = {"name":pkg_name,"version":pkg_version,"format":fmt,"source":filepath.name,
            "installed":datetime.now().isoformat(),"mode":mode,"path":str(extract_dir),"kuraliAll":VERSION}
    (pkg_dir/f"{pkg_name}.info").write_text("\n".join(f"{k}={v}" for k,v in meta.items()))
    files_list = [str(f.relative_to(extract_dir)) for f in extract_dir.rglob('*') if f.is_file()]
    (pkg_dir/f"{pkg_name}.files").write_text("\n".join(files_list))

    add_log("OK", f"安装完成: {pkg_name} ({pkg_version})")
    return True, f"安装完成: {pkg_name} ({pkg_version})"


def do_remove(name):
    pkg_dir = PKG_DIR/name
    if not pkg_dir.exists(): return False, f"包不存在: {name}"

    files_file = pkg_dir/f"{name}.files"
    if files_file.exists():
        for line in files_file.read_text().splitlines():
            bn = Path(line).name
            for d in [Path("/usr/local/bin"), Path.home()/".local/bin"]:
                lnk = d/bn
                try:
                    if lnk.is_symlink() and str(pkg_dir) in str(lnk.resolve()): lnk.unlink()
                except: pass

    df = Path.home()/f".local/share/applications/kurali-{name}.desktop"
    df.unlink(missing_ok=True)
    shutil.rmtree(pkg_dir)
    add_log("OK", f"已卸载: {name}")
    return True, f"已卸载: {name}"


def do_deps_check(target=None):
    results = []
    if target is None:
        r = run_cmd(['ldd', '--version'])
        glibc = r.stdout.split('\n')[0] if r else "unknown"
        results.append({"type":"info","text":f"glibc: {glibc}"})
        for lib in ['libc.so','libm.so','libdl.so','libpthread.so','libz.so','libssl.so']:
            found = False
            if has_cmd('ldconfig'):
                r2 = run_cmd(['ldconfig','-p'])
                if r2 and lib.replace('.so','') in r2.stdout: found = True
            if not found:
                for d in ['/lib','/lib64','/usr/lib','/usr/lib64','/usr/lib/x86_64-linux-gnu','/lib/x86_64-linux-gnu']:
                    if Path(d).is_dir():
                        try:
                            for f in os.listdir(d):
                                if lib in f: found = True; break
                        except: pass
                    if found: break
            results.append({"type":"ok" if found else "warn","text":f"{'✓' if found else '?'} {lib}"})
    else:
        if not Path(target).exists(): return False, "文件不存在", results
        r = run_cmd(['ldd', target])
        if r:
            for line in r.stdout.splitlines():
                if 'not found' in line: results.append({"type":"error","text":line.strip()})
                elif '=>' in line: results.append({"type":"ok","text":f"✓ {line.split()[0]}"})
    return True, "依赖检查完成", results


def get_system_info():
    info = {}
    if Path("/etc/os-release").exists():
        for line in Path("/etc/os-release").read_text().splitlines():
            if line.startswith("PRETTY_NAME="):
                info['distro'] = line.split('=',1)[1].strip().strip('"'); break
    r = run_cmd(['uname','-r']); info['kernel'] = r.stdout.strip() if r else '?'
    r = run_cmd(['uname','-m']); info['arch'] = r.stdout.strip() if r else '?'
    r = run_cmd(['df','-h',str(KURALI_HOME)])
    if r:
        lines = r.stdout.strip().split('\n')
        if len(lines) >= 2:
            parts = lines[1].split()
            if len(parts) >= 5:
                info['disk_total']=parts[1]; info['disk_used']=parts[2]; info['disk_avail']=parts[3]; info['disk_pct']=parts[4]
    info['pkg_count'] = len(get_packages())
    svf = KURALI_HOME/"version"
    info['sys_version'] = svf.read_text().strip() if svf.exists() else "未安装"
    info['webui_version'] = VERSION
    return info


def get_backups():
    backups = []
    if BACKUP_DIR.exists():
        for f in sorted(BACKUP_DIR.rglob('*'), key=lambda x: x.stat().st_mtime, reverse=True):
            if f.is_file():
                try:
                    st = f.stat()
                    sz = st.st_size
                    sz_str = f"{sz/1024:.1f} KB" if sz < 1048576 else f"{sz/1048576:.1f} MB"
                    backups.append({"path":str(f.relative_to(BACKUP_DIR)),"size":sz_str,
                                    "modified":datetime.fromtimestamp(st.st_mtime).isoformat()})
                except: pass
    return backups


# ═══════════════════════════════════════════════════════
#  任务队列
# ═══════════════════════════════════════════════════════

def add_task(task_type, filepath=None, pkg_name=None, mode="sandbox"):
    global task_counter
    with task_lock:
        task_counter += 1
        task = {"id":task_counter,"type":task_type,"filepath":filepath,"pkg_name":pkg_name,
                "mode":mode,"status":"pending","progress":0,"message":"等待中...","created":datetime.now().isoformat()}
        tasks.append(task)
    threading.Thread(target=execute_task, args=(task["id"],), daemon=True).start()
    return task["id"]


def execute_task(task_id):
    with task_lock:
        task = next((t for t in tasks if t["id"]==task_id), None)
        if not task: return
        task["status"]="running"; task["progress"]=10; task["message"]="执行中..."
    try:
        if task["type"]=="install":
            with task_lock: task["progress"]=30
            success, msg = do_install(task["filepath"], task["mode"])
            with task_lock:
                task["status"]="success" if success else "error"
                task["progress"]=100 if success else 0; task["message"]=msg
        elif task["type"]=="remove":
            with task_lock: task["progress"]=50
            success, msg = do_remove(task["pkg_name"])
            with task_lock:
                task["status"]="success" if success else "error"
                task["progress"]=100 if success else 0; task["message"]=msg
    except Exception as e:
        with task_lock: task["status"]="error"; task["message"]=str(e)


# ═══════════════════════════════════════════════════════
#  HTTP 服务器
# ═══════════════════════════════════════════════════════

class KuraliWebHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args): pass

    def _send_json(self, data, code=200):
        body = json.dumps(data, ensure_ascii=False).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Content-Length',str(len(body)))
        self.send_header('Access-Control-Allow-Origin','*')
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, html, code=200):
        body = html.encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type','text/html; charset=utf-8')
        self.send_header('Content-Length',str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self):
        length = int(self.headers.get('Content-Length',0))
        return self.rfile.read(length) if length > 0 else b''

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        params = parse_qs(parsed.query)

        if path in ('/','/index.html'):
            self._send_html(INDEX_HTML)
        elif path=='/api/version':
            self._send_json({"version":VERSION,"kuraliAll":"2.2.0"})
        elif path=='/api/info':
            self._send_json(get_system_info())
        elif path=='/api/packages':
            self._send_json({"packages":get_packages()})
        elif path=='/api/tasks':
            with task_lock: self._send_json({"tasks":list(tasks[-50:])})
        elif path=='/api/logs':
            with op_logs_lock: self._send_json({"logs":list(op_logs[-200:])})
        elif path=='/api/backups':
            self._send_json({"backups":get_backups()})
        elif path=='/api/deps':
            target = params.get('target',[None])[0]
            s, m, r = do_deps_check(target)
            self._send_json({"success":s,"message":m,"results":r})
        elif path=='/api/package/info':
            name = params.get('name',[''])[0]
            if not name: self._send_json({"error":"缺少包名"},400); return
            info_file = PKG_DIR/name/f"{name}.info"
            if not info_file.exists(): self._send_json({"error":f"包不存在: {name}"},404); return
            meta = {}
            for line in info_file.read_text().splitlines():
                if '=' in line: k,v = line.split('=',1); meta[k]=v
            ff = PKG_DIR/name/f"{name}.files"
            if ff.exists(): meta['file_count']=str(len(ff.read_text().splitlines()))
            try:
                sz = sum(f.stat().st_size for f in (PKG_DIR/name).rglob('*') if f.is_file())
                meta['total_size'] = f"{sz/1048576:.1f} MB" if sz>1048576 else f"{sz/1024:.1f} KB"
            except: meta['total_size']='?'
            self._send_json(meta)
        elif path=='/api/package/files':
            name = params.get('name',[''])[0]
            if not name: self._send_json({"error":"缺少包名"},400); return
            ff = PKG_DIR/name/f"{name}.files"
            if not ff.exists(): self._send_json({"files":[]}); return
            all_files = ff.read_text().splitlines()
            self._send_json({"files":all_files[:200],"total":len(all_files)})
        elif path.startswith('/api/task/'):
            tid = path.split('/')[-1]
            with task_lock: t = next((t for t in tasks if t["id"]==int(tid)),None)
            self._send_json(t if t else {"error":"任务不存在"}, 200 if t else 404)
        else:
            self._send_json({"error":"Not found"},404)

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path=='/api/install':
            ct = self.headers.get('Content-Type','')
            if 'multipart/form-data' in ct:
                try:
                    body = self._read_body()
                    fields = _parse_multipart(body, ct)
                    mode = fields.get('mode','sandbox')
                    file_info = fields.get('file')
                    if not file_info or not isinstance(file_info, dict) or not file_info.get('filename'):
                        self._send_json({"error":"未选择文件"},400); return
                    upload_dir = CACHE_DIR/"uploads"
                    upload_dir.mkdir(parents=True, exist_ok=True)
                    filepath = upload_dir/Path(file_info['filename']).name
                    with open(filepath,'wb') as f: f.write(file_info['data'])
                    tid = add_task("install", filepath=str(filepath), mode=mode)
                    self._send_json({"success":True,"task_id":tid,"message":f"已提交安装: {file_info['filename']}"})
                except Exception as e:
                    self._send_json({"error":f"上传失败: {e}"},500)
            else:
                try:
                    body = json.loads(self._read_body())
                    filepath = body.get('filepath','')
                    mode = body.get('mode','sandbox')
                    if not filepath: self._send_json({"error":"未指定文件路径"},400); return
                    if not Path(filepath).exists(): self._send_json({"error":f"文件不存在: {filepath}"},400); return
                    tid = add_task("install", filepath=filepath, mode=mode)
                    self._send_json({"success":True,"task_id":tid})
                except Exception as e:
                    self._send_json({"error":str(e)},500)

        elif path=='/api/remove':
            try:
                body = json.loads(self._read_body())
                name = body.get('name','')
                if not name: self._send_json({"error":"未指定包名"},400); return
                tid = add_task("remove", pkg_name=name)
                self._send_json({"success":True,"task_id":tid})
            except Exception as e: self._send_json({"error":str(e)},500)

        elif path=='/api/pack':
            try:
                body = json.loads(self._read_body())
                filepath = body.get('filepath','')
                output = body.get('output','')
                if not filepath or not Path(filepath).exists(): self._send_json({"error":"文件不存在"},400); return
                cmd = [str(KURALI_SH),'pack',filepath]
                if output: cmd.append(output)
                r = subprocess.run(cmd, capture_output=True, text=True, timeout=120,
                                    env={**os.environ,'KURALI_HOME':str(KURALI_HOME)})
                if r.returncode==0:
                    add_log("OK",f"打包完成: {filepath}")
                    self._send_json({"success":True,"output":r.stdout+r.stderr})
                else: self._send_json({"error":r.stderr or "打包失败"},500)
            except Exception as e: self._send_json({"error":str(e)},500)

        elif path=='/api/native-install':
            try:
                body = json.loads(self._read_body())
                pkg = body.get('package','')
                if not pkg: self._send_json({"error":"未指定包名"},400); return
                r = subprocess.run([str(KURALI_SH),'native',pkg], capture_output=True, text=True, timeout=120,
                                    env={**os.environ,'KURALI_HOME':str(KURALI_HOME)})
                add_log("INFO",f"原生安装: {pkg}")
                self._send_json({"success":r.returncode==0,"output":r.stdout+r.stderr})
            except Exception as e: self._send_json({"error":str(e)},500)

        elif path=='/api/backup/clean':
            try:
                if BACKUP_DIR.exists(): shutil.rmtree(BACKUP_DIR); BACKUP_DIR.mkdir(parents=True,exist_ok=True)
                add_log("OK","备份已清理")
                self._send_json({"success":True,"message":"备份已清理"})
            except Exception as e: self._send_json({"error":str(e)},500)

        else:
            self._send_json({"error":"Not found"},404)

    def do_DELETE(self):
        parsed = urlparse(self.path)
        path = parsed.path
        if path.startswith('/api/backup/'):
            rel = unquote(path[len('/api/backup/'):])
            bf = BACKUP_DIR/rel
            if bf.exists() and bf.is_file():
                bf.unlink(); add_log("INFO",f"删除备份: {rel}"); self._send_json({"success":True})
            else: self._send_json({"error":"文件不存在"},404)
        else: self._send_json({"error":"Not found"},404)


# ═══════════════════════════════════════════════════════
#  HTML 前端（单文件嵌入）
# ═══════════════════════════════════════════════════════

INDEX_HTML = r'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>KuraliAll WebUI v''' + VERSION + r'''</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
:root{--bg:#0d1117;--bg2:#161b22;--bg3:#21262d;--border:#30363d;--text:#e6edf3;--text2:#8b949e;--text3:#6e7681;--blue:#58a6ff;--green:#3fb950;--yellow:#d29922;--red:#f85149;--orange:#f78166;--purple:#bc8cff;--green-bg:rgba(63,185,80,.15);--blue-bg:rgba(88,166,255,.15);--red-bg:rgba(248,81,73,.15);--yellow-bg:rgba(210,153,34,.15)}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;background:var(--bg);color:var(--text);overflow:hidden;height:100vh}
a{color:var(--blue);text-decoration:none}
.app{display:grid;grid-template-columns:240px 1fr;grid-template-rows:48px 1fr;height:100vh;gap:1px;background:var(--border)}
.topbar{grid-column:1/-1;background:var(--bg2);display:flex;align-items:center;padding:0 16px;gap:12px;z-index:10}
.sidebar{background:var(--bg);display:flex;flex-direction:column;overflow-y:auto}
.main{background:var(--bg);display:flex;flex-direction:column;overflow:hidden}
.logo{display:flex;align-items:center;gap:8px}
.logo-icon{width:28px;height:28px;background:linear-gradient(135deg,#2ea043,#238636);border-radius:6px;display:flex;align-items:center;justify-content:center;font-size:14px;font-weight:700;color:#fff}
.logo-text{font-weight:600;font-size:15px}
.logo-ver{font-size:11px;padding:2px 6px;border-radius:10px;background:var(--green-bg);color:var(--green);border:1px solid rgba(63,185,80,.3)}
.topbar-right{margin-left:auto;display:flex;align-items:center;gap:10px}
.sys-badge{display:flex;align-items:center;gap:6px;padding:4px 10px;border-radius:6px;background:var(--bg3);border:1px solid var(--border);font-size:12px;color:var(--text2)}
.sys-dot{width:7px;height:7px;border-radius:50%;background:var(--green);animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
.sb-section{padding:12px 16px 4px;font-size:11px;font-weight:600;color:var(--text3);text-transform:uppercase;letter-spacing:.5px}
.sb-item{display:flex;align-items:center;gap:10px;padding:8px 16px;cursor:pointer;transition:all .15s;font-size:13px;color:var(--text2);border-left:3px solid transparent}
.sb-item:hover{background:var(--bg3);color:var(--text)}
.sb-item.active{background:var(--blue-bg);color:var(--blue);border-left-color:var(--blue)}
.sb-item .icon{width:18px;text-align:center;font-size:14px}
.sb-item .badge{margin-left:auto;font-size:11px;padding:1px 6px;border-radius:8px;background:var(--bg3);color:var(--text2)}
.sb-bottom{margin-top:auto;padding:12px 16px;border-top:1px solid var(--border)}
.sb-bottom .storage-label{font-size:11px;color:var(--text3);margin-bottom:6px}
.sb-bottom .storage-bar{height:5px;background:var(--bg3);border-radius:3px;overflow:hidden}
.sb-bottom .storage-fill{height:100%;background:var(--blue);border-radius:3px;transition:width .3s}
.sb-bottom .storage-text{display:flex;justify-content:space-between;font-size:11px;color:var(--text3);margin-top:4px}
.view{display:none;flex:1;overflow-y:auto;padding:20px}
.view.active{display:block}
.card{background:var(--bg2);border:1px solid var(--border);border-radius:8px;padding:16px;margin-bottom:16px}
.card-title{font-size:14px;font-weight:600;margin-bottom:12px;display:flex;align-items:center;gap:8px}
.card-title .icon{font-size:16px}
.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:16px}
.stat{background:var(--bg2);border:1px solid var(--border);border-radius:8px;padding:14px;text-align:center}
.stat-val{font-size:22px;font-weight:700}
.stat-label{font-size:11px;color:var(--text2);margin-top:2px}
.stat.green .stat-val{color:var(--green)}.stat.blue .stat-val{color:var(--blue)}.stat.yellow .stat-val{color:var(--yellow)}.stat.red .stat-val{color:var(--red)}
.btn{display:inline-flex;align-items:center;gap:6px;padding:7px 14px;border-radius:6px;font-size:13px;font-weight:500;cursor:pointer;transition:all .15s;border:1px solid transparent;font-family:inherit}
.btn-primary{background:#238636;color:#fff;border-color:rgba(46,160,67,.4)}.btn-primary:hover{background:#2ea043}
.btn-secondary{background:var(--bg3);color:var(--text);border-color:var(--border)}.btn-secondary:hover{background:#30363d;border-color:var(--text2)}
.btn-danger{background:#da3633;color:#fff;border-color:rgba(248,81,73,.4)}.btn-danger:hover{background:#f85149}
.btn-sm{padding:4px 10px;font-size:12px}
.btn:disabled{opacity:.5;cursor:not-allowed}
input[type="text"]{background:var(--bg);border:1px solid var(--border);border-radius:6px;padding:8px 12px;color:var(--text);font-size:13px;outline:none;width:100%;font-family:inherit}
input:focus{border-color:var(--blue);box-shadow:0 0 0 3px rgba(88,166,255,.1)}
.row{display:flex;gap:12px;flex-wrap:wrap}.col{flex:1;min-width:280px}
.modes{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-bottom:16px}
.mode-card{padding:14px;border:1px solid var(--border);border-radius:8px;cursor:pointer;transition:all .15s;background:var(--bg2);text-align:center}
.mode-card:hover{border-color:var(--text2)}
.mode-card.selected{border-color:var(--blue);background:var(--blue-bg)}
.mode-card.danger.selected{border-color:var(--red);background:var(--red-bg)}
.mode-card .mode-icon{font-size:20px;margin-bottom:6px}
.mode-card .mode-name{font-size:13px;font-weight:600}
.mode-card .mode-desc{font-size:11px;color:var(--text2);margin-top:2px}
.drop-zone{border:2px dashed var(--border);border-radius:10px;padding:36px;text-align:center;transition:all .2s;cursor:pointer;margin-bottom:16px;background:var(--bg2)}
.drop-zone:hover,.drop-zone.drag-over{border-color:var(--blue);background:var(--blue-bg)}
.drop-zone .dz-icon{font-size:32px;margin-bottom:8px}
.drop-zone .dz-text{font-size:14px;color:var(--text2)}
.drop-zone .dz-hint{font-size:12px;color:var(--text3);margin-top:4px}
.table-wrap{overflow-x:auto}
table{width:100%;border-collapse:collapse;font-size:13px}
th{text-align:left;padding:10px 12px;border-bottom:2px solid var(--border);color:var(--text2);font-weight:600;font-size:12px;text-transform:uppercase;letter-spacing:.3px}
td{padding:8px 12px;border-bottom:1px solid var(--border)}
tr:hover{background:var(--bg3)}
.tag{display:inline-block;padding:2px 8px;border-radius:10px;font-size:11px;font-weight:500}
.tag-green{background:var(--green-bg);color:var(--green)}.tag-blue{background:var(--blue-bg);color:var(--blue)}.tag-yellow{background:var(--yellow-bg);color:var(--yellow)}.tag-red{background:var(--red-bg);color:var(--red)}.tag-purple{background:rgba(188,140,255,.15);color:var(--purple)}
.terminal{background:var(--bg);border:1px solid var(--border);border-radius:8px;padding:12px;font-family:'JetBrains Mono','Fira Code',monospace;font-size:12px;line-height:1.6;overflow-y:auto;max-height:500px;min-height:200px}
.terminal .line{white-space:pre-wrap;word-break:break-all}
.terminal .ts{color:var(--text3)}.terminal .level-INFO{color:var(--blue)}.terminal .level-OK{color:var(--green)}.terminal .level-WARN{color:var(--yellow)}.terminal .level-ERROR{color:var(--red)}
.task-item{display:flex;align-items:center;gap:10px;padding:10px 12px;border-bottom:1px solid var(--border);background:var(--bg)}
.task-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0}
.task-dot.pending{background:var(--text3);animation:pulse 2s infinite}.task-dot.running{background:var(--blue);animation:pulse 1s infinite}.task-dot.success{background:var(--green)}.task-dot.error{background:var(--red)}
.task-info{flex:1;min-width:0}
.task-name{font-size:12px;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.task-msg{font-size:11px;color:var(--text2);margin-top:1px}
.task-bar{height:3px;background:var(--bg3);border-radius:2px;margin-top:4px;overflow:hidden}
.task-bar-fill{height:100%;background:var(--blue);transition:width .3s;border-radius:2px}
.modal-overlay{display:none;position:fixed;inset:0;background:rgba(0,0,0,.6);z-index:100;align-items:center;justify-content:center}
.modal-overlay.show{display:flex}
.modal{background:var(--bg2);border:1px solid var(--border);border-radius:12px;padding:24px;max-width:600px;width:90%;max-height:80vh;overflow-y:auto}
.modal-title{font-size:16px;font-weight:600;margin-bottom:16px;display:flex;align-items:center;gap:8px}
.modal-close{margin-left:auto;cursor:pointer;font-size:18px;color:var(--text2);background:none;border:none}
.modal-close:hover{color:var(--text)}
.dep-ok{color:var(--green)}.dep-err{color:var(--red)}.dep-warn{color:var(--yellow)}
::-webkit-scrollbar{width:8px;height:8px}::-webkit-scrollbar-track{background:var(--bg)}::-webkit-scrollbar-thumb{background:var(--bg3);border-radius:4px}::-webkit-scrollbar-thumb:hover{background:#484f58}
@media(max-width:768px){.app{grid-template-columns:1fr}.sidebar{display:none}.stats{grid-template-columns:repeat(2,1fr)}.modes{grid-template-columns:1fr}}
@keyframes fadeIn{from{opacity:0;transform:translateY(-8px)}to{opacity:1;transform:translateY(0)}}
.fade-in{animation:fadeIn .25s ease}
</style>
</head>
<body>
<div class="app">
<div class="topbar">
  <div class="logo"><div class="logo-icon">K</div><span class="logo-text">KuraliAll</span><span class="logo-ver">v''' + VERSION + r'''</span></div>
  <div class="topbar-right">
    <div class="sys-badge"><div class="sys-dot"></div><span id="sysStatus">系统正常</span></div>
    <button class="btn btn-secondary btn-sm" onclick="refreshAll()" title="刷新">⟳</button>
  </div>
</div>
<div class="sidebar">
  <div class="sb-section">导航</div>
  <div class="sb-item active" data-view="install" onclick="switchView('install')"><span class="icon">📦</span><span>安装管理</span></div>
  <div class="sb-item" data-view="packages" onclick="switchView('packages')"><span class="icon">📋</span><span>已安装软件</span><span class="badge" id="pkgBadge">0</span></div>
  <div class="sb-item" data-view="terminal" onclick="switchView('terminal')"><span class="icon">🖥️</span><span>终端输出</span></div>
  <div class="sb-section">系统</div>
  <div class="sb-item" data-view="deps" onclick="switchView('deps')"><span class="icon">🔍</span><span>依赖检查</span></div>
  <div class="sb-item" data-view="backup" onclick="switchView('backup')"><span class="icon">💾</span><span>备份管理</span></div>
  <div class="sb-item" data-view="logs" onclick="switchView('logs')"><span class="icon">📝</span><span>系统日志</span></div>
  <div class="sb-item" data-view="about" onclick="switchView('about')"><span class="icon">ℹ️</span><span>关于</span></div>
  <div class="sb-bottom" id="storageInfo">
    <div class="storage-label">存储使用</div>
    <div class="storage-bar"><div class="storage-fill" id="storageFill" style="width:0%"></div></div>
    <div class="storage-text"><span id="storageUsed">-</span><span id="storageTotal">-</span></div>
  </div>
</div>
<div class="main">

<!-- View: Install -->
<div class="view active" id="view-install">
  <div class="stats">
    <div class="stat green"><div class="stat-val" id="statOk">0</div><div class="stat-label">已安装</div></div>
    <div class="stat blue"><div class="stat-val" id="statRunning">0</div><div class="stat-label">执行中</div></div>
    <div class="stat yellow"><div class="stat-val" id="statPending">0</div><div class="stat-label">等待中</div></div>
    <div class="stat red"><div class="stat-val" id="statError">0</div><div class="stat-label">失败</div></div>
  </div>
  <div class="card" id="taskCard" style="display:none"><div class="card-title"><span class="icon">⚡</span>任务队列</div><div id="taskList"></div></div>
  <div class="drop-zone" id="dropZone">
    <div class="dz-icon">📂</div>
    <div class="dz-text">点击或拖拽软件包文件至此</div>
    <div class="dz-hint">支持 .deb, .rpm, .pkg.tar.*, .apk, AppImage, .tar.*, .zip, .kurali</div>
    <input type="file" id="fileInput" style="display:none" accept=".deb,.rpm,.pacman,.pkg.tar.*,.apk,.appimage,.tar.gz,.tar.xz,.tar.bz2,.tgz,.txz,.zip,.kurali">
  </div>
  <div class="card">
    <div class="card-title"><span class="icon">🔗</span>快速安装</div>
    <div class="row" style="margin-bottom:12px">
      <div class="col"><input type="text" id="pathInput" placeholder="输入本地文件路径..." onkeypress="if(event.key==='Enter')installFromPath()"></div>
    </div>
    <div style="margin-bottom:16px">
      <div style="font-size:11px;color:var(--text3);margin-bottom:8px;text-transform:uppercase;letter-spacing:.5px">安装模式</div>
      <div class="modes">
        <div class="mode-card selected" data-mode="sandbox" onclick="selectMode(this)"><div class="mode-icon">🛡️</div><div class="mode-name">安全模式</div><div class="mode-desc">沙箱隔离，不修改系统</div></div>
        <div class="mode-card danger" data-mode="system" onclick="selectMode(this)"><div class="mode-icon">⚠️</div><div class="mode-name">系统安装</div><div class="mode-desc">修改系统文件（高风险）</div></div>
        <div class="mode-card" data-mode="ram" onclick="selectMode(this)"><div class="mode-icon">💨</div><div class="mode-name">RAM 模式</div><div class="mode-desc">内存运行，退出即清理</div></div>
      </div>
    </div>
    <div class="row">
      <button class="btn btn-primary" onclick="installFromPath()"><span>⚡</span>安装</button>
      <button class="btn btn-secondary" onclick="showNativeInstall()"><span>📦</span>原生安装</button>
      <button class="btn btn-secondary" onclick="showPackDialog()"><span>📦</span>打包 .kurali</button>
    </div>
  </div>
</div>

<!-- View: Packages -->
<div class="view" id="view-packages">
  <div class="card">
    <div class="card-title" style="justify-content:space-between">
      <span><span class="icon">📋</span>已安装软件</span>
      <div style="display:flex;gap:8px">
        <input type="text" id="searchPkg" placeholder="搜索..." style="width:200px" oninput="filterPackages()">
        <button class="btn btn-secondary btn-sm" onclick="loadPackages()">⟳ 刷新</button>
      </div>
    </div>
    <div class="table-wrap">
      <table><thead><tr><th>包名</th><th>格式</th><th>版本</th><th>模式</th><th>大小</th><th>安装日期</th><th>操作</th></tr></thead>
      <tbody id="pkgTable"></tbody></table>
    </div>
    <div id="pkgEmpty" style="text-align:center;padding:30px;color:var(--text2);display:none">暂无已安装的软件包</div>
  </div>
</div>

<!-- View: Terminal -->
<div class="view" id="view-terminal">
  <div class="card">
    <div class="card-title" style="justify-content:space-between"><span><span class="icon">🖥️</span>操作日志</span><button class="btn btn-secondary btn-sm" onclick="clearTerminalLogs()">清空</button></div>
    <div class="terminal" id="terminalOutput"></div>
  </div>
</div>

<!-- View: Deps -->
<div class="view" id="view-deps">
  <div class="card">
    <div class="card-title"><span class="icon">🔍</span>依赖检查</div>
    <div class="row" style="margin-bottom:16px">
      <div class="col"><input type="text" id="depsTarget" placeholder="输入程序路径检查依赖（留空=系统检查）..." onkeypress="if(event.key==='Enter')checkDeps()"></div>
      <button class="btn btn-primary" onclick="checkDeps()">检查</button>
    </div>
    <div class="terminal" id="depsResult" style="min-height:150px"><div class="line" style="color:var(--text2)">点击"检查"开始依赖分析</div></div>
  </div>
</div>

<!-- View: Backup -->
<div class="view" id="view-backup">
  <div class="card">
    <div class="card-title" style="justify-content:space-between"><span><span class="icon">💾</span>备份管理</span><button class="btn btn-danger btn-sm" onclick="cleanBackups()">清空所有备份</button></div>
    <div class="table-wrap"><table><thead><tr><th>文件路径</th><th>大小</th><th>备份时间</th><th>操作</th></tr></thead><tbody id="backupTable"></tbody></table></div>
    <div id="backupEmpty" style="text-align:center;padding:30px;color:var(--text2);display:none">暂无备份文件</div>
  </div>
</div>

<!-- View: Logs -->
<div class="view" id="view-logs">
  <div class="card">
    <div class="card-title" style="justify-content:space-between"><span><span class="icon">📝</span>系统日志</span><button class="btn btn-secondary btn-sm" onclick="loadLogs()">⟳ 刷新</button></div>
    <div class="terminal" id="logOutput"></div>
  </div>
</div>

<!-- View: About -->
<div class="view" id="view-about">
  <div class="card">
    <div class="card-title"><span class="icon">ℹ️</span>关于 KuraliAll WebUI</div>
    <div style="line-height:2">
      <div><strong>KuraliAll WebUI</strong> — 全能 Linux 包管理器 Web 界面</div>
      <div>WebUI 版本：<span class="tag tag-green">v''' + VERSION + r'''</span></div>
      <div>KuraliAll 版本：<span class="tag tag-blue" id="aboutKuraliVer">v2.1.2</span></div>
      <div style="margin-top:12px">在任意 Linux 发行版上，安装任意 Linux 发行版的离线软件包。</div>
      <div>100% 离线工作，纯 Python 标准库实现，零外部依赖。</div>
      <div style="margin-top:12px;color:var(--text2)">支持格式：.deb · .rpm · .pkg.tar.* · .pacman · .apk · AppImage · .tar.* · .zip · .kurali</div>
    </div>
  </div>
  <div class="card">
    <div class="card-title"><span class="icon">🖥️</span>系统信息</div>
    <div id="sysInfo" style="line-height:2">加载中...</div>
  </div>
</div>

</div></div>

<!-- Modals -->
<div class="modal-overlay" id="modalPkgDetail">
  <div class="modal">
    <div class="modal-title"><span>📦</span><span id="modalPkgName">包详情</span><button class="modal-close" onclick="closeModal('modalPkgDetail')">✕</button></div>
    <div id="modalPkgContent"></div>
  </div>
</div>
<div class="modal-overlay" id="modalNative">
  <div class="modal">
    <div class="modal-title"><span>📦</span><span>原生包管理器安装</span><button class="modal-close" onclick="closeModal('modalNative')">✕</button></div>
    <p style="font-size:13px;color:var(--text2);margin-bottom:12px">使用系统原生包管理器（apt/yum/dnf/pacman 等）安装软件</p>
    <input type="text" id="nativePkgName" placeholder="输入包名，如 htop、vim..." onkeypress="if(event.key==='Enter')doNativeInstall()">
    <div style="margin-top:12px"><button class="btn btn-primary" onclick="doNativeInstall()">安装</button></div>
    <div id="nativeResult" style="margin-top:12px"></div>
  </div>
</div>
<div class="modal-overlay" id="modalPack">
  <div class="modal">
    <div class="modal-title"><span>📦</span><span>打包为 .kurali 格式</span><button class="modal-close" onclick="closeModal('modalPack')">✕</button></div>
    <p style="font-size:13px;color:var(--text2);margin-bottom:12px">将任意支持的格式统一转换为 .kurali 归档</p>
    <input type="text" id="packSrcPath" placeholder="源文件路径..." style="margin-bottom:8px">
    <input type="text" id="packOutput" placeholder="输出文件名（可选）">
    <div style="margin-top:12px"><button class="btn btn-primary" onclick="doPack()">打包</button></div>
    <div id="packResult" style="margin-top:12px"></div>
  </div>
</div>

<script>
let currentMode='sandbox',allPackages=[],refreshTimer=null;
async function api(path,opts={}){try{const r=await fetch(path,{headers:opts.json?{'Content-Type':'application/json'}:{},...opts,body:opts.json?JSON.stringify(opts.body):opts.body});return await r.json()}catch(e){return{error:e.message}}}
function switchView(n){document.querySelectorAll('.view').forEach(v=>v.classList.remove('active'));document.querySelectorAll('.sb-item').forEach(i=>i.classList.remove('active'));const v=document.getElementById('view-'+n);if(v)v.classList.add('active');const it=document.querySelector('.sb-item[data-view="'+n+'"]');if(it)it.classList.add('active');if(n==='packages')loadPackages();if(n==='logs')loadLogs();if(n==='backup')loadBackups();if(n==='about')loadSysInfo()}
function selectMode(el){document.querySelectorAll('.mode-card').forEach(c=>c.classList.remove('selected'));el.classList.add('selected');currentMode=el.dataset.mode}
const dropZone=document.getElementById('dropZone'),fileInput=document.getElementById('fileInput');
dropZone.addEventListener('click',()=>fileInput.click());
dropZone.addEventListener('dragover',e=>{e.preventDefault();dropZone.classList.add('drag-over')});
dropZone.addEventListener('dragleave',()=>dropZone.classList.remove('drag-over'));
dropZone.addEventListener('drop',e=>{e.preventDefault();dropZone.classList.remove('drag-over');if(e.dataTransfer.files.length>0)uploadFile(e.dataTransfer.files[0])});
fileInput.addEventListener('change',()=>{if(fileInput.files.length>0)uploadFile(fileInput.files[0])});
async function uploadFile(file){const fd=new FormData();fd.append('file',file);fd.append('mode',currentMode);const r=await fetch('/api/install',{method:'POST',body:fd});const d=await r.json();if(d.success){showNotif('success','已提交安装: '+file.name);refreshTasks()}else{showNotif('error',d.error||'安装失败')}fileInput.value=''}
async function installFromPath(){const p=document.getElementById('pathInput').value.trim();if(!p){showNotif('error','请输入文件路径');return}const r=await api('/api/install',{method:'POST',json:true,body:{filepath:p,mode:currentMode}});if(r.success){showNotif('success','已提交安装任务');document.getElementById('pathInput').value='';refreshTasks()}else{showNotif('error',r.error||'安装失败')}}
async function loadPackages(){const r=await api('/api/packages');allPackages=r.packages||[];renderPackages(allPackages);document.getElementById('pkgBadge').textContent=allPackages.length}
function renderPackages(pkgs){const tb=document.getElementById('pkgTable'),em=document.getElementById('pkgEmpty');if(!pkgs.length){tb.innerHTML='';em.style.display='block';return}em.style.display='none';tb.innerHTML=pkgs.map(p=>{const mc=p.mode==='system'?'tag-red':p.mode==='ram'?'tag-purple':'tag-green';const mt=p.mode==='system'?'系统':p.mode==='ram'?'RAM':'沙箱';const fc=p.format==='deb'?'tag-blue':p.format==='rpm'?'tag-yellow':'tag-green';return'<tr><td><strong style="cursor:pointer" onclick="showPkgDetail(\''+p.name+'\')">'+p.name+'</strong></td><td><span class="tag '+fc+'">'+(p.format||'?')+'</span></td><td>'+(p.version||'?')+'</td><td><span class="tag '+mc+'">'+mt+'</span></td><td>'+(p.size||'?')+'</td><td>'+(p.installed||'?').substring(0,10)+'</td><td><button class="btn btn-danger btn-sm" onclick="removePkg(\''+p.name+'\')">卸载</button></td></tr>'}).join('')}
function filterPackages(){const kw=document.getElementById('searchPkg').value.toLowerCase();if(!kw){renderPackages(allPackages);return}renderPackages(allPackages.filter(p=>p.name.toLowerCase().includes(kw)))}
async function showPkgDetail(name){const info=await api('/api/package/info?name='+encodeURIComponent(name));if(info.error){showNotif('error',info.error);return}document.getElementById('modalPkgName').textContent=name;let h='<div style="line-height:2">';for(const[k,v]of Object.entries(info))h+='<div><span style="color:var(--text2);display:inline-block;width:80px">'+k+':</span> '+v+'</div>';h+='</div>';document.getElementById('modalPkgContent').innerHTML=h;document.getElementById('modalPkgDetail').classList.add('show')}
async function removePkg(name){if(!confirm('确定卸载 '+name+'？'))return;const r=await api('/api/remove',{method:'POST',json:true,body:{name}});if(r.success){showNotif('success','已提交卸载: '+name);refreshTasks();setTimeout(loadPackages,2000)}else{showNotif('error',r.error||'卸载失败')}}
async function refreshTasks(){const r=await api('/api/tasks');const ts=r.tasks||[];const card=document.getElementById('taskCard'),list=document.getElementById('taskList');if(!ts.length){card.style.display='none'}else{card.style.display='block';list.innerHTML=ts.slice(-10).reverse().map(t=>{const ic=t.type==='install'?'📥':'🗑️';const lb=t.type==='install'?'安装 '+(t.filepath?t.filepath.split('/').pop():'?')+' ('+t.mode+')':'卸载 '+(t.pkg_name||'?');return'<div class="task-item"><div class="task-dot '+t.status+'"></div><div class="task-info"><div class="task-name">'+ic+' '+lb+'</div><div class="task-msg">'+t.message+'</div>'+(t.status==='running'?'<div class="task-bar"><div class="task-bar-fill" style="width:'+t.progress+'%"></div></div>':'')+'</div></div>'}).join('')}const pkgs=(await api('/api/packages')).packages||[];document.getElementById('statOk').textContent=pkgs.length;document.getElementById('statRunning').textContent=ts.filter(t=>t.status==='running').length;document.getElementById('statPending').textContent=ts.filter(t=>t.status==='pending').length;document.getElementById('statError').textContent=ts.filter(t=>t.status==='error').length;document.getElementById('pkgBadge').textContent=pkgs.length}
async function checkDeps(){const t=document.getElementById('depsTarget').value.trim();const r=await api('/api/deps'+(t?'?target='+encodeURIComponent(t):''));const el=document.getElementById('depsResult');if(!r.success&&(!r.results||!r.results.length)){el.innerHTML='<div class="line dep-err">'+(r.message||'检查失败')+'</div>';return}el.innerHTML=(r.results||[]).map(i=>{const c=i.type==='ok'?'dep-ok':i.type==='error'?'dep-err':i.type==='warn'?'dep-warn':'';return'<div class="line '+c+'">'+i.text+'</div>'}).join('')}
async function loadBackups(){const r=await api('/api/backups');const b=r.backups||[];const tb=document.getElementById('backupTable'),em=document.getElementById('backupEmpty');if(!b.length){tb.innerHTML='';em.style.display='block';return}em.style.display='none';tb.innerHTML=b.map(x=>'<tr><td style="font-family:monospace;font-size:12px">'+x.path+'</td><td>'+x.size+'</td><td>'+x.modified.substring(0,19).replace('T',' ')+'</td><td><button class="btn btn-danger btn-sm" onclick="deleteBackup(\''+encodeURIComponent(x.path)+'\')">删除</button></td></tr>').join('')}
async function deleteBackup(p){if(!confirm('确定删除此备份？'))return;await fetch('/api/backup/'+p,{method:'DELETE'});loadBackups()}
async function cleanBackups(){if(!confirm('确定清空所有备份？'))return;const r=await api('/api/backup/clean',{method:'POST'});if(r.success){showNotif('success','备份已清空');loadBackups()}}
async function loadLogs(){const r=await api('/api/logs');const logs=r.logs||[];document.getElementById('logOutput').innerHTML=logs.map(l=>'<div class="line"><span class="ts">['+l.time+']</span> <span class="level-'+l.level+'">['+l.level+']</span> '+l.message+'</div>').join('')}
function clearTerminalLogs(){document.getElementById('terminalOutput').innerHTML='<div class="line" style="color:var(--text2)">日志已清空</div>'}
let lastLogCount=0;async function refreshTerminal(){const r=await api('/api/logs');const logs=r.logs||[];if(logs.length===lastLogCount)return;lastLogCount=logs.length;const el=document.getElementById('terminalOutput');el.innerHTML=logs.map(l=>'<div class="line"><span class="ts">['+l.time+']</span> <span class="level-'+l.level+'">['+l.level+']</span> '+l.message+'</div>').join('');el.scrollTop=el.scrollHeight}
function showNativeInstall(){document.getElementById('modalNative').classList.add('show');document.getElementById('nativePkgName').focus()}
function showPackDialog(){document.getElementById('modalPack').classList.add('show');document.getElementById('packSrcPath').focus()}
async function doNativeInstall(){const pkg=document.getElementById('nativePkgName').value.trim();if(!pkg)return;const r=await api('/api/native-install',{method:'POST',json:true,body:{package:pkg}});document.getElementById('nativeResult').innerHTML=r.success?'<div style="color:var(--green)">'+(r.output||'安装成功')+'</div>':'<div style="color:var(--red)">'+(r.error||r.output||'安装失败')+'</div>'}
async function doPack(){const fp=document.getElementById('packSrcPath').value.trim();const out=document.getElementById('packOutput').value.trim();if(!fp)return;const r=await api('/api/pack',{method:'POST',json:true,body:{filepath:fp,output:out}});document.getElementById('packResult').innerHTML=r.success?'<div style="color:var(--green)">'+(r.output||'打包成功')+'</div>':'<div style="color:var(--red)">'+(r.error||'打包失败')+'</div>'}
async function loadSysInfo(){const r=await api('/api/info');document.getElementById('sysInfo').innerHTML='<div><span style="color:var(--text2);display:inline-block;width:120px">发行版：</span>'+(r.distro||'?')+'</div><div><span style="color:var(--text2);display:inline-block;width:120px">内核：</span>'+(r.kernel||'?')+'</div><div><span style="color:var(--text2);display:inline-block;width:120px">架构：</span>'+(r.arch||'?')+'</div><div><span style="color:var(--text2);display:inline-block;width:120px">磁盘：</span>'+(r.disk_used||'?')+' / '+(r.disk_total||'?')+' ('+(r.disk_pct||'?')+')</div><div><span style="color:var(--text2);display:inline-block;width:120px">已安装包数：</span>'+(r.pkg_count||0)+'</div><div><span style="color:var(--text2);display:inline-block;width:120px">KuraliAll：</span>'+(r.sys_version||'?')+'</div><div><span style="color:var(--text2);display:inline-block;width:120px">WebUI：</span>v'+(r.webui_version||'?')+'</div>';document.getElementById('aboutKuraliVer').textContent='v'+(r.sys_version||'?');if(r.disk_pct){const p=parseInt(r.disk_pct)||0;document.getElementById('storageFill').style.width=p+'%';document.getElementById('storageUsed').textContent=r.disk_used||'-';document.getElementById('storageTotal').textContent=r.disk_total||'-'}}
function showNotif(type,msg){const colors={success:'var(--green)',error:'var(--red)',info:'var(--blue)',warn:'var(--yellow)'};const el=document.createElement('div');el.style.cssText='position:fixed;top:60px;right:20px;padding:10px 16px;border-radius:8px;background:var(--bg2);border:1px solid '+(colors[type]||'var(--border)')+';color:'+(colors[type]||'var(--text)')+';font-size:13px;z-index:200;animation:fadeIn .2s ease;max-width:400px;word-break:break-all';el.textContent=msg;document.body.appendChild(el);setTimeout(()=>el.remove(),4000)}
function closeModal(id){document.getElementById(id).classList.remove('show')}
document.querySelectorAll('.modal-overlay').forEach(m=>{m.addEventListener('click',e=>{if(e.target===m)m.classList.remove('show')})});
async function refreshAll(){await Promise.all([refreshTasks(),refreshTerminal()])}
function startAutoRefresh(){if(refreshTimer)clearInterval(refreshTimer);refreshTimer=setInterval(()=>{refreshTasks();refreshTerminal()},3000)}
document.addEventListener('DOMContentLoaded',()=>{loadSysInfo();loadPackages();refreshTasks();refreshTerminal();startAutoRefresh()});
</script>
</body>
</html>'''


# ═══════════════════════════════════════════════════════
#  主入口
# ═══════════════════════════════════════════════════════

def main():
    for d in [DB_DIR, LOG_DIR, PKG_DIR, BACKUP_DIR, CACHE_DIR]:
        d.mkdir(parents=True, exist_ok=True)

    host = os.environ.get("KURALI_WEBUI_HOST", "0.0.0.0")
    port = WEBUI_PORT
    args = sys.argv[1:]
    for i, arg in enumerate(args):
        if arg in ('-p','--port') and i+1 < len(args): port = int(args[i+1])
        elif arg in ('-h','--host') and i+1 < len(args): host = args[i+1]
        elif arg in ('--help',):
            print(f"""KuraliAll WebUI v{VERSION}

用法: python3 kuraliAll-webui.py [选项]

选项:
  -p, --port <端口>    监听端口 (默认: 8080)
  -h, --host <地址>    监听地址 (默认: 0.0.0.0)
  --help               显示帮助

环境变量:
  KURALI_WEBUI_PORT    监听端口
  KURALI_WEBUI_HOST    监听地址
  KURALI_HOME          KuraliAll 数据目录 (默认: /var/lib/kuraliAll)
""")
            sys.exit(0)

    add_log("OK", f"KuraliAll WebUI v{VERSION} 启动")
    add_log("INFO", f"数据目录: {KURALI_HOME}")

    server = http.server.HTTPServer((host, port), KuraliWebHandler)
    print(f"""
 ╔══════════════════════════════════════════════╗
 ║   KuraliAll WebUI v{VERSION}                  ║
 ║   全能 Linux 包管理器 Web 界面               ║
 ╠══════════════════════════════════════════════╣
 ║   地址: http://{host}:{port}{' '*(27-len(host)-len(str(port)))}║
 ║   按 Ctrl+C 停止服务                        ║
 ╚══════════════════════════════════════════════╝
""")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n停止服务...")
        add_log("INFO", "WebUI 已停止")
        server.server_close()


if __name__ == '__main__':
    main()
