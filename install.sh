#!/bin/bash

set -e

echo "======================================"
echo "Claude Code 컨텍스트 상태바 설치"
echo "======================================"
echo ""

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 의존성 확인
echo "1. 의존성 확인 중..."

if ! command -v jq &> /dev/null; then
    echo -e "${RED}❌ 오류: jq가 설치되어 있지 않습니다.${NC}"
    echo ""
    echo "다음 명령어로 설치하세요:"
    echo "  macOS:   brew install jq"
    echo "  Linux:   sudo apt-get install jq  또는  sudo yum install jq"
    exit 1
fi

if ! command -v awk &> /dev/null; then
    echo -e "${RED}❌ 오류: awk가 설치되어 있지 않습니다.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 모든 의존성이 설치되어 있습니다.${NC}"
echo ""

# Claude 디렉토리 확인 및 생성
echo "2. Claude Code 디렉토리 확인 중..."
CLAUDE_DIR="$HOME/.claude"

if [ ! -d "$CLAUDE_DIR" ]; then
    echo -e "${YELLOW}⚠ ~/.claude 디렉토리가 없습니다. 생성합니다.${NC}"
    mkdir -p "$CLAUDE_DIR"
fi

echo -e "${GREEN}✓ 디렉토리 확인 완료${NC}"
echo ""

# statusline.sh 복사
echo "3. statusline.sh 설치 중..."
cp statusline.sh "$CLAUDE_DIR/statusline.sh"
chmod +x "$CLAUDE_DIR/statusline.sh"
echo -e "${GREEN}✓ $CLAUDE_DIR/statusline.sh 설치 완료${NC}"
echo ""

# settings.json 업데이트
echo "4. settings.json 설정 중..."
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

if [ ! -f "$SETTINGS_FILE" ]; then
    echo -e "${YELLOW}⚠ settings.json이 없습니다. 새로 생성합니다.${NC}"
    cat > "$SETTINGS_FILE" << 'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
EOF
else
    # 백업 생성
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup"
    echo -e "${GREEN}✓ 기존 설정 백업: $SETTINGS_FILE.backup${NC}"

    # jq를 사용하여 statusLine 설정 추가/업데이트
    TMP_FILE=$(mktemp)
    jq '. + {
      "statusLine": {
        "type": "command",
        "command": "~/.claude/statusline.sh"
      }
    }' "$SETTINGS_FILE" > "$TMP_FILE"

    mv "$TMP_FILE" "$SETTINGS_FILE"
fi

echo -e "${GREEN}✓ settings.json 설정 완료${NC}"
echo ""

# 설치 완료
echo "======================================"
echo -e "${GREEN}✅ 설치가 완료되었습니다!${NC}"
echo "======================================"
echo ""
echo "다음 단계:"
echo "1. Claude Code를 재시작하세요"
echo "2. 상태바에 컨텍스트 사용량이 표시됩니다"
echo ""
echo "표시 형식:"
echo "  Context: [████████░░░░░░░░░░░░] 40% | Remaining: 120.0K"
echo ""
echo "색상:"
echo "  - 초록색: 60% 미만"
echo "  - 노란색: 60-85%"
echo "  - 빨간색: 85% 이상"
echo "  - '(Compressed)' 표시: 100% 초과"
echo ""
echo "제거하려면: ./uninstall.sh"
echo ""
