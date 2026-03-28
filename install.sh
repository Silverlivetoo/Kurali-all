#!/usr/bin/env bash
# KuraliAll v3.0 一键安装脚本 — 纯 Shell
set -uo pipefail

GREEN='\033[1;32m'; BLUE='\033[1;34m'; RED='\033[1;31m'; NC='\033[0m'

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="/var/lib/kuraliAll"
BIN="/usr/local/bin/kurali"

[[ "$EUID" -ne 0 ]] && { echo -e "${RED}请用 sudo 运行${NC}"; exit 1; }

echo -e "${BLUE}[KuraliAll]${NC} 安装到系统..."

mkdir -p "$TARGET"
cp -a "$DIR/modules" "$DIR/config" "$DIR/hooks" "$DIR/kuraliAll.sh" "$TARGET/" 2>/dev/null || true
chmod +x "$TARGET/kuraliAll.sh"
mkdir -p "$TARGET"/{db,logs,pkg,backup,cache}

cat > "$BIN" << 'EOF'
#!/bin/bash
exec /var/lib/kuraliAll/kuraliAll.sh "$@"
EOF
chmod +x "$BIN"

echo "3.0.0" > "$TARGET/version"

echo -e "\n${GREEN}✓ 安装完成！${NC}"
echo -e "  入口: ${BLUE}${BIN}${NC}"
echo -e "  数据: ${BLUE}${TARGET}${NC}"
echo -e "  帮助: ${GREEN}kurali help${NC}"
echo -e "  安装: ${GREEN}sudo kurali i <文件>${NC}"
echo ""
