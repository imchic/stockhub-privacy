/// 앱 상수 모음
///
/// API 키는 --dart-define-from-file=env.json 빌드 플래그로 주입됩니다.
/// 실행 예시: flutter run --dart-define-from-file=env.json
/// env.json.example 파일을 복사해 env.json 을 만들고 실제 키를 입력하세요.
class AppConstants {
  // NewsAPI 설정 (더 이상 주 소스로 사용하지 않음)
  // ignore: do_not_use_environment
  static const String newsApiKey = String.fromEnvironment('NEWS_API_KEY');

  // Google Gemini API 키 (https://aistudio.google.com/app/apikey 에서 발급)
  // ignore: do_not_use_environment
  static const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
  // Financial Modeling Prep 경제 캘린더 API 키
  // ignore: do_not_use_environment
  static const String fmpApiKey = String.fromEnvironment('FMP_API_KEY');
  static const String newsApiBaseUrl = 'https://newsapi.org/v2';

  // 네이버 검색 API 설정 (https://developers.naver.com 에서 앱 등록 후 발급)
  // ignore: do_not_use_environment
  static const String naverClientId = String.fromEnvironment('NAVER_CLIENT_ID');
  // ignore: do_not_use_environment
  static const String naverClientSecret = String.fromEnvironment(
    'NAVER_CLIENT_SECRET',
  );
  static const String naverSearchBaseUrl =
      'https://openapi.naver.com/v1/search';

  // KRX Open API 키 (https://openapi.krx.co.kr 에서 발급)
  // ignore: do_not_use_environment
  static const String krxOpenApiKey = String.fromEnvironment(
    'KRX_OPEN_API_KEY',
  );

  // 앱 정보
  static const String appName = 'PinStock';
  static const String appVersion = '1.0.0';
  static const String supportEmail = 'pinnstock.dev@gmail.com';
  static const String supportPhone = '';
  static const String supportTeamName = 'PinStock 운영팀';
  static const String supportResponseHours = '평일 10:00 - 18:00 (KST)';
  static const String supportWebsiteUrl =
      'https://imchic.github.io/pinstock-privacy/docs/index.html';
  static const String supportContactPageUrl =
      'https://imchic.github.io/pinstock-privacy/docs/contact.html';
  static const String privacyPolicyUrl =
      'https://imchic.github.io/pinstock-privacy/docs/privacy_policy.html';

  // 시간 설정
  static const int apiRefreshIntervalMinutes = 10;
  static const int trendUpdateIntervalMinutes = 60;

  // 페이지네이션
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;

  // 임계값
  static const double surgingThreshold = 50.0; // 급상승 임계값 (%)
  static const double fallingThreshold = -30.0; // 급하락 임계값 (%)
  static const double highSentimentThreshold = 0.3;
  static const double lowSentimentThreshold = -0.3;

  // 캐시 설정
  static const int cacheExpiryMinutes = 60;
  static const int maxCacheSize = 500;

  // 알림
  static const int maxAlerts = 100;
  static const int alertRetentionDays = 30;

  // 지역
  static const List<String> defaultRegions = [
    'MidEast',
    'USA',
    'Asia',
    'Europe',
    'Africa',
  ];

  // 지역 코드 → 한글 표시명
  static const Map<String, String> regionLabels = {
    'MidEast': '중동',
    'USA': '미국',
    'Asia': '아시아',
    'Europe': '유럽',
    'Africa': '아프리카',
    'Korea': '한국',
    'China': '중국',
    'Japan': '일본',
    'Russia': '러시아',
    'LatinAmerica': '중남미',
  };

  static String regionToKorean(String region) => regionLabels[region] ?? region;

  // 카테고리
  static const List<String> categories = ['정치', '경제', '에너지', '군사', '기타'];

  // 언어
  static const String defaultLanguage = 'ko';
}
