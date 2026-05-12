import 'package:flutter/foundation.dart';

import '../models/index.dart';
import '../services/index.dart';

/// 뉴스 Repository
class NewsRepository {
  final NaverNewsService naverService;
  final LocalStorageService localService;

  NewsRepository({required this.naverService, required this.localService});

  /// 뉴스 검색 (Naver API + 캐시)
  Future<List<News>> searchNews({
    required String query,
    String sortBy = 'date',
    int page = 1,
    int pageSize = 30,
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final newsList = await naverService.searchNews(
        query: query,
        display: pageSize,
        start: ((page - 1) * pageSize) + 1,
        sortBy: sortBy == 'publishedAt' ? 'date' : sortBy,
      );

      final newsWithBookmarks = newsList
          .map(
            (news) =>
                news.copyWith(isBookmarked: localService.isBookmarked(news.id)),
          )
          .toList();

      if (page == 1) {
        await localService.saveNews(newsWithBookmarks);
        await localService.setLastUpdateTime(
          'news_update_time',
          DateTime.now(),
        );
      }

      return newsWithBookmarks;
    } catch (e) {
      if (e is ApiAuthException || e is ApiConfigurationException) {
        debugPrint('⛔ Repository 인증/설정 에러 (query: $query): $e');
        rethrow;
      }
      debugPrint('❌ Repository 에러 (query: $query): $e');
      final cached = localService.getCachedNews();
      debugPrint('📦 캐시에서 ${cached.length}개 기사 반환');
      return cached;
    }
  }

  /// 최근 뉴스 조회
  Future<List<News>> getRecentNews({
    required String query,
    int page = 1,
    int pageSize = 30,
  }) async {
    return searchNews(query: query, page: page, pageSize: pageSize);
  }

  /// 지역별 뉴스 조회
  Future<List<News>> getNewsByRegion(
    String region, {
    int page = 1,
    int pageSize = 30,
  }) async {
    try {
      final newsList = await naverService.getNewsByRegion(
        region,
        display: pageSize,
        start: ((page - 1) * pageSize) + 1,
      );

      final newsWithBookmarks = newsList
          .map(
            (news) =>
                news.copyWith(isBookmarked: localService.isBookmarked(news.id)),
          )
          .toList();

      if (page == 1) await localService.saveNews(newsWithBookmarks);
      return newsWithBookmarks;
    } catch (e) {
      if (e is ApiAuthException || e is ApiConfigurationException) {
        rethrow;
      }
      return localService
          .getCachedNews()
          .where((news) => news.regions.contains(region))
          .toList();
    }
  }

  /// 카테고리별 뉴스 조회
  Future<List<News>> getNewsByCategory(
    String category, {
    int page = 1,
    int pageSize = 30,
  }) async {
    try {
      final newsList = await naverService.getNewsByCategory(
        category,
        display: pageSize,
        start: ((page - 1) * pageSize) + 1,
      );

      final newsWithBookmarks = newsList
          .map(
            (news) =>
                news.copyWith(isBookmarked: localService.isBookmarked(news.id)),
          )
          .toList();

      if (page == 1) await localService.saveNews(newsWithBookmarks);
      return newsWithBookmarks;
    } catch (e) {
      if (e is ApiAuthException || e is ApiConfigurationException) {
        rethrow;
      }
      return localService
          .getCachedNews()
          .where((news) => news.category == category)
          .toList();
    }
  }

  /// 관심 키워드별 뉴스 조회
  Future<List<News>> getNewsByKeywords(
    List<String> keywords, {
    int page = 1,
    int pageSize = 30,
  }) async {
    try {
      final newsList = await naverService.getNewsByKeywords(
        keywords,
        display: pageSize,
        start: ((page - 1) * pageSize) + 1,
      );

      final newsWithBookmarks = newsList
          .map(
            (news) =>
                news.copyWith(isBookmarked: localService.isBookmarked(news.id)),
          )
          .toList();

      if (page == 1) await localService.saveNews(newsWithBookmarks);
      return newsWithBookmarks;
    } catch (e) {
      if (e is ApiAuthException || e is ApiConfigurationException) {
        rethrow;
      }
      return localService.getCachedNews();
    }
  }

  /// 북마크된 뉴스 조회
  List<News> getBookmarkedNews() {
    // _bookmarkedNewsObjectsKey에 저장된 전체 객체를 읽어 반환
    // (getCachedNews 필터 방식은 캐시 갱신 시 유실 위험 있음)
    return localService.getBookmarkedNewsObjects();
  }

  /// 북마크 토글
  Future<void> toggleBookmark(News news) async {
    await localService.toggleBookmark(news);
  }

  /// 메모 저장
  Future<void> saveNewsNote(String newsId, String note) async {
    final cachedNews = localService.getCachedNews();
    final newsIndex = cachedNews.indexWhere((n) => n.id == newsId);

    if (newsIndex != -1) {
      final updatedNews = cachedNews[newsIndex].copyWith(memo: note);
      cachedNews[newsIndex] = updatedNews;
      await localService.saveNews(cachedNews);
    }
  }

  /// 캐시된 뉴스 조회
  List<News> getCachedNews() {
    return localService.getCachedNews();
  }

  /// 캐시 초기화
  Future<void> clearCache() async {
    await localService.clearNews();
  }
}
