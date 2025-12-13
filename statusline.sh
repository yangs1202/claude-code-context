#!/bin/bash

# stdin에서 JSON 데이터 읽기
input=$(cat)

# 상태 파일 경로
STATE_FILE="/tmp/claude-statusline-state"

# 현재 session_id 추출
CURRENT_SESSION=$(echo "$input" | jq -r '.session_id // ""')

# jq로 컨텍스트 윈도우 정보 추출
INPUT_TOKENS=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
OUTPUT_TOKENS=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')

# 이전 세션 정보 읽기
if [ -f "$STATE_FILE" ]; then
    PREV_SESSION=$(jq -r '.session_id // ""' "$STATE_FILE")
    BASELINE_INPUT=$(jq -r '.baseline_input // 0' "$STATE_FILE")
    BASELINE_OUTPUT=$(jq -r '.baseline_output // 0' "$STATE_FILE")
else
    PREV_SESSION=""
    BASELINE_INPUT=0
    BASELINE_OUTPUT=0
fi

# 세션이 변경되었으면 baseline 업데이트
if [ "$CURRENT_SESSION" != "$PREV_SESSION" ] && [ -n "$CURRENT_SESSION" ]; then
    BASELINE_INPUT=$INPUT_TOKENS
    BASELINE_OUTPUT=$OUTPUT_TOKENS

    # 상태 저장
    echo "{\"session_id\":\"$CURRENT_SESSION\",\"baseline_input\":$BASELINE_INPUT,\"baseline_output\":$BASELINE_OUTPUT}" > "$STATE_FILE"
fi

# 현재 대화의 실제 토큰 계산 (baseline 차감)
ACTUAL_INPUT=$((INPUT_TOKENS - BASELINE_INPUT))
ACTUAL_OUTPUT=$((OUTPUT_TOKENS - BASELINE_OUTPUT))
TOTAL_TOKENS=$((ACTUAL_INPUT + ACTUAL_OUTPUT))
REMAINING=$((CONTEXT_SIZE - TOTAL_TOKENS))

# 음수 방지
if [ $TOTAL_TOKENS -lt 0 ]; then
    TOTAL_TOKENS=0
    REMAINING=$CONTEXT_SIZE
fi

# 사용률 계산
if [ $CONTEXT_SIZE -gt 0 ]; then
    PERCENTAGE=$((TOTAL_TOKENS * 100 / CONTEXT_SIZE))
else
    PERCENTAGE=0
fi

# K 단위로 변환
TOTAL_K=$(awk "BEGIN {printf \"%.1f\", $TOTAL_TOKENS / 1000}")
REMAINING_K=$(awk "BEGIN {printf \"%.1f\", $REMAINING / 1000}")

# 진행률 바 생성 (20칸)
BAR_LENGTH=20
FILLED=$((PERCENTAGE * BAR_LENGTH / 100))
if [ $FILLED -gt $BAR_LENGTH ]; then
    FILLED=$BAR_LENGTH
fi

# 색상 코드 정의
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

# 사용량에 따라 색상 선택
if [ $PERCENTAGE -lt 60 ]; then
    COLOR=$GREEN
elif [ $PERCENTAGE -lt 85 ]; then
    COLOR=$YELLOW
else
    COLOR=$RED
fi

# 진행률 바 생성
BAR="["
for ((i=0; i<$BAR_LENGTH; i++)); do
    if [ $i -lt $FILLED ]; then
        BAR+="█"
    else
        BAR+="░"
    fi
done
BAR+="]"

# 압축 상태 확인
COMPRESSED=""
if [ $PERCENTAGE -gt 100 ]; then
    COMPRESSED=" (Compressed)"
fi

# 출력
echo -e "${COLOR}Context: ${BAR} ${PERCENTAGE}%${COMPRESSED} | Remaining: ${REMAINING_K}K${RESET}"
