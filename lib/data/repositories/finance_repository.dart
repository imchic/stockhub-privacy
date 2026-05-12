import 'package:flutter/foundation.dart';

import '../models/index.dart';
import '../services/index.dart';

/// 금융 뉴스 Repository
class FinanceRepository {
  final FinanceApiService apiService;
  final LocalStorageService localService;

  // 캐시 TTL: 8시간 (rate limit 대응)
  static const _cacheTtl = Duration(hours: 8);

  FinanceRepository({required this.apiService, required this.localService});

  /// 통합 금융 뉴스 — 캐시 우선, 만료 시 API 1회 호출
  Future<List<FinanceNews>> getFinanceNews({int pageSize = 30}) async {
    // 유효한 캐시가 있으면 즉시 반환 (API 호출 없음)
    if (localService.isFinanceNewsCacheValid(ttl: _cacheTtl)) {
      final cached = localService.getCachedFinanceNews();
      if (cached.isNotEmpty) {
        debugPrint('📦 [FinanceRepo] 캐시 히트 → ${cached.length}건 반환');
        return cached;
      }
    }

    try {
      debugPrint('📡 [FinanceRepo] API 호출 시작');
      final news = await apiService.getFinanceNews(pageSize: pageSize);
      await localService.saveFinanceNews(news);
      debugPrint('✅ [FinanceRepo] API 완료 → ${news.length}건 캐시 저장');
      return news;
    } catch (e) {
      if (e is ApiAuthException || e is ApiConfigurationException) {
        final cached = localService.getCachedFinanceNews();
        if (cached.isNotEmpty) {
          debugPrint('⚠️ [FinanceRepo] 인증 실패, 캐시 반환 → ${cached.length}건');
          return cached;
        }
        debugPrint('⛔ [FinanceRepo] 인증/설정 오류: $e');
        rethrow;
      }

      // Rate limit 특별 처리
      if (e.toString().contains('429')) {
        debugPrint('⏱️ [FinanceRepo] Rate limit 감지, 캐시 TTL 연장');
        // 만료된 캐시라도 반환하고, 다음 호출까지 더 오래 대기
        final cached = localService.getCachedFinanceNews();
        if (cached.isNotEmpty) {
          debugPrint(
            '📦 [FinanceRepo] Rate limit 회피: 만료 캐시 반환 → ${cached.length}건',
          );
          return cached;
        }
      }

      // API 실패 시 만료된 캐시라도 반환
      final cached = localService.getCachedFinanceNews();
      if (cached.isNotEmpty) {
        debugPrint('⚠️ [FinanceRepo] API 실패, 만료 캐시 반환 → ${cached.length}건');
        return cached;
      }
      debugPrint('❌ [FinanceRepo] API 실패 & 캐시 없음: $e');
      throw Exception('금융 뉴스 조회 실패: $e');
    }
  }

  /// 코스피 뉴스 — allFinanceNews에서 필터링 (별도 API 호출 없음)
  Future<List<FinanceNews>> getKospiNews({int pageSize = 20}) async {
    final all = await getFinanceNews();
    return all
        .where(
          (n) => _containsAny(n.title + n.description, [
            '코스피',
            'KOSPI',
            '한국증시',
            '코스피200',
          ]),
        )
        .take(pageSize)
        .toList();
  }

  /// 나스닥 뉴스 — allFinanceNews에서 필터링
  Future<List<FinanceNews>> getNasdaqNews({int pageSize = 20}) async {
    final all = await getFinanceNews();
    return all
        .where(
          (n) => _containsAny(n.title + n.description, [
            '나스닥',
            'NASDAQ',
            '미국주식',
            '기술주',
          ]),
        )
        .take(pageSize)
        .toList();
  }

  /// 경제 뉴스 — allFinanceNews에서 필터링
  Future<List<FinanceNews>> getEconomicNews({int pageSize = 20}) async {
    final all = await getFinanceNews();
    return all
        .where(
          (n) => _containsAny(n.title + n.description, [
            '금리',
            'FED',
            '인플레이션',
            '경제',
            '재정',
          ]),
        )
        .take(pageSize)
        .toList();
  }

  /// 섹터별 뉴스 조회
  Future<List<FinanceNews>> getSectorNews(
    String sector, {
    int pageSize = 20,
  }) async {
    try {
      final news = await apiService.getSectorNews(sector, pageSize: pageSize);
      return news;
    } catch (e) {
      return [];
    }
  }

  /// 특정 종목 뉴스 조회
  Future<List<FinanceNews>> getStockNews(
    String ticker, {
    int pageSize = 20,
  }) async {
    try {
      final news = await apiService.getStockNews(ticker, pageSize: pageSize);
      return news;
    } catch (e) {
      return [];
    }
  }

  /// 섹터별 필터링
  Future<List<FinanceNews>> filterBySector(String sector) async {
    final all = await getFinanceNews();
    return all.where((n) => n.sectors.contains(sector)).toList();
  }

  /// 감정 필터링
  Future<List<FinanceNews>> filterBySentiment({
    double minScore = -1.0,
    double maxScore = 1.0,
  }) async {
    final all = await getFinanceNews();
    return all
        .where(
          (n) => n.sentimentScore >= minScore && n.sentimentScore <= maxScore,
        )
        .toList();
  }

  /// 긍정적인 뉴스만 (강세)
  Future<List<FinanceNews>> getPositiveNews() async {
    return filterBySentiment(minScore: 0.3);
  }

  /// 부정적인 뉴스만 (약세)
  Future<List<FinanceNews>> getNegativeNews() async {
    return filterBySentiment(maxScore: -0.3);
  }

  /// 북마크된 뉴스 조회
  Future<List<FinanceNews>> getBookmarkedNews() async {
    final all = localService.getCachedFinanceNews();
    return all.where((n) => n.isBookmarked).toList();
  }

  /// 북마크 추가
  Future<void> bookmarkNews(String newsId) async {
    final all = localService.getCachedFinanceNews();
    final idx = all.indexWhere((n) => n.id == newsId);
    if (idx != -1) {
      all[idx] = all[idx].copyWith(isBookmarked: true);
      await localService.saveFinanceNews(all);
    }
  }

  /// 북마크 해제
  Future<void> unbookmarkNews(String newsId) async {
    final all = localService.getCachedFinanceNews();
    final idx = all.indexWhere((n) => n.id == newsId);
    if (idx != -1) {
      all[idx] = all[idx].copyWith(isBookmarked: false);
      await localService.saveFinanceNews(all);
    }
  }

  bool _containsAny(String text, List<String> keywords) {
    final lower = text.toLowerCase();
    return keywords.any((kw) => lower.contains(kw.toLowerCase()));
  }
}
