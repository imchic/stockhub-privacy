# PinStock 계획 문서

## 상태
- 상태: 승인 대기
- 구현 금지: 이 문서를 사용한 코드 작성은 사용자 승인 전까지 시작하지 않는다.
- 작업 방식: Ralph 루프 기반으로 문서 검토와 메모 반영을 반복한다.

## 문서 목적
이 문서는 PinStock 코드베이스에서 새 기능이나 구조 변경을 시작하기 전에 검토하는 승인용 계획 문서다.

현재 대상 기능은 아직 확정되지 않았으므로, 이 문서는 바로 구현을 지시하는 문서가 아니라 다음 목적을 가진다.

1. 이 저장소의 실제 구조와 레이어를 기준으로 계획을 작성하는 기준을 고정한다.
2. 리뷰어가 에디터에서 직접 메모를 남길 수 있는 shared mutable state 문서 역할을 한다.
3. 이후 Claude나 다른 에이전트에게 전달할 때 구현 전에 무엇을 조사하고, 어떤 파일을 건드리며, 어떤 금지사항을 지켜야 하는지 명확히 한다.

## 최상위 규칙
1. 사용자 승인 전에는 코드를 쓰지 않는다.
2. 구현보다 먼저 코드리서치와 계획 품질을 고정한다.
3. 기존 레이어를 우회하는 새 함수나 임의의 직결 호출을 만들지 않는다.
4. Riverpod provider, service, repository, screen의 기존 책임 분리를 유지한다.
5. any, unknown에 해당하는 느슨한 타입 사용을 금지한다.
6. 새 변경은 실제 파일 경로와 코드 스니펫으로 설명되어야 한다.
7. 계획이 바뀌면 문서를 직접 수정하고, 완료 여부도 이 문서에서 추적한다.

## 현재 코드베이스 조사 요약

### 앱 셸
- 앱 진입점은 lib/main.dart 이다.
- 앱 초기화 시 온보딩 상태, 로컬 저장소, 알림 예약, 백그라운드 작업을 먼저 동기화한다.
- 루트 앱은 Riverpod ProviderScope 아래에서 실행된다.

### 레이어 구조
- lib/data/models: API 응답과 저장 데이터의 모델 계층
- lib/data/services: 외부 API, AI, KRX, 경제 일정 같은 데이터 취득 및 가공 서비스
- lib/data/repositories: 저장소 추상화 계층
- lib/providers: Riverpod 연결 지점과 비동기 데이터 조합 계층
- lib/features: 화면 단위 기능 모듈
- lib/services: 앱 전역 서비스, 알림, 백그라운드 작업, 온보딩 같은 앱 레벨 서비스

### 이미 확인한 실제 흐름
- 금융 화면은 lib/features/finance/views/finance_screen.dart 에서 렌더링된다.
- AI 시장 요약은 lib/providers/finance_providers.dart 의 aiMarketSummaryProvider 에서 뉴스, 지수, KRX 종목 목록을 조합해 만든다.
- 실제 요약 생성은 lib/data/services/ai_summary_service.dart 의 AiSummaryService.generateMarketSummary 에서 수행된다.
- 앱 시작 시 KRX 종목 목록은 lib/main.dart 에서 미리 로드된다.

### 현재 구조에서 중요한 설계 포인트
- provider는 여러 비동기 소스를 합성하는 조정 계층이다.
- service는 외부 API 호출과 텍스트 가공, 후보군 계산 같은 세부 로직을 담당한다.
- screen은 provider 결과를 표시하고, 주기적 invalidate 같은 UI 레벨 동작을 처리한다.
- 알림과 백그라운드 작업은 main 초기화 흐름과 앱 서비스 레이어에 묶여 있으므로 화면에서 직접 우회 제어하면 안 된다.

## 이 저장소에서 자주 건드릴 가능성이 높은 파일

### 앱 전체 흐름
- lib/main.dart
- lib/providers/index.dart

### 금융 탭과 AI 요약
- lib/features/finance/views/finance_screen.dart
- lib/providers/finance_providers.dart
- lib/data/services/ai_summary_service.dart
- lib/data/services/market_data_service.dart
- lib/data/services/krx_stock_service.dart

### 뉴스와 피드
- lib/providers/news_providers.dart
- lib/features/feed/views/feed_screen.dart
- lib/features/feed/views/news_detail_screen.dart
- lib/features/feed/views/news_content_detail_screen.dart

### 설정과 사용자 상태
- lib/providers/user_preference_providers.dart
- lib/features/settings/views/settings_screen.dart
- lib/data/services/local_storage_service.dart

### 알림과 백그라운드 작업
- lib/services/notification_service.dart
- lib/services/background_task_service.dart
- lib/providers/alerts_providers.dart

## 리서치 체크리스트
새 기능을 계획하기 전에 아래를 먼저 확인한다.

1. 이미 같은 역할의 provider, service, repository가 있는가.
2. 화면이 직접 데이터를 가져오는지, provider를 통해 받는지.
3. 기존 모델과 응답 구조를 재사용할 수 있는가.
4. 캐시, 타이머, invalidate, keepAlive 정책을 건드려야 하는가.
5. 알림, 온보딩, 로컬 저장 상태와 충돌하는 흐름이 있는가.
6. 같은 정보를 이미 다른 탭이나 화면이 보여주고 있지 않은가.
7. 새 기능이 UI 전용인지, 데이터 계층 변경까지 필요한지.

## 상세 계획 템플릿
아래 섹션은 이후 특정 기능명으로 채워 넣는 본문 템플릿이다.

---

## 작업명
- 예시: ETF 리밸런싱, AI 요약 정확도 개선, 경제 탭 개편

## 목표
- 사용자 관점에서 무엇이 달라지는지 한 문단으로 적는다.
- 성공 조건을 측정 가능한 형태로 적는다.

## 범위
- 포함: 이번 작업에서 반드시 끝내야 하는 것
- 제외: 이번 작업에서 하지 않을 것

## 접근 방식
이 섹션에는 실제 코드베이스에 맞춘 구현 경로를 쓴다.

예시 작성 형식:

1. 화면 진입점은 어느 screen인지 명시한다.
2. 상태 조합은 어느 provider에서 할지 명시한다.
3. 외부 API 호출이나 계산은 어느 service로 둘지 명시한다.
4. 기존 모델 확장이 필요한지 적는다.
5. 캐시, 타이머, invalidate 전략을 적는다.

예시 문장:

이 기능은 화면에서 직접 네트워크를 호출하지 않고, 먼저 provider에서 기존 뉴스 데이터와 사용자 설정을 조합한 뒤, 세부 계산은 service 계층으로 내린다. UI는 provider의 AsyncValue만 소비하게 유지한다.

## 실제 변경 파일 경로
- 수정 예정 파일:
  - lib/features/.../...
  - lib/providers/..._providers.dart
  - lib/data/services/...
  - lib/data/models/...
- 신규 파일:
  - 필요 시만 추가

## 코드 스니펫 초안
이 섹션에는 실제 변경 방향을 검토할 수 있을 정도의 작은 코드 블록만 넣는다.
아직 구현 단계가 아니므로, 정확한 방향 확인용 스니펫만 작성한다.

### 스니펫 A: provider 조합 위치 예시
```dart
final aiMarketSummaryProvider = FutureProvider.autoDispose<String>((ref) async {
  final allNews = await ref.watch(allFinanceNewsProvider.future);
  final indices = ref.read(marketIndicesProvider).valueOrNull ?? [];
  final krxStocks = await ref.read(krxStocksProvider.future);

  return ref.read(aiSummaryServiceProvider).generateMarketSummary(
    indices: indices,
    newsItems: allNews,
    kospiStocks: krxStocks.kospi,
    kosdaqStocks: krxStocks.kosdaq,
  );
});
```

의도:
- provider에서 소스 결합을 담당한다.
- AI 프롬프트나 후보군 계산 세부사항은 service로 유지한다.

### 스니펫 B: service 책임 위치 예시
```dart
class AiSummaryService {
  Future<String> generateMarketSummary({
    required List<MarketIndex> indices,
    required List<FinanceNews> newsItems,
    List<String> kospiStocks = const [],
    List<String> kosdaqStocks = const [],
  }) async {
    // 프롬프트 구성, 외부 API 호출, 응답 정규화는 여기서 처리
  }
}
```

의도:
- 화면이나 provider에 문자열 가공 로직이 새지 않게 한다.
- 외부 모델 응답 검증과 fallback 로직을 service 안에 고정한다.

### 스니펫 C: 화면 소비 예시
```dart
Widget _buildAiSummaryCard() {
  final summaryAsync = ref.watch(aiMarketSummaryProvider);

  return summaryAsync.when(
    data: _buildSummaryBody,
    loading: _buildSummarySkeleton,
    error: (error, stack) => _buildSummaryError(error),
  );
}
```

의도:
- 화면은 상태 표현만 담당한다.
- 구현 세부사항은 provider와 service에 남긴다.

## 트레이드오프
각 작업에는 최소 2개 이상의 선택지와 기각 이유를 적는다.

예시:

### 선택지 1: 화면에서 직접 데이터 조합
- 장점: 파일 수가 적고 빠르게 보인다.
- 단점: UI와 비즈니스 로직이 섞여 테스트와 재사용이 어려워진다.
- 결론: 기각.

### 선택지 2: provider에서 조합, service에서 세부 계산
- 장점: 현재 코드베이스 구조와 일치하고 확장성이 높다.
- 단점: 초기에 파일을 더 많이 읽어야 한다.
- 결론: 채택.

### 선택지 3: 새 repository 추가
- 장점: 저장소 추상화가 더 선명해질 수 있다.
- 단점: 단순 계산 기능이면 레이어가 과도하게 늘어난다.
- 결론: 데이터 영속성이나 다중 데이터 소스 통합이 필요할 때만 사용.

## 위험 요소
- 기존 provider invalidate 주기를 깨뜨릴 위험
- 사용자 설정이나 알림 토글과 충돌할 위험
- 기존 화면에서 같은 데이터를 중복 호출할 위험
- AI 응답 포맷 변경으로 파서가 깨질 위험

## 검증 계획
아직 구현은 하지 않지만, 구현 단계에서 무엇을 검증할지는 미리 적는다.

1. flutter analyze
2. 관련 화면 수동 테스트
3. provider 로딩, 에러, 빈 데이터 상태 점검
4. 기존 알림, 설정, 캐시 흐름 회귀 확인

## 주석 메모 구역
리뷰어는 아래 형식으로 직접 메모를 추가한다.

### 메모 규칙
- 가정 수정
- 접근 방식 거부
- 제약조건 추가
- 도메인 지식 전달
- 구현 금지 범위 지정

### 메모 예시
- 메모: 설정 페이지가 아니라 금융 탭 내부 카드로만 노출할 것
- 메모: 새 패키지 추가 금지
- 메모: 관리자 기능은 사용자 앱에 두지 말 것
- 메모: 아직 구현하지 마

## Ralph 루프 운영 방식
1. 작업 지시서와 이 문서를 읽는다.
2. 필요한 파일을 깊이 읽고 research.md 또는 조사 섹션을 갱신한다.
3. plan.md를 업데이트한다.
4. 사용자가 문서에 메모를 남긴다.
5. 메모를 반영해 plan.md를 다시 갱신한다.
6. 승인 전까지 구현하지 않는다.
7. 승인 후에만 기계적으로 구현하고, 완료 시 체크박스나 상태를 문서에 기록한다.

## 승인 조건
아래가 모두 충족되기 전까지는 구현 단계로 넘어가지 않는다.

1. 작업명이 확정되었다.
2. 수정 파일 경로가 확정되었다.
3. 트레이드오프가 문서화되었다.
4. 리뷰어 메모가 반영되었다.
5. 사용자로부터 구현 승인 문구를 받았다.

## 다음 액션
- 사용자가 구체적인 작업명을 정한다.
- 이 문서의 작업명, 목표, 범위, 변경 파일 경로를 실제 기능 기준으로 채운다.
- 사용자가 메모를 남긴 뒤, 그 메모만 반영해 문서를 갱신한다.
- 승인 전까지 코드는 수정하지 않는다.