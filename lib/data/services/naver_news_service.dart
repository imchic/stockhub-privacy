import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/constants.dart';
import '../models/index.dart';
import 'api_exceptions.dart';
import 'press_cache_service.dart';

/// 네이버 뉴스 검색 API 서비스
/// - 공식 API: https://developers.naver.com/docs/serviceapi/search/news/v1/news.md
/// - 무료: 25,000 호출/일
/// - 한국어 뉴스 직접 수신 (번역 불필요)
class NaverNewsService {
  static const String _baseUrl = AppConstants.naverSearchBaseUrl;
  static const String _clientId = AppConstants.naverClientId;
  static const String _clientSecret = AppConstants.naverClientSecret;
  static const Duration _minimumRequestInterval = Duration(milliseconds: 1100);
  static const Duration _rateLimitCooldown = Duration(seconds: 30);

  static Future<void> _requestQueue = Future<void>.value();
  static DateTime? _lastRequestAt;
  static DateTime? _cooldownUntil;
  static bool _authLocked = false;
  static String? _authLockReason;

  final http.Client _client;
  final PressCacheService _pressCache;

  NaverNewsService({http.Client? client, PressCacheService? pressCache})
    : _client = client ?? http.Client(),
      _pressCache = pressCache ?? PressCacheService();

  static bool get _verboseLogging => kDebugMode;

  static void _logVerbose(String message) {
    if (_verboseLogging) {
      debugPrint(message);
    }
  }

  static bool get hasConfiguredCredentials =>
      _clientId.trim().isNotEmpty && _clientSecret.trim().isNotEmpty;

  void _ensureConfigured() {
    if (!hasConfiguredCredentials) {
      throw const ApiConfigurationException(
        'Naver API 자격증명이 비어 있습니다. env.json의 NAVER_CLIENT_ID, NAVER_CLIENT_SECRET 값을 확인하세요.',
      );
    }
  }

  void _ensureAuthAvailable() {
    if (_authLocked) {
      throw ApiAuthException(
        _authLockReason ?? 'Naver API 인증 실패가 감지되어 이후 요청을 차단합니다.',
      );
    }
  }

  void _lockAuthentication(String responseBody) {
    _authLocked = true;
    _authLockReason =
        'Naver API 인증 실패가 감지되었습니다. env.json의 NAVER_CLIENT_ID, NAVER_CLIENT_SECRET 값을 확인하세요. 응답: $responseBody';
  }

  Future<T> _enqueueRequest<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _requestQueue = _requestQueue.catchError((_) {}).then((_) async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _waitForRateLimitWindow() async {
    final now = DateTime.now();
    final cooldownUntil = _cooldownUntil;
    if (cooldownUntil != null && cooldownUntil.isAfter(now)) {
      final wait = cooldownUntil.difference(now);
      _logVerbose('⏳ Naver API 쿨다운 대기: ${wait.inSeconds}s');
      throw Exception('네이버 API 쿨다운 중');
    }

    final lastRequestAt = _lastRequestAt;
    if (lastRequestAt != null) {
      final elapsed = now.difference(lastRequestAt);
      if (elapsed < _minimumRequestInterval) {
        await Future.delayed(_minimumRequestInterval - elapsed);
      }
    }

    _lastRequestAt = DateTime.now();
  }

  /// 뉴스 검색
  /// [query]    - 검색어
  /// [display]  - 결과 수 (최대 100)
  /// [start]    - 시작 위치 (1~1000, 페이지네이션)
  /// [sortBy]   - 'date'(최신순) | 'sim'(관련도순)
  Future<List<News>> searchNews({
    required String query,
    int display = 100,
    int start = 1,
    String sortBy = 'date',
  }) async {
    return _enqueueRequest(() async {
      try {
        _ensureConfigured();
        _ensureAuthAvailable();
        await _waitForRateLimitWindow();

        final uri = Uri.parse('$_baseUrl/news.json').replace(
          queryParameters: {
            'query': query,
            'display': display.toString(),
            'start': start.toString(),
            'sort': sortBy,
          },
        );

        _logVerbose('🔗 Naver API 요청: $query');
        final response = await _client.get(
          uri,
          headers: {
            'X-Naver-Client-Id': _clientId,
            'X-Naver-Client-Secret': _clientSecret,
          },
        );

        if (response.statusCode == 200) {
          _cooldownUntil = null;
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final items = (json['items'] as List?)?.cast<Map<String, dynamic>>();

          if (items == null || items.isEmpty) {
            _logVerbose('⚠️ 결과 없음: $query');
            return <News>[];
          }

          _logVerbose('✅ ${items.length}개 기사 수신: $query');
          return items.map((item) => _parseNews(item)).toList();
        }

        if (response.statusCode == 401 || response.statusCode == 403) {
          _lockAuthentication(response.body);
          debugPrint(
            '⛔ Naver API 인증 실패: ${response.statusCode} — ${response.body}',
          );
          throw ApiAuthException(_authLockReason!);
        }

        if (response.statusCode == 429) {
          _cooldownUntil = DateTime.now().add(_rateLimitCooldown);
        }

        debugPrint(
          '⚠️ Naver API 에러: ${response.statusCode} — ${response.body}',
        );
        throw Exception('네이버 뉴스 검색 실패: ${response.statusCode}');
      } catch (e) {
        debugPrint('❌ Naver API 호출 오류: $e, Query: $query');
        throw Exception('Naver API 오류: $e');
      }
    });
  }

  /// 지역별 뉴스 조회
  Future<List<News>> getNewsByRegion(
    String region, {
    int display = 30,
    int start = 1,
  }) async {
    final keywords = _getQueryByRegion(region);
    if (keywords.isEmpty) return [];
    return searchNews(query: keywords, display: display, start: start);
  }

  /// 카테고리별 뉴스 조회
  Future<List<News>> getNewsByCategory(
    String category, {
    int display = 30,
    int start = 1,
  }) async {
    return searchNews(query: category, display: display, start: start);
  }

  /// 관심 키워드 뉴스 조회
  Future<List<News>> getNewsByKeywords(
    List<String> keywords, {
    int display = 30,
    int start = 1,
  }) async {
    if (keywords.isEmpty) return [];
    final query = keywords.join(' OR ');
    return searchNews(query: query, display: display, start: start);
  }

  // ── 파싱 헬퍼 ────────────────────────────────────────────

  /// 네이버 뉴스 아이템 → News 모델 변환
  News _parseNews(Map<String, dynamic> item) {
    final now = DateTime.now();
    final rawTitle = item['title'] as String? ?? '';
    final rawDesc = item['description'] as String? ?? '';

    // 네이버 API는 제목/설명에 <b>, &amp; 등 HTML이 포함되어 있음 — 제거
    final title = _stripHtml(rawTitle);
    final description = _stripHtml(rawDesc);
    final content = '$title $description';

    // 원문 링크 (originallink 없으면 네이버 링크 사용)
    final naverLink = item['link'] as String? ?? '';
    final newsUrl = (item['originallink'] as String?)?.isNotEmpty == true
        ? item['originallink'] as String
        : naverLink;

    // press_id 기반 한글 언론사명 (Naver link에서 추출) → 실패 시 도메인 fallback
    final pressIdName = _sourceFromNaverLink(naverLink);
    final source = pressIdName.isNotEmpty
        ? pressIdName
        : _extractSource(newsUrl);
    // debugPrint(
    //   '🗞️ 언론사 변환 | '
    //   'naverLink=$naverLink | '
    //   'originalLink=$newsUrl | '
    //   'pressId=${pressIdName.isNotEmpty ? pressIdName : "미등록"} | '
    //   'result=$source',
    // );

    final publishedAt = _parseDate(item['pubDate'] as String? ?? '');

    return News(
      id: newsUrl,
      title: title,
      description: description,
      content: description,
      source: source,
      imageUrl: '',
      newsUrl: newsUrl,
      publishedAt: publishedAt,
      createdAt: now,
      keywords: _extractKeywords(content),
      regions: _detectRegions(content),
      sentimentScore: _calculateSentimentScore(content),
      importanceLevel: _calculateImportanceLevel(content),
      category: _categorizeNews(content),
      stockRelevanceScore: _calculateStockRelevanceScore(content),
    );
  }

  /// HTML 태그 및 엔티티 제거
  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        // 십진수 numeric 엔티티: &#160; &#8211; &#8217; 등
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
          final code = int.tryParse(m.group(1)!);
          return code != null ? String.fromCharCode(code) : m.group(0)!;
        })
        // 16진수 numeric 엔티티: &#x00A0; &#xAD; 등
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);', caseSensitive: false), (
          m,
        ) {
          final code = int.tryParse(m.group(1)!, radix: 16);
          return code != null ? String.fromCharCode(code) : m.group(0)!;
        })
        // 이름있는 엔티티
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&middot;', '·')
        .replaceAll('&hellip;', '…')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&rsquo;', "'")
        .replaceAll('&lsquo;', "'")
        .replaceAll('&rdquo;', '"')
        .replaceAll('&ldquo;', '"')
        // 연속 공백·개행 정리
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        // 네이버 API trailing 말줄임표 제거 (UI가 자체 클리핑하므로 중복 방지)
        .replaceAll(RegExp(r'[.…]{2,}\s*$'), '')
        .trim();
  }

  /// RFC2822 날짜 문자열 파싱 (예: "Mon, 24 Mar 2026 10:00:00 +0900")
  DateTime _parseDate(String dateStr) {
    try {
      // RFC2822 → DateTime (Dart는 기본 파싱 불가, 수동 처리)
      final months = {
        'Jan': 1,
        'Feb': 2,
        'Mar': 3,
        'Apr': 4,
        'May': 5,
        'Jun': 6,
        'Jul': 7,
        'Aug': 8,
        'Sep': 9,
        'Oct': 10,
        'Nov': 11,
        'Dec': 12,
      };
      // "Mon, 24 Mar 2026 10:30:00 +0900" 형식
      final parts = dateStr.split(' ');
      if (parts.length >= 5) {
        final day = int.tryParse(parts[1]) ?? 1;
        final month = months[parts[2]] ?? 1;
        final year = int.tryParse(parts[3]) ?? DateTime.now().year;
        final timeParts = parts[4].split(':');
        final hour = int.tryParse(timeParts[0]) ?? 0;
        final min = int.tryParse(timeParts[1]) ?? 0;
        final sec = int.tryParse(timeParts[2]) ?? 0;
        return DateTime(year, month, day, hour, min, sec);
      }
    } catch (_) {}
    return DateTime.now();
  }

  /// URL에서 뉴스 소스(도메인) 추출
  /// Naver 언론사 press_id → 한글 언론사명
  /// press_id는 Naver가 언론사 온보딩 시 부여하는 고유 숫자로, 도메인과 달리 영구 불변입니다.
  /// 신규 언론사가 추가되면 press_id를 1회 등록하면 이후 유지 불필요.
  static const _pressIdToKo = {
    '001': '연합뉴스',
    '003': '뉴시스',
    '005': '국민일보',
    '006': '서울신문',
    '011': '서울경제',
    '013': '경기일보',
    '014': '파이낸셜뉴스',
    '015': '한국경제',
    '016': '헤럴드경제',
    '018': '이데일리',
    '020': 'MBC',
    '021': '문화일보',
    '022': '세계일보',
    '023': '조선일보',
    '025': '중앙일보',
    '028': '한겨레',
    '030': '전자신문',
    '032': '경향신문',
    '034': 'YTN',
    '035': '한국일보',
    '036': '조선비즈',
    '037': '매일경제',
    '038': '한경TV',
    '040': 'SBS',
    '041': 'KBS',
    '042': 'MBN',
    '047': '오마이뉴스',
    '050': '이투데이',
    '055': 'SBS Biz',
    '056': '머니투데이',
    '057': '아시아경제',
    '058': '비즈니스포스트',
    '061': '동아일보',
    '064': '채널A',
    '069': '아이뉴스24',
    '079': '노컷뉴스',
    '082': 'KBS World',
    '086': '뉴스통신',
    '087': '한겨레21',
    '092': 'TV조선',
    '093': 'JTBC',
    '094': '채널A',
    '095': 'MBN',
    '096': 'NSP통신',
    '098': '중도일보',
    '119': '재경일보',
    '138': '뉴시스',
    '215': '스포츠서울',
    '277': '아시아경제',
    '374': '매일경제TV',
    '421': '데일리안',
    '437': '뉴스핌',
    '448': '인베스트조선',
    '469': '비즈워치',
    '481': '뉴스1',
    '524': '한경닷컴',
  };

  /// Naver link URL에서 press_id 추출 → 한글 언론사명 반환
  /// 예: https://n.news.naver.com/mnews/article/001/0014712345 → '연합뉴스'
  /// 구형: https://news.naver.com/...?oid=001&aid=... → '연합뉴스'
  static String _sourceFromNaverLink(String naverLink) {
    // 신형: /article/001/0014712345
    final m1 = RegExp(r'/article/(\d+)/').firstMatch(naverLink);
    if (m1 != null) {
      final pressId = m1.group(1)!;
      final name = _pressIdToKo[pressId];
      if (name == null) {
        _logVerbose('⚠️ press_id 미등록: $pressId (naverLink=$naverLink)');
      }
      return name ?? '';
    }
    // 구형: ?..&oid=001&..
    final m2 = RegExp(r'[?&]oid=(\d+)').firstMatch(naverLink);
    if (m2 != null) {
      final pressId = m2.group(1)!;
      final name = _pressIdToKo[pressId];
      if (name == null) {
        _logVerbose('⚠️ press_id 미등록(구형): $pressId (naverLink=$naverLink)');
      }
      return name ?? '';
    }
    return '';
  }

  // 도메인 약자 → 한글 (press_id 매칭 실패 시 fallback)
  static const _domainToKo = {
    'chosun': '조선일보',
    'donga': '동아일보',
    'joongang': '중앙일보',
    'joins': '중앙일보',
    'hani': '한겨레',
    'khan': '경향신문',
    'ohmynews': '오마이뉴스',
    'mk': '매일경제',
    'hankyung': '한국경제',
    'sedaily': '서울경제',
    'etnews': '전자신문',
    'mt': '머니투데이',
    'newspim': '뉴스핌',
    'edaily': '이데일리',
    'fnnews': '파이낸셜뉴스',
    'asiaeconomy': '아시아경제',
    'ajunews': '아주경제',
    'bizwatch': '비즈워치',
    'thebell': '더벨',
    'yna': '연합뉴스',
    'yonhap': '연합뉴스',
    'newsis': '뉴시스',
    'news1': '뉴스1',
    'kbs': 'KBS',
    'mbc': 'MBC',
    'sbs': 'SBS',
    'jtbc': 'JTBC',
    'tvchosun': 'TV조선',
    'mbn': 'MBN',
    'ytn': 'YTN',
    'reuters': '로이터',
    'bloomberg': '블룸버그',
  };

  String _extractSource(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.contains('naver')) return '네이버 뉴스';

      final host = uri.host.replaceFirst('www.', '');

      if (host == 'magazine.hankyung.com') {
        final section = uri.pathSegments.isNotEmpty
            ? uri.pathSegments.first
            : '';
        switch (section) {
          case 'business':
            return '한경BUSINESS';
          case 'money':
            return '한경MONEY';
          case 'job-joy':
            return '한경JOB&JOY';
          default:
            return '한경매거진';
        }
      }

      // 1순위: 자동 크롤링 캐시
      final cached = _pressCache.resolveSync(host);
      if (cached != null) {
        _logVerbose('📰 [크롤링캐시] $host → $cached');
        return cached;
      }

      // 캐시 미스 → 백그라운드 크롤링 예약
      _pressCache.prefetch(host);

      // 2순위: 하드코딩 도메인 맵 (크롤링 완료 전 fallback)
      final parts = host.split('.');
      final String key;
      if (parts.length >= 3 && parts.last == 'kr') {
        key = parts[parts.length - 3];
      } else if (parts.length >= 2) {
        key = parts[parts.length - 2];
      } else {
        key = parts.first;
      }
      final mapped = _domainToKo[key.toLowerCase()];
      if (mapped != null) {
        _logVerbose('📰 [하드코딩맵] $host (key=$key) → $mapped');
      } else {
        _logVerbose('📰 [도메인원문] $host (key=$key) → 매핑없음, 크롤링 예약됨');
      }
      final result = mapped ?? (key.isNotEmpty ? key : host);
      return result.isNotEmpty ? result : '';
    } catch (_) {
      return '';
    }
  }

  // ── 분석 헬퍼 (한국어 텍스트 기준) ─────────────────────────

  List<String> _extractKeywords(String content) {
    final keywords = <String>[];
    const patterns = [
      '코스피',
      '코스닥',
      '나스닥',
      '다우존스',
      'S&P',
      '금리',
      '기준금리',
      '한국은행',
      '연준',
      '금리인상',
      '금리인하',
      '유가',
      '원유',
      'OPEC',
      '반도체',
      'AI',
      '인공지능',
      '삼성전자',
      'SK하이닉스',
      '현대차',
      '카카오',
      '네이버',
      '환율',
      '달러',
      '엔화',
      '위안화',
      '이스라엘',
      '우크라이나',
      '러시아',
      '중국',
      '미국',
      '인플레이션',
      '경기침체',
      '무역전쟁',
      '관세',
    ];
    for (final kw in patterns) {
      if (content.contains(kw)) keywords.add(kw);
    }
    return keywords;
  }

  List<String> _detectRegions(String content) {
    final regions = <String>{};
    const regionPatterns = {
      'MidEast': ['중동', '이란', '사우디', '이스라엘', '이라크', '팔레스타인', '하마스'],
      'USA': ['미국', '미 연준', '연준', '워싱턴', '뉴욕', '월가', '월스트리트'],
      'Asia': ['중국', '일본', '한국', '인도', '대만', '아시아', '홍콩'],
      'Europe': ['유럽', '러시아', '우크라이나', 'EU', '독일', '영국', '프랑스'],
    };
    regionPatterns.forEach((region, patterns) {
      if (patterns.any((p) => content.contains(p))) regions.add(region);
    });
    return regions.toList();
  }

  double _calculateSentimentScore(String content) {
    int positive = 0, negative = 0;
    const positiveWords = [
      '상승',
      '급등',
      '호조',
      '반등',
      '돌파',
      '신고가',
      '성장',
      '흑자',
      '수익',
      '기대',
      '회복',
      '개선',
      '강세',
      '랠리',
      '호재',
      '증가',
      '확대',
      '호실적',
      '낙관',
    ];
    const negativeWords = [
      '하락',
      '급락',
      '폭락',
      '위기',
      '적자',
      '손실',
      '충격',
      '불안',
      '공포',
      '우려',
      '악화',
      '약세',
      '침체',
      '위협',
      '악재',
      '감소',
      '축소',
      '부진',
      '비관',
      '전쟁',
      '갈등',
    ];
    for (final w in positiveWords) {
      if (content.contains(w)) positive++;
    }
    for (final w in negativeWords) {
      if (content.contains(w)) negative++;
    }
    if (positive + negative == 0) return 0.0;
    return (positive - negative) / (positive + negative);
  }

  double _calculateStockRelevanceScore(String content) {
    int score = 0;
    const highWeight = [
      '코스피',
      '코스닥',
      '주가',
      '주식시장',
      '증시',
      '상한가',
      '하한가',
      '급등주',
      '급락주',
      '시가총액',
      '나스닥',
      '다우존스',
      'S&P',
      '닛케이',
      '항셍',
      'IPO',
      '상장',
      '공모주',
      '배당',
      '자사주',
      '금리인상',
      '금리인하',
      '기준금리 결정',
      '연준 결정',
      '실적발표',
      '분기실적',
      'EPS',
      '어닝쇼크',
      '어닝서프라이즈',
    ];
    const midWeight = [
      '기준금리', '한국은행', '연준', '중앙은행', '통화정책',
      '인플레이션', '소비자물가', 'CPI', 'GDP', '경기침체',
      '무역전쟁', '관세', '제재', '환율', '달러', '엔화', '위안화',
      '유가', '원유', '금값', '국채', '채권금리',
      '삼성전자', 'SK하이닉스', '현대차', '카카오', '네이버',
      'TSMC', '엔비디아', '애플', '마이크로소프트',
      '매출', '영업이익', '순이익', '적자전환', '흑자전환',
      'ETF', '펀드', '포트폴리오', '자산', '헤지펀드',
      '신용등급', '부도', '인수합병', 'M&A',
      // 지정학 — 유가·시장에 직접 영향
      '트럼프', '이란', '이스라엘', '중동', '하마스', '헤즈볼라', '지정학',
    ];
    const lowWeight = [
      '경제', '금융', '시장', '은행', '무역', '투자',
      '고용', '실업률', '소비', '수출', '수입', '경상수지',
      '공급망', '반도체', '부동산', '주택시장',
      // 분쟁·외교 — 유가·환율 간접 영향
      '전쟁', '분쟁', '갈등', '휴전', '제재', '병력', '군사',
    ];

    for (final k in highWeight) {
      if (content.contains(k)) score += 3;
    }
    for (final k in midWeight) {
      if (content.contains(k)) score += 2;
    }
    for (final k in lowWeight) {
      if (content.contains(k)) score += 1;
    }
    return (score / 24.0).clamp(0.0, 1.0);
  }

  int _calculateImportanceLevel(String content) {
    final stockScore = _calculateStockRelevanceScore(content);
    if (stockScore >= 0.5) return 5;
    if (stockScore >= 0.4) return 4;
    if (stockScore >= 0.3) return 3;
    if (stockScore >= 0.15) return 2;
    return 1;
  }

  String _categorizeNews(String content) {
    if (content.contains('코스피') ||
        content.contains('코스닥') ||
        content.contains('주가') ||
        content.contains('증시') ||
        content.contains('나스닥') ||
        content.contains('실적발표') ||
        content.contains('IPO') ||
        content.contains('배당') ||
        content.contains('상장')) {
      return '증시';
    }
    if (content.contains('금리') ||
        content.contains('한국은행') ||
        content.contains('연준') ||
        content.contains('인플레이션') ||
        content.contains('GDP') ||
        content.contains('경기침체') ||
        content.contains('무역') ||
        content.contains('경제') ||
        content.contains('시장')) {
      return '경제';
    }
    if (content.contains('유가') ||
        content.contains('원유') ||
        content.contains('OPEC') ||
        content.contains('가스')) {
      return '에너지';
    }
    if (content.contains('전쟁') ||
        content.contains('군사') ||
        content.contains('국방')) {
      return '군사';
    }
    if (content.contains('정치') || content.contains('정부')) {
      return '정치';
    }
    return '기타';
  }

  String _getQueryByRegion(String region) {
    const queries = {
      'MidEast': '중동 유가 이란 사우디 이스라엘',
      'USA': '미국 금리 연준 나스닥 미국 경제',
      'Asia': '코스피 코스닥 일본 닛케이 중국 경제 대만',
      'Europe': '유럽 ECB 금리 러시아 우크라이나',
    };
    return queries[region] ?? '';
  }
}
