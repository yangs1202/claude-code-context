# Claude Code Context Statusline

Claude Code 터미널 상태 표시줄에 컨텍스트 윈도우 사용량을 시각적으로 표시하는 스크립트입니다.

[English](README.md)

## 특징

- 📊 **진행률 바**: 컨텍스트 사용량을 시각적으로 표시
- 🎨 **색상 코드**: 사용량에 따라 초록 → 노랑 → 빨강
- 📈 **실시간 업데이트**: 현재 사용률과 남은 토큰 수 표시
- 🔄 **자동 리셋**: `/clear` 명령 후 0%로 초기화
- 💾 **압축 알림**: 100% 초과 시 "(Compressed)" 표시

## 미리보기

![Claude Code Context Statusline](sample.png)

**색상 표시:**
- 🟢 초록색: 60% 미만
- 🟡 노란색: 60-85%
- 🔴 빨간색: 85% 이상

## 빠른 설치

### 한 줄 설치 (권장)

**curl 사용:**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yangs1202/claude-code-context/main/install.sh)
```

**wget 사용:**
```bash
bash <(wget -qO- https://raw.githubusercontent.com/yangs1202/claude-code-context/main/install.sh)
```

### 수동 설치

```bash
# 저장소 클론
git clone git@github.com:yangs1202/claude-code-context.git
cd claude-code-context

# 설치 스크립트 실행
./install.sh
```

## 요구사항

- Claude Code v2.0+
- `jq` (JSON 처리기)
- `awk` (텍스트 처리기)

**의존성 설치:**

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# RHEL/CentOS
sudo yum install jq
```

## 설치 내용

설치 스크립트는 자동으로:
1. ✅ 의존성 확인 (jq, awk)
2. ✅ `statusline.sh`를 `~/.claude/`에 설치
3. ✅ 플랜 설정으로 `budget-config.json` 생성
4. ✅ `~/.claude/settings.json` 업데이트
5. ✅ 기존 설정 백업 생성
6. ✅ 실행 권한 설정

## 수동 설정

수동으로 설치하려면:

1. `statusline.sh`를 `~/.claude/`에 복사:
   ```bash
   cp statusline.sh ~/.claude/
   chmod +x ~/.claude/statusline.sh
   ```

2. `~/.claude/budget-config.json` 생성 (버짓 추적용):
   ```json
   {
     "plan_type": "api",
     "monthly_budget": 100
   }
   ```

   **plan_type 옵션:**
   - `"api"` - API Billing (남은 버짓 표시)
   - `"pro"` - Claude Pro ($20/월)
   - `"max_5x"` - Claude Max 5x ($100/월)
   - `"max_20x"` - Claude Max 20x ($200/월)

3. `~/.claude/settings.json`에 추가:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.claude/statusline.sh"
     }
   }
   ```

4. Claude Code 재시작

## 제거 방법

### 빠른 제거

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yangs1202/claude-code-context/main/uninstall.sh)
```

### 수동 제거

```bash
# 저장소를 클론했다면
cd claude-code-context
./uninstall.sh
```

또는 수동으로 제거:
```bash
rm ~/.claude/statusline.sh
rm /tmp/claude-statusline-state
# ~/.claude/settings.json에서 "statusLine" 제거
```

## 작동 원리

스크립트는:
1. Claude Code로부터 stdin을 통해 JSON 데이터 수신
2. `session_id`를 추적하여 `/clear` 명령 감지
3. 현재 토큰과 baseline을 비교하여 컨텍스트 사용량 계산
4. 색상이 적용된 진행률 바와 함께 퍼센트 및 남은 토큰 표시

`/clear`를 실행하면 세션 ID가 변경되고 카운터가 0%로 리셋됩니다.

## 문제 해결

**상태바가 표시되지 않나요?**
- 설치 후 Claude Code를 재시작했는지 확인하세요
- `~/.claude/statusline.sh` 파일이 존재하고 실행 가능한지 확인하세요
- `~/.claude/settings.json`에 `statusLine` 설정이 있는지 확인하세요

**`/clear` 후 상태바가 업데이트되지 않나요?**
- 스크립트가 세션 변경을 자동으로 추적합니다
- Claude Code를 재시작해보세요

**의존성이 없나요?**
- `jq` 설치: 위의 [요구사항](#요구사항) 섹션을 참고하세요

**색상이 표시되지 않나요?**
- 터미널이 ANSI 색상을 지원하는지 확인하세요
- 다른 터미널 에뮬레이터를 시도해보세요

## 기여하기

기여는 언제나 환영합니다! Pull Request를 자유롭게 제출해주세요.

## 라이선스

MIT License - 자세한 내용은 [LICENSE](LICENSE) 파일을 참고하세요

## 크레딧

Claude Code 커뮤니티가 컨텍스트 사용량을 더 효과적으로 모니터링할 수 있도록 제작되었습니다.
