#!/usr/bin/env python3
"""
KuraliAll WebUI API版 — 调用Shell版本的API接口
"""

import http.server
import json
import os
import subprocess
import sys
import threading
import time
import tempfile
import shutil
from pathlib import Path
from urllib.parse import urlparse, parse_qs, unquote

# ═══════════════════════════════════════════════════════
#  配置
# ═══════════════════════════════════════════════════════

VERSION = "2.3.0"
WEBUI_PORT = int(os.environ.get("KURALI_WEBUI_PORT", "8080"))

# 自动检测数据目录路径
if os.path.exists("/var/lib/kuraliAll"):
    KURALI_HOME = Path("/var/lib/kuraliAll")
else:
    KURALI_HOME = Path("/var/lib/kuraliAll")

PKG_DIR = KURALI_HOME / "pkg"
LOG_DIR = KURALI_HOME / "logs"

# ═══════════════════════════════════════════════════════
#  Shell API调用函数
# ═══════════════════════════════════════════════════════

def call_kurali_api(action, arg=""):
    """调用kurali API命令"""
    try:
        cmd = ["kurali", "api", action, arg] if arg else ["kurali", "api", action]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0:
            try:
                return json.loads(result.stdout)
            except json.JSONDecodeError:
                return {"status": "error", "message": "JSON解析失败", "output": result.stdout}
        else:
            # 尝试解析错误JSON
            try:
                return json.loads(result.stdout)
            except json.JSONDecodeError:
                return {"status": "error", "message": result.stdout or result.stderr}
    except subprocess.TimeoutExpired:
        return {"status": "error", "message": "命令超时"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

def call_kurali_command(cmd, *args):
    """调用kurali命令"""
    try:
        command = ["kurali", cmd]
        if args:
            command.extend(args)
        result = subprocess.run(command, capture_output=True, text=True, timeout=30)
        return result.returncode == 0, result.stdout, result.stderr
    except Exception as e:
        return False, "", str(e)

# ═══════════════════════════════════════════════════════
#  HTTP服务器
# ═══════════════════════════════════════════════════════

class KuraliHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path
        
        # API路由
        if path == "/api/packages":
            data = call_kurali_api("list")
            self.send_json_response(data)
            
        elif path.startswith("/api/package"):
            pkg_name = path.split("/api/package/")[1]
            data = call_kurali_api("info", pkg_name)
            self.send_json_response(data)
            
        elif path == "/api/deps":
            data = call_kurali_api("deps")
            self.send_json_response(data)
            
        elif path.startswith("/api/deps/program"):
            # /api/deps/program?path=/usr/bin/program
            params = parse_qs(urlparse(path).query)
            program_path = params.get("path", [""])[0]
            if program_path:
                data = call_kurali_api("deps", program_path)
                self.send_json_response(data)
            else:
                self.send_json_response({"status": "error", "message": "缺少程序路径参数"})
            
        elif path == "/api/system":
            # 系统信息
            data = {
                "status": "success",
                "system": {
                    "kurali_version": "2.2.0",
                    "distro": get_distro(),
                    "arch": os.uname().machine,
                    "pkgs_count": len([p for p in PKG_DIR.iterdir() if p.is_dir()])
                }
            }
            self.send_json_response(data)
            
        elif path == "/":
            # HTML首页
            self.send_html_response()
            
        else:
            self.send_json_response({"status": "error", "message": "未知路由"})
    
    def do_POST(self):
        path = self.path
        
        if path == "/api/install":
            # 文件上传和安装
            content_length = int(self.headers.get('Content-Length', 0))
            content_type = self.headers.get('Content-Type', '')
            
            if content_type.startswith('multipart/form-data'):
                # 解析multipart数据
                body_bytes = self.rfile.read(content_length)
                fields = self._parse_multipart(body_bytes, content_type)
                
                if 'file' not in fields or not fields['file']['is_file']:
                    self.send_json_response({"status": "error", "message": "未上传文件"})
                    return
                    
                # 保存文件
                temp_path = tempfile.mktemp()
                with open(temp_path, 'wb') as f:
                    f.write(fields['file']['data'])
                    
                # 读取模式参数
                mode = fields.get('mode', ['sandbox'])[0]
                
                # 调用kurali安装
                success, stdout, stderr = call_kurali_command("i", temp_path)
                os.unlink(temp_path)
                
                if success:
                    self.send_json_response({"status": "success", "message": "安装成功", "output": stdout})
                else:
                    self.send_json_response({"status": "error", "message": "安装失败", "output": stderr})
                    
            else:
                # JSON数据
                body = self.rfile.read(content_length).decode('utf-8')
                try:
                    data = json.loads(body)
                    file_path = data.get("file_path")
                    mode = data.get("mode", "sandbox")
                    
                    if not file_path:
                        self.send_json_response({"status": "error", "message": "缺少文件路径"})
                        return
                    
                    success, stdout, stderr = call_kurali_command("i", file_path)
                    if success:
                        self.send_json_response({"status": "success", "message": "安装成功", "output": stdout})
                    else:
                        self.send_json_response({"status": "error", "message": "安装失败", "output": stderr})
                except json.JSONDecodeError:
                    self.send_json_response({"status": "error", "message": "JSON解析失败"})
                    
        elif path == "/api/remove":
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length).decode('utf-8')
            try:
                data = json.loads(body)
                pkg_name = data.get("package_name")
                
                if not pkg_name:
                    self.send_json_response({"status": "error", "message": "缺少包名"})
                    return
                    
                data = call_kurali_api("remove", pkg_name)
                self.send_json_response(data)
            except json.JSONDecodeError:
                self.send_json_response({"status": "error", "message": "JSON解析失败"})
                
        else:
            self.send_json_response({"status": "error", "message": "未知路由"})
    
    def _parse_multipart(self, body_bytes, content_type):
        """手动解析 multipart/form-data"""
        import re
        
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
    
    def send_json_response(self, data):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode('utf-8'))
    
    def send_html_response(self):
        html = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>KuraliAll WebUI v2.3.0</title>
    <style>
        body { font-family: sans-serif; margin: 20px; }
        h1 { color: #333; }
        .container { max-width: 800px; margin: auto; }
        .api-list { background: #f5f5f5; padding: 10px; border-radius: 5px; margin-bottom: 20px; }
        .api-item { margin: 5px 0; }
        .api-url { color: #007acc; }
    </style>
</head>
<body>
    <div class="container">
        <h1>KuraliAll WebUI API</h1>
        <p>版本: 2.3.0</p>
        <p>此WebUI使用Shell版本API接口，提供以下端点：</p>
        
        <div class="api-list">
            <h2>API端点</clean>
            <div class="api-item">
                <strong>GET</strong> <span class="api-url">/api/packages</span> - 列出所有安装的包
            </div>
            <div class="api-item">
                <strong>GET</strong> <span class="api-url">/api/package/{name}</span> - 查看包详情
            </div>
            <div class="api-item">
                <strong>GET</strong> <span class="api-url">/api/deps</span> - 检查系统依赖
            </div>
            <div class="api-item">
                <strong>GET</strong> <span class="api-url">/api/deps/program?path={path}</span> - 检查程序依赖
            </div>
            <div class="api-item">
                <strong>GET</strong> <span class="api-url">/api/system</span> - 系统信息
            </div>
            <div class="api-item">
                <strong>POST</strong> <span class="api-url">/api/install</span> - 安装包（multipart上传）
            </div>
            <div class="api-item">
                <strong>POST</strong> <span class="api-url">/api/remove</span> - 卸载包
            </div>
        </div>
        
        <p>使用示例：</p>
        <code>curl http://localhost:8080/api/packages</code>
        
        <h2>下一步计划</h2>
        <p>完整的Web界面将在后续版本中添加。</p>
    </div>
</body>
</html>"""
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(html.encode('utf-8'))

def get_distro():
    """获取发行版信息"""
    try:
        if os.path.exists("/etc/os-release"):
            with open("/etc/os-release") as f:
                for line in f:
                    if line.startswith("ID="):
                        return line.split("=")[1].strip().replace('"', '').replace("'", '')
        elif os.path.exists("/etc/debian_version"):
            return "debian"
        elif os.path.exists("/etc/redhat-release"):
            return "rhel"
        elif os.path.exists("/etc/arch-release"):
            return "arch"
        elif os.path.exists("/etc/alpine-release"):
            return "alpine"
    except:
        return "unknown"
    return "unknown"

def main():
    host = os.environ.get("KURALI_WEBUI_HOST", "0.0.0.0")
    port = WEBUI_PORT
    
    print(f"KuraliAll WebUI API v{VERSION}")
    print(f"服务器: http://{host}:{port}")
    print(f"API基础路径: /api/*")
    
    server = http.server.HTTPServer((host, port), KuraliHandler)
    server.serve_forever()

if __name__ == "__main__":
    main()