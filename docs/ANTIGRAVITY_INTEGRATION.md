# Google Antigravity 연동 가이드 (shift_master)

이 가이드는 `Codex`와 `Google Antigravity`를 같은 저장소로 안정적으로 연동하기 위한 최소 절차입니다.

## 1) 연동 규칙 (기본 원칙)

1. 동일 `shift_master` Git 저장소를 사용한다.
2. 브랜치 정책
   - Codex 적용용: `codex/<날짜>-<이슈>`
   - Antigravity 점검 후 반영용: `ui-check/<날짜>-<이슈>` 또는 동일 브랜치에서 재사용
3. 커밋 메시지 규칙
   - `feat: ...`
   - `fix: ...`
   - `chore: ...`
4. UI 결과 캡처/이슈는 반드시 커밋 메시지 본문/댓글에 첨부한다.

## 2) 1일 작업 절차

### 2.1 Codex 작업 시작

```bash
cd C:/Users/seung/Shift/shift_master
git checkout -b codex/TODO-001
git status
```

1. 코드 수정 후 저장
2. 필요하면 로컬 빌드 체크(원하면 생략 가능)
3. 커밋

```bash
git add .
git commit -m "feat: shift_master update"
git push -u origin HEAD
```

### 2.2 Antigravity 작업 반영

1. Antigravity에서 같은 브랜치(`codex/TODO-001`)를 `Pull` 해서 동일 변경사항 동기화
2. UI/동작 확인 및 이슈 메모
3. 이슈 수정이 필요하면:
   - Antigravity 화면에서 바로 수정(또는 Codex에 반영할 패치 요청)
   - 정합성만 맞으면 `git commit` 후 같은 브랜치로 Push

### 2.3 마무리 병합

1. 변경사항 확인 후 PR/병합
2. 병합 전에 아래 항목 재확인
   - 저장 데이터 로딩/파싱 로직 (shared_preferences 키 충돌 여부)
   - 웹에서 기본 동작
   - 데스크톱 이미지 열기 관련 예외 처리

## 3) 웹 실행(현재 팀 표준)

```bash
./scripts/run_shift_web.ps1 -Port 8080 -HostName 127.0.0.1 -Open
```

로그는 다음 경로에 남습니다.
- `flutter_webserver_stdout.log`
- `flutter_webserver_stderr.log`

## 4) 점검 체크리스트

- `main.dart` 기본 동작: 팀명 편집/시프트 등록/삭제
- `settings` 저장/복원
- 화면 크기 변경 시 레이아웃 깨짐 여부
- 기존 데이터 포맷 호환성(잘못된 JSON 값 안전 처리)

## 5) 문제 발생시 초기 대응

1. 포트 충돌: 8080 사용 프로세스 종료 후 재실행
2. 캐시/상태 꼬임: `build` 폴더/브라우저 캐시 초기화
3. 분석/실행 관련 툴 충돌: Flutter SDK 경로 권한, 네트워크, 캐시 설정 점검

