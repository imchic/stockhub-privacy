# PinStock

> 실시간 시장 속보, 키워드 알림, 장 시작/마감 알림을 제공하는 Flutter 기반 주식 뉴스 앱

PinStock는 국내외 시장 뉴스와 핵심 지표를 한곳에서 빠르게 확인할 수 있도록 설계된 모바일 앱입니다. 투자 판단에 필요한 속보, 관심 키워드, 시장 흐름을 간결한 UI로 정리해 보여주며, 운영 정보와 정책 링크도 앱 내부 정보 화면과 동일한 구조로 제공합니다.

---

## 운영 정보

| 항목 | 내용 |
| --- | --- |
| 서비스명 | PinStock |
| 앱 버전 | 1.0.0 |
| 설명 | 실시간 시장 속보, 키워드 알림, 장 시작/마감 알림 제공 |
| 운영 주체 | PinStock 운영팀 |
| 문의 가능 시간 | 평일 10:00 - 18:00 (KST) |

## 핵심 기능

### 실시간 뉴스 피드
- 국내외 시장 뉴스를 빠르게 수집해 한 번에 확인할 수 있습니다.
- 기사별 언론사명과 발행 시각을 함께 표시합니다.
- 주기적 갱신을 통해 정적 목록이 아니라 최신 흐름을 유지합니다.

### 관심 키워드 관리
- 사용자가 직접 관심 종목이나 키워드를 등록할 수 있습니다.
- 여러 키워드를 쉼표로 한 번에 추가할 수 있습니다.
- 개인 맞춤형 뉴스 탐색 흐름에 맞게 관리됩니다.

### 알림 및 장 마감 정보
- 속보, 급등락, 관심 키워드 조건에 맞는 알림을 제공합니다.
- 필요한 경우에만 권한을 요청하도록 구성되어 있습니다.
- 장 시작, 장 마감 등 투자 리듬에 맞는 확인 포인트를 제공합니다.

### 설정 및 지원 정보
- 테마, 알림, 관심 키워드 등을 앱 안에서 조정할 수 있습니다.
- 문의처, 공식 안내 페이지, 개인정보처리방침 링크를 동일한 정보 구조로 제공합니다.

## 뉴스 및 데이터 출처 안내

- 네이버 검색 API를 통해 국내 뉴스 기사를 수집합니다.
- NewsAPI를 통해 글로벌 금융 뉴스를 보조적으로 수집합니다.
- Yahoo Finance와 KRX Open API를 통해 시장 데이터를 조회합니다.
- 앱은 최신 뉴스와 시장 데이터를 주기적으로 갱신합니다.

## 시작하기

### 1. 환경 변수 파일 준비

env.json.example을 복사해 env.json을 만들고 실제 API 키를 입력합니다.

필수 키:

- NEWS_API_KEY
- GEMINI_API_KEY
- FMP_API_KEY
- NAVER_CLIENT_ID
- NAVER_CLIENT_SECRET
- KRX_OPEN_API_KEY

예시 형식:

```json
{
	"NEWS_API_KEY": "your_news_api_key",
	"GEMINI_API_KEY": "your_gemini_api_key",
	"FMP_API_KEY": "your_fmp_api_key",
	"NAVER_CLIENT_ID": "your_naver_client_id",
	"NAVER_CLIENT_SECRET": "your_naver_client_secret",
	"KRX_OPEN_API_KEY": "your_krx_open_api_key"
}
```

참고:

- 경제 탭의 실시간 경제일정은 Financial Modeling Prep의 경제 캘린더 엔드포인트를 사용합니다.
- FMP 키가 있어도 현재 구독 플랜에서 해당 엔드포인트가 제한되면 앱은 정기 일정 카드로 자동 fallback 됩니다.

### 2. 의존성 설치

```bash
flutter pub get
```

### 3. 앱 실행

```bash
flutter run --dart-define-from-file=env.json
```

릴리스 빌드 예시:

```bash
flutter run --dart-define-from-file=env.json --release
```

## 기술 스택

- Flutter
- Riverpod
- Dio, http
- SharedPreferences
- flutter_local_notifications
- workmanager
- webview_flutter
- google_mobile_ads

## 프로젝트 구조

```text
lib/
	config/      앱 전역 설정, 상수, 테마
	data/        데이터 소스 및 저장 계층
	features/    화면 단위 기능 모듈
	models/      도메인 모델
	providers/   Riverpod 상태 관리
	services/    API, 분석, 캐시, 알림 서비스
	utils/       공용 유틸리티
	widgets/     재사용 UI 컴포넌트
```

## 정책 링크 및 문의

| 항목 | 링크 |
| --- | --- |
| 공식 안내 페이지 | https://imchic.github.io/PinStock-privacy/docs/index.html |
| 문의 페이지 | https://imchic.github.io/PinStock-privacy/docs/contact.html |
| 개인정보처리방침 | https://imchic.github.io/PinStock-privacy/docs/privacy_policy.html |
| 문의 이메일 | pinnstock.dev@gmail.com |

## GitHub Pages 배포

Google Play 정책 대응용 공식 안내 페이지와 문의 페이지는 docs 폴더 기준으로 GitHub Pages에 배포되도록 구성되어 있습니다.

배포 대상 파일:

- docs/index.html
- docs/contact.html
- docs/privacy_policy.html

자동 배포:

- .github/workflows/deploy-pages.yml 이 main 브랜치 푸시 시 docs 폴더를 GitHub Pages로 배포합니다.

최초 1회 설정:

1. GitHub 저장소의 Settings > Pages로 이동합니다.
2. Build and deployment의 Source를 GitHub Actions로 설정합니다.
3. main 브랜치에 푸시합니다.
4. 배포 후 공개 URL은 https://<github-user>.github.io/<repo>/ 형태로 생성됩니다.

Google Play Console 반영 권장값:

- 웹사이트 URL: 배포된 docs/index.html 또는 사이트 루트
- 뉴스 선언 연락처 URL: 배포된 docs/contact.html
- 개인정보처리방침 URL: 배포된 docs/privacy_policy.html

## 안내

이 저장소의 README는 앱 내부의 앱 정보 및 문의 화면과 같은 흐름으로 구성했습니다. 운영 정보, 데이터 출처, 정책 링크를 한눈에 확인할 수 있도록 정리했고, 개발자가 바로 실행할 수 있는 설정 절차와 배포 정보만 하단에 별도로 배치했습니다.
