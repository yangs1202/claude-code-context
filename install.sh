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

# 플랜 및 버짓 설정
echo "2. 월별 버짓 설정..."
echo ""
echo "사용 중인 플랜을 선택하세요:"
echo "  1) API Billing (직접 버짓 입력)"
echo "  2) Claude Pro (\$20/월)"
echo "  3) Claude Max 5x (\$100/월)"
echo "  4) Claude Max 20x (\$200/월)"
echo ""
read -p "선택 (1-4): " PLAN_CHOICE

case $PLAN_CHOICE in
    1)
        PLAN_TYPE="api"
        read -p "월별 최대 버짓 (달러, 예: 50): " BUDGET_AMOUNT
        if ! [[ "$BUDGET_AMOUNT" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            echo -e "${RED}❌ 오류: 숫자를 입력하세요.${NC}"
            exit 1
        fi
        ;;
    2)
        PLAN_TYPE="pro"
        BUDGET_AMOUNT=20
        ;;
    3)
        PLAN_TYPE="max_5x"
        BUDGET_AMOUNT=100
        ;;
    4)
        PLAN_TYPE="max_20x"
        BUDGET_AMOUNT=200
        ;;
    *)
        echo -e "${YELLOW}⚠ 잘못된 선택입니다. 기본값(API \$100)으로 설정합니다.${NC}"
        PLAN_TYPE="api"
        BUDGET_AMOUNT=100
        ;;
esac

echo -e "${GREEN}✓ 플랜: $PLAN_TYPE, 버짓: \$${BUDGET_AMOUNT}/월${NC}"
echo ""

# current_usage.json 경로 설정
echo "3. current_usage.json 경로 설정..."
echo ""
echo "사용량 정보가 담긴 current_usage.json 파일 경로를 입력하세요."
echo "  예: /home/user/usage/current_usage.json"
echo "  (건너뛰려면 Enter)"
echo ""
read -p "경로: " USAGE_FILE_PATH

if [ -n "$USAGE_FILE_PATH" ]; then
    # 경로 유효성 확인
    if [ -f "$USAGE_FILE_PATH" ]; then
        echo -e "${GREEN}✓ 파일 확인 완료: $USAGE_FILE_PATH${NC}"
    else
        echo -e "${YELLOW}⚠ 파일이 아직 존재하지 않지만, 경로를 저장합니다.${NC}"
    fi
else
    echo -e "${YELLOW}⚠ 경로를 입력하지 않았습니다. current_usage.json 기능을 사용하지 않습니다.${NC}"
fi
echo ""

# Claude 디렉토리 확인 및 생성
echo "4. Claude Code 디렉토리 확인 중..."
CLAUDE_DIR="$HOME/.claude"

if [ ! -d "$CLAUDE_DIR" ]; then
    echo -e "${YELLOW}⚠ ~/.claude 디렉토리가 없습니다. 생성합니다.${NC}"
    mkdir -p "$CLAUDE_DIR"
fi

echo -e "${GREEN}✓ 디렉토리 확인 완료${NC}"
echo ""

# statusline.sh 복사
echo "5. statusline.sh 설치 중..."
cp statusline.sh "$CLAUDE_DIR/statusline.sh"
chmod +x "$CLAUDE_DIR/statusline.sh"
echo -e "${GREEN}✓ $CLAUDE_DIR/statusline.sh 설치 완료${NC}"
echo ""

# budget-config.json 저장
echo "6. 버짓 설정 저장 중..."
BUDGET_CONFIG_FILE="$CLAUDE_DIR/budget-config.json"
if [ -n "$USAGE_FILE_PATH" ]; then
cat > "$BUDGET_CONFIG_FILE" << EOF
{
  "plan_type": "$PLAN_TYPE",
  "monthly_budget": $BUDGET_AMOUNT,
  "usage_file": "$USAGE_FILE_PATH"
}
EOF
else
cat > "$BUDGET_CONFIG_FILE" << EOF
{
  "plan_type": "$PLAN_TYPE",
  "monthly_budget": $BUDGET_AMOUNT
}
EOF
fi
echo -e "${GREEN}✓ $BUDGET_CONFIG_FILE 저장 완료${NC}"
echo ""

# settings.json 업데이트
echo "7. settings.json 설정 중..."
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
