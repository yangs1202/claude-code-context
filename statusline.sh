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

# 현재 모델 추출 - 입력 JSON에서 우선 읽기, fallback으로 settings.json
MODEL_ID=$(echo "$input" | jq -r '.model.id // ""')
MODEL_DISPLAY=$(echo "$input" | jq -r '.model.display_name // ""')
MODEL_NAME="${MODEL_ID:-$MODEL_DISPLAY}"

# 입력 JSON에 모델 정보가 없으면 settings.json에서 읽기
if [ -z "$MODEL_NAME" ]; then
    CLAUDE_SETTINGS="$HOME/.claude/settings.json"
    if [ -f "$CLAUDE_SETTINGS" ]; then
        MODEL_NAME=$(jq -r '.model // ""' "$CLAUDE_SETTINGS" 2>/dev/null)
    fi
fi

# 세션 비용 - 입력 JSON에서 직접 읽기 (Claude Code가 제공)
API_COST=$(echo "$input" | jq -r '.cost.total_cost_usd // ""')

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

# 모델별 가격표 (USD per 1M tokens: input output)
# Anthropic 공식 가격 기준 - 구체적인 패턴을 먼저 매칭
get_model_pricing() {
    local model="$1"
    case "$model" in
        # Opus 4.5/4.6 ($5/$25)
        *opus-4-5*|*opus-4-6*|*opus-4.5*|*opus-4.6*|*opus4.5*|*opus4.6*)
            echo "5.00 25.00" ;;
        # Opus 4/4.1 ($15/$75)
        *opus-4*|*opus4*)
            echo "15.00 75.00" ;;
        # Haiku 4.5 ($1/$5)
        *haiku-4*|*haiku4*)
            echo "1.00 5.00" ;;
        # Claude 3.5 Haiku ($0.80/$4)
        *haiku-3.5*|*haiku-3-5*|*haiku3.5*)
            echo "0.80 4.00" ;;
        # Claude 3 Haiku ($0.25/$1.25)
        *3-haiku*|*3haiku*)
            echo "0.25 1.25" ;;
        # Sonnet (전 버전 동일: $3/$15)
        *sonnet*)
            echo "3.00 15.00" ;;
        # Opus fallback ($15/$75)
        *opus*)
            echo "15.00 75.00" ;;
        # Haiku fallback ($1/$5)
        *haiku*)
            echo "1.00 5.00" ;;
        *)
            echo "" ;;
    esac
}

# 세션 비용 계산 - API 제공 값 우선, fallback으로 수동 계산
SESSION_COST=""
if [ -n "$API_COST" ] && [ "$API_COST" != "null" ] && [ "$API_COST" != "0" ]; then
    # Claude Code가 제공하는 실제 비용 사용
    SESSION_COST=$(awk "BEGIN {
        cost = $API_COST;
        if (cost < 0.01)
            printf \"%.4f\", cost;
        else if (cost < 1)
            printf \"%.3f\", cost;
        else
            printf \"%.2f\", cost;
    }")
elif [ -n "$MODEL_NAME" ] && [ "$MODEL_NAME" != "null" ] && [[ "$MODEL_NAME" != *"{"* ]]; then
    # fallback: 모델별 가격표로 수동 계산
    PRICING=$(get_model_pricing "$MODEL_NAME")
    if [ -n "$PRICING" ]; then
        INPUT_PRICE=$(echo "$PRICING" | awk '{print $1}')
        OUTPUT_PRICE=$(echo "$PRICING" | awk '{print $2}')
        SESSION_COST=$(awk "BEGIN {
            input_cost = $ACTUAL_INPUT / 1000000 * $INPUT_PRICE;
            output_cost = $ACTUAL_OUTPUT / 1000000 * $OUTPUT_PRICE;
            total = input_cost + output_cost;
            if (total < 0.01)
                printf \"%.4f\", total;
            else if (total < 1)
                printf \"%.3f\", total;
            else
                printf \"%.2f\", total;
        }")
    fi
fi

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

# 사용량 정보 가져오기
BUDGET_INFO=""
USAGE_FILE=""
if [ -f "$BUDGET_CONFIG" ]; then
    USAGE_FILE=$(jq -r '.usage_file // ""' "$BUDGET_CONFIG")
fi

if [ -n "$USAGE_FILE" ] && [ "$USAGE_FILE" != "null" ] && [ -f "$USAGE_FILE" ]; then
    # current_usage.json에서 사용량 읽기
    USAGE_TOTAL=$(jq -r '.total // 0' "$USAGE_FILE" 2>/dev/null)
    USAGE_SPEND=$(jq -r '.spend // 0' "$USAGE_FILE" 2>/dev/null)
    USAGE_UPDATED=$(jq -r '.updated_at // ""' "$USAGE_FILE" 2>/dev/null)

    if [ -n "$USAGE_TOTAL" ] && [ "$USAGE_TOTAL" != "null" ] && [ "$USAGE_TOTAL" != "0" ]; then
        FORMATTED_SPEND=$(printf "%.2f" "$USAGE_SPEND")
        FORMATTED_TOTAL=$(printf "%.2f" "$USAGE_TOTAL")

        # 사용률 계산
        USAGE_PERCENT=$(awk "BEGIN {
            spent = $USAGE_SPEND;
            total = $USAGE_TOTAL;
            usage = spent / total * 100;
            printf \"%.0f\", usage
        }")

        # 플랜 타입 확인
        PLAN_TYPE=$(jq -r '.plan_type // "api"' "$BUDGET_CONFIG")

        # 플랜 타입에 따라 색상 로직 분기
        if [ "$PLAN_TYPE" = "api" ] || [ "$PLAN_TYPE" = "manual" ]; then
            # API Billing / 수동: 남은 버짓 기준 (적게 쓸수록 초록)
            if [ "$USAGE_PERCENT" -ge 100 ]; then
                BUDGET_COLOR=$RED
            elif [ "$USAGE_PERCENT" -ge 75 ]; then
                BUDGET_COLOR=$YELLOW
            else
                BUDGET_COLOR=$GREEN
            fi
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

        # updated_at에서 시간 포맷팅 (ISO 8601 UTC → 로컬 타임존 변환)
        UPDATED_SHORT=""
        if [ -n "$USAGE_UPDATED" ] && [ "$USAGE_UPDATED" != "null" ]; then
            # "2026-02-05T12:34:56.789Z" → 로컬 타임존으로 변환 → "02/05 21:34"
            UPDATED_SHORT=$(date -d "$USAGE_UPDATED" +"%m/%d %H:%M" 2>/dev/null)
            if [ -z "$UPDATED_SHORT" ]; then
                # macOS의 경우 BSD date 사용
                # ISO 8601에서 밀리초 제거: "2026-02-05T12:34:56.789Z" → "2026-02-05T12:34:56Z"
                CLEANED_TS=$(echo "$USAGE_UPDATED" | sed 's/\.[0-9]*Z$/Z/')
                UPDATED_SHORT=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$CLEANED_TS" +"%s" 2>/dev/null | xargs -I{} date -j -r {} +"%m/%d %H:%M" 2>/dev/null)
            fi
            if [ -n "$UPDATED_SHORT" ]; then
                UPDATED_SHORT=" (${UPDATED_SHORT})"
            fi
        fi

        BUDGET_INFO=" | ${BUDGET_COLOR}💰 ${BUDGET_BAR} \$${FORMATTED_SPEND}/\$${FORMATTED_TOTAL}${UPDATED_SHORT}${RESET}"
    fi
elif command -v ccusage &> /dev/null; then
    # fallback: ccusage로 이번 달 비용 가져오기
    CURRENT_MONTH=$(date +"%Y-%m")

    MONTHLY_COST=$(ccusage monthly -j 2>/dev/null | jq -r --arg month "$CURRENT_MONTH" '.monthly[] | select(.month == $month) | .totalCost // 0')

    if [ -n "$MONTHLY_COST" ] && [ "$MONTHLY_COST" != "null" ] && [ "$MONTHLY_COST" != "0" ]; then
        FORMATTED_COST=$(printf "%.2f" "$MONTHLY_COST")

        if [ -f "$BUDGET_CONFIG" ]; then
            MONTHLY_BUDGET=$(jq -r '.monthly_budget // 0' "$BUDGET_CONFIG")

            if [ "$MONTHLY_BUDGET" != "0" ] && [ "$MONTHLY_BUDGET" != "null" ]; then
                PLAN_TYPE=$(jq -r '.plan_type // "api"' "$BUDGET_CONFIG")

                USAGE_PERCENT=$(awk "BEGIN {
                    used = $MONTHLY_COST;
                    budget = $MONTHLY_BUDGET;
                    usage = used / budget * 100;
                    printf \"%.0f\", usage
                }")

                if [ "$PLAN_TYPE" = "api" ]; then
                    if [ "$USAGE_PERCENT" -ge 100 ]; then
                        BUDGET_COLOR=$RED
                    elif [ "$USAGE_PERCENT" -ge 75 ]; then
                        BUDGET_COLOR=$YELLOW
                    else
                        BUDGET_COLOR=$GREEN
                    fi
                    BAR_PERCENT=$((100 - USAGE_PERCENT))
                    if [ $BAR_PERCENT -lt 0 ]; then BAR_PERCENT=0; fi
                else
                    if [ "$USAGE_PERCENT" -ge 100 ]; then
                        BUDGET_COLOR=$GREEN
                    elif [ "$USAGE_PERCENT" -ge 50 ]; then
                        BUDGET_COLOR=$YELLOW
                    else
                        BUDGET_COLOR=$RED
                    fi
                    BAR_PERCENT=$USAGE_PERCENT
                    if [ $BAR_PERCENT -gt 100 ]; then BAR_PERCENT=100; fi
                fi

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

# 모델 정보 포맷팅 - display_name 우선, fallback으로 model id
MODEL_LABEL="${MODEL_DISPLAY:-$MODEL_NAME}"
MODEL_INFO=""
if [ -n "$MODEL_LABEL" ] && [ "$MODEL_LABEL" != "null" ]; then
    if [[ "$MODEL_LABEL" != *"{"* ]]; then
        MODEL_INFO=" | 🏷 $MODEL_LABEL"
    fi
fi

# 세션 비용 정보 포맷팅
SESSION_COST_INFO=""
if [ -n "$SESSION_COST" ] && [ "$SESSION_COST" != "0.0000" ]; then
    SESSION_COST_INFO=" | 💵 \$${SESSION_COST}"
fi

# 출력
echo -e "${COLOR}Context: ${BAR} ${PERCENTAGE}%${COMPRESSED} | Remaining: ${REMAINING_K}K${RESET}${MODEL_INFO}${SESSION_COST_INFO}${BUDGET_INFO}"
