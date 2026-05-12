import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/constants.dart';
import '../../utils/text_sanitizer.dart';
import '../models/index.dart';
import 'api_exceptions.dart';
import 'api_rate_limiter.dart';

/// 금융 뉴스 API 서비스 (코스피, 나스닥 등)
class FinanceApiService {
  static const String _baseUrl = 'https://newsapi.org/v2';
  static const String _apiKey = AppConstants.newsApiKey;
  static bool _authLocked = false;
  static String? _authLockReason;

  // NewsAPI source.name → 한글 언론사명
  static const _newsApiSourceToKo = {
    'Reuters': '로이터',
    'Bloomberg': '블룸버그',
    'CNBC': 'CNBC',
    'The Wall Street Journal': '월스트리트저널',
    'Financial Times': '파이낸셜타임스',
    'MarketWatch': '마켓워치',
    'Investor\'s Business Daily': 'IBD',
    'The Motley Fool': '모틀리풀',
    'Seeking Alpha': '시킹알파',
    'Barron\'s': '배런스',
    'Forbes': '포브스',
    'Fortune': '포춘',
    'Business Insider': '비즈니스인사이더',
    'CNN': 'CNN',
    'BBC News': 'BBC',
    'The New York Times': '뉴욕타임스',
    'The Washington Post': '워싱턴포스트',
    'Associated Press': 'AP통신',
    'Nikkei': '니케이',
    'South China Morning Post': 'SCMP',
    'Yonhap News Agency': '연합뉴스',
    'Korea Herald': '코리아헤럴드',
    'Korea Times': '코리아타임스',
  };

  final http.Client _client;
  final ApiRateLimiter _rateLimiter = ApiRateLimiter();

  /// 전세계 주요 금융 종목 정보
  static const Map<String, StockTicker> majorTickers = {
    'kospi': StockTicker(
      symbol: 'KOSPI',
      name: '코스피',
      market: 'KRX',
      companyName: 'Korea Composite Stock Price Index',
      sector: '지수',
      industry: '종합지수',
    ),
    'kosdaq': StockTicker(
      symbol: 'KOSDAQ',
      name: '코스닥',
      market: 'KRX',
      companyName: 'Korea Securities Dealers Automated Quotations',
      sector: '지수',
      industry: '종합지수',
    ),
    'nasdaq': StockTicker(
      symbol: 'NASDAQ',
      name: '나스닥',
      market: 'NASDAQ',
      companyName: 'NASDAQ Composite',
      sector: '지수',
      industry: '종합지수',
    ),
    'sp500': StockTicker(
      symbol: 'SPY',
      name: 'S&P 500',
      market: 'NYSE',
      companyName: 'Standard & Poors 500',
      sector: '지수',
      industry: '종합지수',
    ),
    'dow': StockTicker(
      symbol: 'DJI',
      name: '다우 존스',
      market: 'NYSE',
      companyName: 'Dow Jones Industrial Average',
      sector: '지수',
      industry: '종합지수',
    ),
  };

  /// 섹터별 핵심 종목
  static const Map<String, List<String>> sectorStocks = {
    '기술': ['apple', 'microsoft', 'google', 'nvidia', 'tesla', '삼성', 'sk'],
    '금융': ['jp morgan', 'bank of america', '우리은행', '신한은행'],
    '에너지': ['exxon', 'oil', 'energy', '석유'],
    '의약': ['pfizer', 'moderna', 'merck', '제약', '의료'],
    '자동차': ['tesla', 'gm', 'ford', '현대차', '기아'],
  };

  FinanceApiService({http.Client? client}) : _client = client ?? http.Client();

  static bool get hasConfiguredApiKey => _apiKey.trim().isNotEmpty;

  void _ensureConfigured() {
    if (!hasConfiguredApiKey) {
      throw const ApiConfigurationException(
        'NewsAPI 키가 비어 있습니다. env.json의 NEWS_API_KEY 값을 확인하세요.',
      );
    }
  }

  void _ensureAuthAvailable() {
    if (_authLocked) {
      throw ApiAuthException(
        _authLockReason ?? 'NewsAPI 인증 실패가 감지되어 이후 요청을 차단합니다.',
      );
    }
  }

  void _lockAuthentication(String responseBody) {
    _authLocked = true;
    _authLockReason =
        'NewsAPI 인증 실패가 감지되었습니다. env.json의 NEWS_API_KEY 값을 확인하세요. 응답: $responseBody';
  }

  /// 코스피 뉴스 검색
  Future<List<FinanceNews>> getKospiNews({
    int pageSize = 20,
    String sortBy = 'publishedAt',
  }) async {
    return _searchFinanceNews(
      query: '코스피 OR KOSPI OR 주가 OR 한국주식',
      category: 'market',
      pageSize: pageSize,
      sortBy: sortBy,
    );
  }

  /// 나스닥 뉴스 검색
  Future<List<FinanceNews>> getNasdaqNews({
    int pageSize = 20,
    String sortBy = 'publishedAt',
  }) async {
    return _searchFinanceNews(
      query: '나스닥 OR NASDAQ OR 미국주식 OR 기술주',
      category: 'market',
      pageSize: pageSize,
      sortBy: sortBy,
    );
  }

  /// 특정 섹터 뉴스 검색
  Future<List<FinanceNews>> getSectorNews(
    String sector, {
    int pageSize = 20,
    String sortBy = 'publishedAt',
  }) async {
    final stocks = sectorStocks[sector] ?? [];
    final query = stocks.join(' OR ');

    return _searchFinanceNews(
      query: query,
      category: sector,
      pageSize: pageSize,
      sortBy: sortBy,
    );
  }

  /// 특정 종목 뉴스 검색
  Future<List<FinanceNews>> getStockNews(
    String ticker, {
    int pageSize = 20,
    String sortBy = 'publishedAt',
  }) async {
    return _searchFinanceNews(
      query: ticker,
      pageSize: pageSize,
      sortBy: sortBy,
    );
  }

  /// 경제 뉴스 검색 (FED, 인플레이션 등)
  Future<List<FinanceNews>> getEconomicNews({
    int pageSize = 20,
    String sortBy = 'publishedAt',
  }) async {
    return _searchFinanceNews(
      query: 'FED OR 인플레이션 OR 금리 OR 경제 OR 재정',
      category: 'economic',
      pageSize: pageSize,
      sortBy: sortBy,
    );
  }

  /// 통합 금융 뉴스 검색 — NewsAPI 1회 호출
  /// (코스피/나스닥/경제 키워드를 하나의 쿼리로 합침)
  Future<List<FinanceNews>> getFinanceNews({
    int pageSize = 30,
    String sortBy = 'publishedAt',
  }) async {
    return _searchFinanceNews(
      query:
          '코스피 OR KOSPI OR 코스닥 OR NASDAQ OR 나스닥 OR 증시 OR 주가 OR 금리 OR 경제 OR FED',
      pageSize: pageSize,
      sortBy: sortBy,
    );
  }

  /// 내부: 금융 뉴스 공통 검색 로직
  Future<List<FinanceNews>> _searchFinanceNews({
    required String query,
    String category = 'general',
    int pageSize = 20,
    String sortBy = 'publishedAt',
  }) async {
    _ensureConfigured();
    _ensureAuthAvailable();

    // Rate Limiter 체크
    if (!_rateLimiter.canMakeRequest()) {
      debugPrint('⏳ [NewsAPI] Rate Limiter에 의해 요청 차단됨');
      throw Exception('Rate Limit: API 요청 제한으로 인해 잠시 후 다시 시도해주세요');
    }

    try {
      final uri = Uri.parse('$_baseUrl/everything').replace(
        queryParameters: {
          'q': query,
          'sortBy': sortBy,
          'pageSize': pageSize.toString(),
          'apiKey': _apiKey,
          'language': 'ko',
        },
      );

      debugPrint(
        '🔗 [NewsAPI] 요청: category=$category, query="$query", pageSize=$pageSize',
      );
      final response = await _client.get(uri);
      debugPrint(
        '📥 [NewsAPI] 응답: status=${response.statusCode}, bodyLen=${response.body.length}',
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final totalResults = json['totalResults'] ?? 0;
        final articles = (json['articles'] as List?)
            ?.cast<Map<String, dynamic>>();

        if (articles == null || articles.isEmpty) {
          debugPrint(
            '⚠️ [NewsAPI] 기사 없음: category=$category (totalResults=$totalResults)',
          );
          return [];
        }

        final parsed = articles
            .map((article) => _parseFinanceNews(article, query, category))
            .toList();
        debugPrint(
          '✅ [NewsAPI] 파싱 완료: category=$category → ${parsed.length}건 (서버 총 $totalResults건)',
        );
        // 첫 3건 제목 미리보기
        for (var i = 0; i < parsed.length && i < 3; i++) {
          debugPrint(
            '   [$i] ${parsed[i].source} | ${parsed[i].title.substring(0, parsed[i].title.length.clamp(0, 50))}...',
          );
        }

        // 성공 기록
        _rateLimiter.recordRequest();
        return parsed;
      } else if (response.statusCode == 429) {
        // Rate Limit 전용 처리
        final json = jsonDecode(response.body);
        final message = json['message'] ?? 'Rate limit 초과';
        debugPrint('⏳ [NewsAPI] Rate Limit: ${response.statusCode} — $message');
        _rateLimiter.recordFailure(); // 실패 기록
        throw Exception('Rate Limit: $message');
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint(
          '⛔ [NewsAPI] 인증 실패: ${response.statusCode} — ${response.body.substring(0, response.body.length.clamp(0, 200))}',
        );
        _lockAuthentication(response.body);
        throw ApiAuthException(_authLockReason!);
      } else {
        debugPrint(
          '❌ [NewsAPI] HTTP 오류: ${response.statusCode} — ${response.body.substring(0, response.body.length.clamp(0, 200))}',
        );
        _rateLimiter.recordFailure(); // 실패 기록
        throw Exception('뉴스 검색 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ [NewsAPI] 예외: $e (category=$category)');
      if (!e.toString().contains('Rate Limit')) {
        _rateLimiter.recordFailure(); // Rate limit이 아닌 다른 실패도 기록
      }
      throw Exception('API 호출 오류: $e');
    }
  }

  /// NewsAPI 기사를 FinanceNews 모델로 변환
  FinanceNews _parseFinanceNews(
    Map<String, dynamic> article,
    String query,
    String category,
  ) {
    final title = sanitizeHtmlText(article['title'] as String? ?? '');
    final description = sanitizeHtmlText(
      article['description'] as String? ?? '',
    );
    final url = article['url'] as String?;
    final image = article['urlToImage'] as String?;
    final rawSource = (article['source'] as Map?)?['name'] as String? ?? '';
    final source = rawSource.isNotEmpty
        ? (_newsApiSourceToKo[rawSource] ?? rawSource)
        : '뉴스';
    final publishedAt =
        DateTime.tryParse(article['publishedAt'] as String? ?? '') ??
        DateTime.now();

    final keywords = _extractKeywords(title, description, query);
    final tickers = _extractTickers(title, description);
    final sectors = _extractSectors(tickers);
    final sentiment = _calculateSentiment(title, description);

    return FinanceNews(
      id:
          url?.hashCode.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      description: description,
      source: source,
      publishedAt: publishedAt,
      createdAt: DateTime.now(),
      imageUrl: image,
      url: url,
      keywords: keywords,
      tickers: tickers,
      sectors: sectors,
      sentimentScore: sentiment,
      importanceLevel: _calculateImportance(title, keywords),
      category: category,
    );
  }

  /// 키워드 추출
  List<String> _extractKeywords(
    String title,
    String description,
    String query,
  ) {
    final text = '$title $description'.toLowerCase();
    final keywords = <String>{};

    // 명시적인 금융 키워드
    final financialKeywords = {
      '상승': '상승',
      '하락': '하락',
      '급등': '급등',
      '폭락': '폭락',
      '수익': '수익',
      '손실': '손실',
      '회사채': '회사채',
      '주가지수': '지수',
      '포트폴리오': '포트폴리오',
      '배당': '배당',
      '실적': '실적',
      '분석': '분석',
      '리포트': '리포트',
      '투자': '투자',
      '거래': '거래',
      '공모': '공모',
      '상장': '상장',
    };

    for (final kw in financialKeywords.keys) {
      if (text.contains(kw)) {
        keywords.add(financialKeywords[kw]!);
      }
    }

    keywords.add(query);
    return keywords.toList();
  }

  /// 주식 종목 코드/이름 추출
  List<String> _extractTickers(String title, String description) {
    final text = '$title $description'.toUpperCase();
    final tickers = <String>{};

    // 주요 시장 종목 매칭
    for (final ticker in majorTickers.values) {
      if (text.contains(ticker.symbol) ||
          text.contains(ticker.name.toUpperCase())) {
        tickers.add(ticker.symbol);
      }
    }

    // 섹터별 주요 종목
    for (final stocks in sectorStocks.values) {
      for (final stock in stocks) {
        if (text.contains(stock.toUpperCase())) {
          tickers.add(stock.toUpperCase());
        }
      }
    }

    return tickers.toList();
  }

  /// 섹터 추출
  List<String> _extractSectors(List<String> tickers) {
    final sectors = <String>{};

    for (final sector in sectorStocks.keys) {
      final stocks = sectorStocks[sector]!;
      for (final ticker in tickers) {
        if (stocks.contains(ticker.toLowerCase())) {
          sectors.add(sector);
        }
      }
    }

    return sectors.toList();
  }

  /// 감정 분석 (간단한 키워드 기반)
  double _calculateSentiment(String title, String description) {
    final text = '$title $description'.toLowerCase();

    final positiveWords = {'상승', '급등', '강세', '회복', '개선', '성장', '호조'};
    final negativeWords = {'하락', '폭락', '약세', '악화', '악전', '부진', '하락장'};

    int positive = 0;
    int negative = 0;

    for (final word in positiveWords) {
      if (text.contains(word)) positive++;
    }
    for (final word in negativeWords) {
      if (text.contains(word)) negative++;
    }

    if (positive + negative == 0) return 0.0;
    return (positive - negative) / (positive + negative);
  }

  /// 중요도 계산
  int _calculateImportance(String title, List<String> keywords) {
    int score = 3; // 기본값

    if (title.length > 60) score++;
    if (keywords.isNotEmpty) score++;

    final highPriorityKeywords = {'상승', '하락', '폭락', '급등', '실적', '배당'};
    for (final kw in keywords) {
      if (highPriorityKeywords.contains(kw)) {
        score++;
        break;
      }
    }

    return score.clamp(1, 5);
  }

  /// Rate Limiter 상태 확인
  Map<String, dynamic> getRateLimiterStatus() {
    return _rateLimiter.getStatus();
  }
}
