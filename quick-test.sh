#!/bin/bash
# KuraliAll快速测试脚本

echo "=== 测试1: API列表 ==="
bash kuraliAll.sh api list

echo "=== 测试2: API详情 ==="
bash kuraliAll.sh api info api-test

echo "=== 测试3: API依赖检查 ==="
bash kuraliAll.sh api deps

echo "=== 测试4: 创建测试包 ==="
echo "#!/bin/bash\necho 'Test'" > test.sh
chmod +x test.sh
tar czf test.tar.gz test.sh

echo "=== 测试5: 打包 ==="
bash kuraliAll.sh pack test.tar.gz

echo "=== 测试6: 安装 ==="
bash kuraliAll.sh i test-unknown.kurali

echo "=== 测试7: 查看已安装 ==="
bash kuraliAll.sh l

echo "=== 测试8: 卸载 ==="
bash kuraliAll.sh r test

echo "=== 测试9: RAM模式 ==="
bash kuraliAll.sh run test-unknown.kurali

echo "=== 清理 ==="
rm -f test.sh test.tar.gz test-unknown.kurali