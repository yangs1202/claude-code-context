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

# 현재 모델 추출 - settings.json에서 읽기
MODEL_NAME=""
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [ -f "$CLAUDE_SETTINGS" ]; then
    MODEL_NAME=$(jq -r '.model // ""' "$CLAUDE_SETTINGS" 2>/dev/null)
fi

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

# 세션이 변경되었을 때 처리 - 무조건 baseline 리셋
if [ "$CURRENT_SESSION" != "$PREV_SESSION" ] && [ -n "$CURRENT_SESSION" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ 세션 변경 감지 - baseline 리셋" >> "$LOG_FILE"
    BASELINE_INPUT=$INPUT_TOKENS
    BASELINE_OUTPUT=$OUTPUT_TOKENS

    # 상태 저장
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

# 버짓 설정 파일 경로
BUDGET_CONFIG="$HOME/.claude/budget-config.json"

# ccusage로 이번 달 비용 가져오기 및 버짓 퍼센트 계산
BUDGET_INFO=""
if command -v ccusage &> /dev/null; then
    # 현재 년-월 가져오기
    CURRENT_MONTH=$(date +"%Y-%m")

    # ccusage 실행하고 이번 달 비용 추출
    MONTHLY_COST=$(ccusage monthly -j 2>/dev/null | jq -r --arg month "$CURRENT_MONTH" '.monthly[] | select(.month == $month) | .totalCost // 0')

    if [ -n "$MONTHLY_COST" ] && [ "$MONTHLY_COST" != "null" ] && [ "$MONTHLY_COST" != "0" ]; then
        FORMATTED_COST=$(printf "%.2f" "$MONTHLY_COST")

        # 버짓 설정이 있으면 퍼센트 바 표시
        if [ -f "$BUDGET_CONFIG" ]; then
            MONTHLY_BUDGET=$(jq -r '.monthly_budget // 0' "$BUDGET_CONFIG")

            if [ "$MONTHLY_BUDGET" != "0" ] && [ "$MONTHLY_BUDGET" != "null" ]; then
                # 플랜 타입 확인
                PLAN_TYPE=$(jq -r '.plan_type // "api"' "$BUDGET_CONFIG")

                # 사용률 계산
                USAGE_PERCENT=$(awk "BEGIN {
                    used = $MONTHLY_COST;
                    budget = $MONTHLY_BUDGET;
                    usage = used / budget * 100;
                    printf \"%.0f\", usage
                }")

                # 플랜 타입에 따라 색상 로직 분기
                if [ "$PLAN_TYPE" = "api" ]; then
                    # API Billing: 남은 버짓 기준 (적게 쓸수록 초록)
                    if [ "$USAGE_PERCENT" -ge 100 ]; then
                        BUDGET_COLOR=$RED
                    elif [ "$USAGE_PERCENT" -ge 75 ]; then
                        BUDGET_COLOR=$YELLOW
                    else
                        BUDGET_COLOR=$GREEN
                    fi
                    # 바는 남은 버짓 표시
                    BAR_PERCENT=$((100 - USAGE_PERCENT))
                    if [ $BAR_PERCENT -lt 0 ]; then BAR_PERCENT=0; fi
                else
                    # Pro/Max 구독: 사용량 기준 (많이 쓸수록 초록 = 뽕뽑기)
                    if [ "$USAGE_PERCENT" -ge 100 ]; then
                        BUDGET_COLOR=$GREEN
                    elif [ "$USAGE_PERCENT" -ge 50 ]; then
                        BUDGET_COLOR=$YELLOW
                    else
                        BUDGET_COLOR=$RED
                    fi
                    # 바는 사용량 표시
                    BAR_PERCENT=$USAGE_PERCENT
                    if [ $BAR_PERCENT -gt 100 ]; then BAR_PERCENT=100; fi
                fi

                # 버짓 바 생성 (10칸)
                BUDGET_BAR_LEN=10
                BUDGET_FILLED=$((BAR_PERCENT * BUDGET_BAR_LEN / 100))
                BUDGET_BAR="["
                for ((i=0; i<$BUDGET_BAR_LEN; i++)); do
                    if [ $i -lt $BUDGET_FILLED ]; then
                        BUDGET_BAR+="█"
                    else
                        BUDGET_BAR+="░"
                    fi
                done
                BUDGET_BAR+="]"

                BUDGET_INFO=" | ${BUDGET_COLOR}💰 ${BUDGET_BAR} \$${FORMATTED_COST}/\$${MONTHLY_BUDGET}${RESET}"
            else
                BUDGET_INFO=" | 💰 \$${FORMATTED_COST}"
            fi
        else
            BUDGET_INFO=" | 💰 \$${FORMATTED_COST}"
        fi
    fi
fi

# 모델 정보 포맷팅 - JSON 문자열이 아닌 경우에만 표시
MODEL_INFO=""
if [ -n "$MODEL_NAME" ] && [ "$MODEL_NAME" != "null" ]; then
    # JSON 형식인지 확인 ('{' 포함 여부)
    if [[ "$MODEL_NAME" != *"{"* ]]; then
        MODEL_INFO=" | 🤖 $MODEL_NAME"
    fi
fi

# 출력
echo -e "${COLOR}Context: ${BAR} ${PERCENTAGE}%${COMPRESSED} | Remaining: ${REMAINING_K}K${RESET}${MODEL_INFO}${BUDGET_INFO}"
