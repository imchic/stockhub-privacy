import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/index.dart';
import '../data/services/api_exceptions.dart';
import 'repositories_provider.dart';
import 'user_preference_providers.dart';

/// 뉴스 관련 상태 프로바이더들

/// 검색 키워드 상태 (초기값: 글로벌 증시 경제 뉴스)
final searchKeywordProvider = StateProvider<String>((ref) => '주식 증시 경제 금리');

/// 지역 선택 상태
final selectedRegionProvider = StateProvider<String>((ref) => '전체');

/// 뉴스 리스트 상태 (검색 결과 + 시간 범위 필터)
/// 당일 기준 뉴스 피드
final newsListProvider = FutureProvider<List<News>>((ref) async {
  final repository = await ref.watch(newsRepositoryProvider.future);
  final keyword = ref.watch(searchKeywordProvider);
  final favoriteKeywords = ref.watch(favoriteKeywordsControllerProvider);

  // 관심 키워드를 검색 쿼리에 포함 (최대 3개, 중복 방지)
  final base = keyword.isEmpty ? '증시 경제 금리' : keyword;
  final extra = favoriteKeywords.take(3).join(' ');
  final searchQuery = extra.isNotEmpty ? '$base $extra' : base;

  try {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day); // 당일 00:00

    final newsList = await repository.searchNews(
      query: searchQuery,
      sortBy: 'publishedAt',
      pageSize: 100,
      from: todayStart,
      to: now,
    );

    // 데이터가 없으면 캐시 반환
    if (newsList.isEmpty) {
      return repository.getCachedNews();
    }

    return newsList;
  } catch (e) {
    // 에러 발생 시 캐시된 데이터 반환
    debugPrint('뉴스 로드 에러: $e');
    return repository.getCachedNews();
  }
});

/// 지역별 뉴스 상태
final newsByRegionProvider = FutureProvider.family<List<News>, String>((
  ref,
  region,
) async {
  final repository = await ref.watch(newsRepositoryProvider.future);
  return repository.getNewsByRegion(region);
});

/// 카테고리별 뉴스 상태
final newsByCategoryProvider = FutureProvider.family<List<News>, String>((
  ref,
  category,
) async {
  final repository = await ref.watch(newsRepositoryProvider.future);
  return repository.getNewsByCategory(category);
});

/// 북마크된 뉴스 상태
final bookmarkedNewsProvider = FutureProvider<List<News>>((ref) async {
  final repository = await ref.watch(newsRepositoryProvider.future);
  return repository.getBookmarkedNews();
});

/// 북마크 토글 함수
final toggleBookmarkProvider = FutureProvider.family<void, News>((
  ref,
  news,
) async {
  final repository = await ref.watch(newsRepositoryProvider.future);
  await repository.toggleBookmark(news);

  // 상태 갱신 (newsListProvider는 건드리지 않음 — API 재호출 방지)
  ref.invalidate(bookmarkedNewsProvider);
});

/// 뉴스 메모 저장 함수
final saveNewsNoteProvider = FutureProvider.family<void, (String, String)>((
  ref,
  params,
) async {
  final (newsId, note) = params;
  final repository = await ref.watch(newsRepositoryProvider.future);
  await repository.saveNewsNote(newsId, note);
});

/// 선택된 필터
final newsFilterProvider = StateProvider<NewsFilter>((ref) => NewsFilter());

/// 필터 적용된 뉴스
final filteredNewsProvider = FutureProvider<List<News>>((ref) async {
  final allNews = await ref.watch(newsListProvider.future);
  final filter = ref.watch(newsFilterProvider);
  final selectedRegion = ref.watch(selectedRegionProvider);
  var filtered = allNews;

  // 지역 필터
  if (selectedRegion != '전체') {
    filtered = filtered
        .where((news) => news.regions.contains(selectedRegion))
        .toList();
  }

  // 기존 filter 규칙 적용
  if (filter.selectedRegions.isNotEmpty) {
    filtered = filtered
        .where(
          (news) => news.regions.any((r) => filter.selectedRegions.contains(r)),
        )
        .toList();
  }

  // 카테고리 필터
  if (filter.selectedCategories.isNotEmpty) {
    filtered = filtered
        .where((news) => filter.selectedCategories.contains(news.category))
        .toList();
  }

  // 중요도 필터
  filtered = filtered
      .where((news) => filter.importanceLevels.contains(news.importanceLevel))
      .toList();

  // 검색 키워드 필터
  if (filter.searchKeyword.isNotEmpty) {
    filtered = filtered
        .where(
          (news) =>
              news.title.toLowerCase().contains(
                filter.searchKeyword.toLowerCase(),
              ) ||
              news.description.toLowerCase().contains(
                filter.searchKeyword.toLowerCase(),
              ),
        )
        .toList();
  }

  // 북마크 필터
  if (filter.onlyBookmarked) {
    filtered = filtered.where((news) => news.isBookmarked).toList();
  }

  // 정렬
  switch (filter.sortBy) {
    case 'trending':
      filtered.sort((a, b) => b.importanceLevel.compareTo(a.importanceLevel));
      break;
    case 'importance':
      filtered.sort((a, b) => b.importanceLevel.compareTo(a.importanceLevel));
      break;
    case 'latest':
    default:
      filtered.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
  }

  return filtered;
});

/// 지역별 필터 적용 헬퍼 함수
List<News> _applyRegionFilter(List<News> news, String region) {
  if (region == '전체') return news;
  return news.where((n) => n.regions.contains(region)).toList();
}

/// 시장별 키워드 매핑
const _marketKeywords = <String, List<String>>{
  '코스피': ['코스피', 'KOSPI', 'kospi', '유가증권', '한국증시', '국내주식', '코스피지수'],
  '코스닥': ['코스닥', 'KOSDAQ', 'kosdaq', '코스닥지수', '코스닥시장'],
  '나스닥': ['나스닥', 'NASDAQ', 'nasdaq', '기술주', '빅테크', '미국기술'],
  'S&P500': ['S&P', 's&p', '다우', '뉴욕증시', '미국증시', '월가', '뉴욕', '다우존스'],
  '원자재': ['원자재', '유가', '금값', '원유', '구리', '천연가스', 'WTI', '금시세', '배럴'],
};

bool _matchesMarket(News news, List<String> keywords) {
  final text = '${news.title} ${news.description} ${news.keywords.join(' ')}'
      .toLowerCase();
  return keywords.any((kw) => text.contains(kw.toLowerCase()));
}

/// 시장별 뉴스 (provider.family)
final marketNewsProvider = FutureProvider.family<List<News>, String>((
  ref,
  market,
) async {
  final allNews = await ref.watch(stockMarketNewsProvider.future);
  final region = ref.watch(selectedRegionProvider);

  List<News> filtered;
  if (market == '전체') {
    filtered = List.of(allNews);
  } else {
    final keywords = _marketKeywords[market] ?? [];
    filtered = allNews.where((n) => _matchesMarket(n, keywords)).toList();
  }

  return _applyRegionFilter(filtered, region);
});

/// 호재 뉴스 (양수 센티멘트)
final positiveSentimentNewsProvider = FutureProvider<List<News>>((ref) async {
  final allNews = await ref.watch(newsListProvider.future);
  final region = ref.watch(selectedRegionProvider);

  var filtered = allNews.where((news) => news.sentimentScore > 0.1).toList();
  filtered = _applyRegionFilter(filtered, region);

  return filtered..sort((a, b) => b.sentimentScore.compareTo(a.sentimentScore));
});

/// 악재 뉴스 (음수 센티멘트)
final negativeSentimentNewsProvider = FutureProvider<List<News>>((ref) async {
  final allNews = await ref.watch(newsListProvider.future);
  final region = ref.watch(selectedRegionProvider);

  var filtered = allNews.where((news) => news.sentimentScore < -0.1).toList();
  filtered = _applyRegionFilter(filtered, region);

  return filtered..sort((a, b) => a.sentimentScore.compareTo(b.sentimentScore));
});

/// 중립 뉴스 (중립 센티멘트)
final neutralSentimentNewsProvider = FutureProvider<List<News>>((ref) async {
  final allNews = await ref.watch(newsListProvider.future);
  final region = ref.watch(selectedRegionProvider);

  var filtered = allNews
      .where(
        (news) => news.sentimentScore >= -0.1 && news.sentimentScore <= 0.1,
      )
      .toList();
  filtered = _applyRegionFilter(filtered, region);

  return filtered;
});

/// 증시 영향 뉴스 (금융/경제/주식 관련)
/// 초기 진입 체감 속도를 위해 핵심 쿼리만 우선 수집한다.
final stockMarketNewsProvider = FutureProvider<List<News>>((ref) async {
  final repository = await ref.watch(newsRepositoryProvider.future);
  final favoriteKeywords = ref.watch(favoriteKeywordsControllerProvider);
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day); // 당일 00:00

  // 중복·유사 쿼리를 더 강하게 통합하여 초기 호출 수를 줄인다.
  final baseQueries = [
    '코스피 코스닥 나스닥 다우 S&P 증시 금리 환율',
    '실적 전망 가이던스 수주 계약 투자 증설 자사주 배당 공급계약 수출',
    '반도체 AI HBM 배터리 전기차 바이오 로봇 방산 조선 원전',
    '트럼프 관세 무역 인플레이션 경기침체 환율 유가 금값 원유 OPEC 중동 이스라엘 이란',
    '비트코인 이더리움 ETF 규제 유동성 달러 금리 위험자산',
  ];
  final sectorLeaderQueries = [
    '강세섹터 약세섹터 주도주 순환매 수급 급등 급락',
    '반도체 AI 전력기기 원전 방산 조선 금융 바이오 주도주',
    '2차전지 로봇 화장품 엔터 게임 제약 유리기판 주도주',
  ];
  // 관심 키워드가 없으면 섹터 주도주 기반 쿼리로 종목 풀을 넓힌다.
  final extraQueries = favoriteKeywords.isEmpty
      ? sectorLeaderQueries
      : favoriteKeywords.take(2).toList();
  final queries = [...baseQueries, ...extraQueries];

  try {
    debugPrint('📡 증시 뉴스: ${queries.length}개 쿼리 순차 실행 중...');

    // 순차 실행 + 요청 간 250ms 딜레이
    final results = <List<News>>[];
    for (int i = 0; i < queries.length; i++) {
      if (i > 0) await Future.delayed(const Duration(milliseconds: 250));
      try {
        final result = await repository.searchNews(
          query: queries[i],
          sortBy: 'publishedAt',
          pageSize: 60,
          from: todayStart,
          to: now,
        );
        results.add(result);
      } on ApiAuthException catch (error) {
        debugPrint('⛔ 증시 뉴스 중단: $error');
        rethrow;
      } on ApiConfigurationException catch (error) {
        debugPrint('⛔ 증시 뉴스 중단: $error');
        rethrow;
      } catch (_) {
        results.add([]);
      }
    }

    // 결과 합치기 + 중복 제거 (URL 기준)
    final seen = <String>{};
    final allNews = <News>[];
    for (final list in results) {
      for (final news in list) {
        if (seen.add(news.id)) {
          allNews.add(news);
        }
      }
    }

    debugPrint('📊 수집된 전체: ${allNews.length}개');

    // stockRelevanceScore 0.1 이상 뉴스만 필터링하고 관련성 높은 순으로 정렬
    // (지정학·외교 뉴스도 포함하기 위해 임계값 완화)
    final stockNews =
        allNews.where((n) => n.stockRelevanceScore >= 0.1).toList()..sort(
          (a, b) => b.stockRelevanceScore.compareTo(a.stockRelevanceScore),
        );

    if (stockNews.isNotEmpty) {
      debugPrint('✅ 증시 관련 뉴스: ${stockNews.length}개 (${allNews.length}개 중)');
      return stockNews;
    }

    // 필터링 후 없으면 전체 최신순 반환
    allNews.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return allNews;
  } catch (e) {
    debugPrint('❌ 증시 뉴스 로드 에러: $e');
    return repository.getCachedNews();
  }
});

/// 증시 뉴스 Provider — 한국어 뉴스를 직접 수신하므로 번역 없이 그대로 반환
final translatedStockMarketNewsProvider = FutureProvider<List<News>>((
  ref,
) async {
  return ref.watch(stockMarketNewsProvider.future);
});

/// 실시간 속보 — importanceLevel 4+ 우선, 없으면 최신순 상위 20개
final breakingNewsProvider = FutureProvider<List<News>>((ref) async {
  final all = await ref.watch(stockMarketNewsProvider.future);
  if (all.isEmpty) return [];

  // 코인/암호화폐 뉴스 제외 (증시 뉴스만 속보로 표시)
  final cryptoKeywords = RegExp(
    r'비트코인|이더리움|암호화폐|코인|가상화폐|BTC|ETH|리플|XRP|솔라나|SOL|도지',
    caseSensitive: false,
  );
  final stockOnly = all
      .where((n) => !cryptoKeywords.hasMatch(n.title))
      .toList();

  // level 4 이상만 먼저 추출 (신뢰 언론 or 증시 고관련)
  final highImportance = stockOnly.where((n) => n.importanceLevel >= 4).toList()
    ..sort((a, b) {
      final cmp = b.importanceLevel.compareTo(a.importanceLevel);
      if (cmp != 0) return cmp;
      return b.publishedAt.compareTo(a.publishedAt);
    });

  if (highImportance.isNotEmpty) return highImportance.take(20).toList();

  // level 4+ 기사가 없을 때는 stockOnly 최신순 상위 10개로 fallback
  final sorted = [...stockOnly]
    ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
  return sorted.take(10).toList();
});

/// 실시간 뉴스 스트림 (주기적으로 새로운 뉴스 확인)
/// 5초마다 새로운 뉴스 폴링
final realtimeNewsStreamProvider = StreamProvider<List<News>>((ref) async* {
  final repository = await ref.watch(newsRepositoryProvider.future);
  final keyword = ref.watch(searchKeywordProvider);
  final searchQuery = keyword.isEmpty ? '증시 경제 금리' : keyword;

  DateTime todayStart() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day); // 당일 00:00
  }

  // 초기값 반환
  try {
    final now = DateTime.now();
    final initialNews = await repository.searchNews(
      query: searchQuery,
      pageSize: 100,
      from: todayStart(),
      to: now,
    );
    yield initialNews.isNotEmpty ? initialNews : repository.getCachedNews();
  } catch (e) {
    yield repository.getCachedNews();
  }

  // 주기적으로 새로운 뉴스 폴링 (10분마다 갱신 — API 할당량 절약)
  await for (final _ in Stream.periodic(const Duration(minutes: 10))) {
    try {
      final now = DateTime.now();
      final freshNews = await repository.searchNews(
        query: searchQuery,
        pageSize: 100,
        from: todayStart(),
        to: now,
      );
      yield freshNews.isNotEmpty ? freshNews : repository.getCachedNews();
    } catch (e) {
      // 폴링 중 오류는 무시하고 계속 진행
      yield repository.getCachedNews();
    }
  }
});
