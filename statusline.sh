#!/bin/bash

# stdin에서 JSON 데이터 읽기
input=$(cat)

# 상태 파일 경로
STATE_FILE="/tmp/claude-statusline-state"
LOG_FILE="/tmp/claude-statusline-debug.log"

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

# 세션이 변경되었을 때 처리
if [ "$CURRENT_SESSION" != "$PREV_SESSION" ] && [ -n "$CURRENT_SESSION" ]; then
    # 이전 토큰 총합 계산
    PREV_TOTAL=$((BASELINE_INPUT + BASELINE_OUTPUT))
    CURRENT_TOTAL=$((INPUT_TOKENS + OUTPUT_TOKENS))

    # 토큰이 50% 이상 감소했으면 진짜 clear로 판단
    THRESHOLD=$((PREV_TOTAL / 2))

    if [ $CURRENT_TOTAL -lt $THRESHOLD ] || [ $PREV_TOTAL -eq 0 ]; then
        # 진짜 clear: baseline 리셋
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ 세션 변경 감지 (진짜 clear) - 이전: $PREV_TOTAL, 현재: $CURRENT_TOTAL" >> "$LOG_FILE"
        BASELINE_INPUT=$INPUT_TOKENS
        BASELINE_OUTPUT=$OUTPUT_TOKENS
    else
        # session_id만 변경됨: baseline 유지하고 session_id만 업데이트
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  세션 ID만 변경됨 (baseline 유지) - 이전: $PREV_TOTAL, 현재: $CURRENT_TOTAL" >> "$LOG_FILE"
    fi

    # 상태 저장 (session_id는 항상 업데이트)
    echo "{\"session_id\":\"$CURRENT_SESSION\",\"baseline_input\":$BASELINE_INPUT,\"baseline_output\":$BASELINE_OUTPUT}" > "$STATE_FILE"
fi

# 디버그 로그 (토큰이 감소했을 때)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Session: $CURRENT_SESSION | Input: $INPUT_TOKENS (Baseline: $BASELINE_INPUT) | Output: $OUTPUT_TOKENS (Baseline: $BASELINE_OUTPUT)" >> "$LOG_FILE"

# 자동 요약 감지: baseline이 현재 토큰보다 크면 재조정
if [ $INPUT_TOKENS -lt $BASELINE_INPUT ] || [ $OUTPUT_TOKENS -lt $BASELINE_OUTPUT ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  토큰 감소 감지! Input: $INPUT_TOKENS < $BASELINE_INPUT or Output: $OUTPUT_TOKENS < $BASELINE_OUTPUT" >> "$LOG_FILE"
    BASELINE_INPUT=$INPUT_TOKENS
    BASELINE_OUTPUT=$OUTPUT_TOKENS

    # 상태 업데이트
    if [ -n "$CURRENT_SESSION" ]; then
        echo "{\"session_id\":\"$CURRENT_SESSION\",\"baseline_input\":$BASELINE_INPUT,\"baseline_output\":$BASELINE_OUTPUT}" > "$STATE_FILE"
    fi
fi

# 현재 대화의 실제 토큰 계산 (baseline 차감)
ACTUAL_INPUT=$((INPUT_TOKENS - BASELINE_INPUT))
ACTUAL_OUTPUT=$((OUTPUT_TOKENS - BASELINE_OUTPUT))
TOTAL_TOKENS=$((ACTUAL_INPUT + ACTUAL_OUTPUT))
REMAINING=$((CONTEXT_SIZE - TOTAL_TOKENS))

# 음수 방지 (추가 안전장치)
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
