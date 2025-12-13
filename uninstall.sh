#!/bin/bash

set -e

echo "======================================"
echo "Claude Code 컨텍스트 상태바 제거"
echo "======================================"
echo ""

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

# statusline.sh 제거
echo "1. statusline.sh 제거 중..."
if [ -f "$CLAUDE_DIR/statusline.sh" ]; then
    rm "$CLAUDE_DIR/statusline.sh"
    echo -e "${GREEN}✓ $CLAUDE_DIR/statusline.sh 제거 완료${NC}"
else
    echo -e "${YELLOW}⚠ statusline.sh가 없습니다.${NC}"
fi
echo ""

# 상태 파일 제거
echo "2. 상태 파일 제거 중..."
if [ -f "/tmp/claude-statusline-state" ]; then
    rm "/tmp/claude-statusline-state"
    echo -e "${GREEN}✓ 상태 파일 제거 완료${NC}"
else
    echo -e "${YELLOW}⚠ 상태 파일이 없습니다.${NC}"
fi
echo ""

# settings.json에서 statusLine 설정 제거
echo "3. settings.json 설정 제거 중..."
if [ -f "$SETTINGS_FILE" ]; then
    # 백업 생성
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.uninstall-backup"
    echo -e "${GREEN}✓ 기존 설정 백업: $SETTINGS_FILE.uninstall-backup${NC}"

    # jq를 사용하여 statusLine 설정 제거
    TMP_FILE=$(mktemp)
    jq 'del(.statusLine)' "$SETTINGS_FILE" > "$TMP_FILE"
    mv "$TMP_FILE" "$SETTINGS_FILE"

    echo -e "${GREEN}✓ settings.json 설정 제거 완료${NC}"
else
    echo -e "${YELLOW}⚠ settings.json이 없습니다.${NC}"
fi
echo ""

# 제거 완료
echo "======================================"
echo -e "${GREEN}✅ 제거가 완료되었습니다!${NC}"
echo "======================================"
echo ""
echo "Claude Code를 재시작하면 상태바가 기본값으로 돌아갑니다."
echo ""
