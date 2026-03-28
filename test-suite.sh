#!/bin/bash
# KuraliAll 测试套件

echo "=== KuraliAll 功能测试套件 ==="

# 1. 基础命令测试
echo "1. 基础命令测试..."
kurali version
kurali help

# 2. API测试
echo "2. API测试..."
echo "API列表:"
kurali api list
echo ""
echo "API依赖检查:"
kurali api deps
echo ""
echo "API程序依赖检查:"
kurali api deps /usr/local/bin/api-test.sh || echo "找不到文件"

# 3. 打包测试
echo "3. 打包测试..."
echo "创建测试文件..."
echo "#!/bin/bash
echo 'Test package for KuraliAll'
echo 'Version: 1.0.0'" > /tmp/test.sh
chmod +x /tmp/test.sh
tar czf /tmp/test.tar.gz /tmp/test.sh

echo "打包为kurali格式..."
kurali pack /tmp/test.tar.gz
ls -lh /tmp/test-*.kurali

# 4. 安装测试
echo "4. 安装测试..."
kurali i /tmp/test-unknown.kurali

# 5. 查看安装结果
echo "5. 查看安装结果..."
kurali l
kurali f test
kurali s test

# 6. RAM模式测试
echo "6. RAM模式测试..."
kurali --ram /tmp/test-unknown.kurali

# 7. 卸载测试
echo "7. 卸载测试..."
kurali r test

# 8. 验证卸载
echo "8. 验证卸载..."
kurali l

# 9. WebUI测试
echo "9. WebUI启动测试..."
python3 kuraliAll-webui.py -h 127.0.0.1 &
WEBUI_PID=$!
sleep 2
if curl -s http://127.0.0.1:8080 > /dev/null; then
    echo "WebUI启动成功"
else
    echo "WebUI启动失败"
fi
kill $WEBUI_PID

echo "=== 测试完成 ==="
rm -f /tmp/test.sh /tmp/test.tar.gz /tmp/test-unknown.kurali