import 'package:flutter/foundation.dart';

import '../models/index.dart';
import '../services/index.dart';

/// 사용자 설정 Repository
class UserPreferenceRepository {
  final LocalStorageService localService;

  UserPreferenceRepository({required this.localService});

  /// 사용자 설정 조회
  Future<UserPreference?> getUserPreference() async {
    return localService.getUserPreference();
  }

  /// 사용자 설정 저장
  Future<void> saveUserPreference(UserPreference preference) async {
    await localService.saveUserPreference(preference);
  }

  /// 관심 키워드 추가
  Future<void> addFavoriteKeyword(String keyword) async {
    final normalizedKeyword = keyword.trim();
    var preference = localService.getUserPreference();

    preference ??= UserPreference(
      userId: 'default_user',
      createdAt: DateTime.now(),
      lastUpdatedAt: DateTime.now(),
    );

    if (!preference.favoriteKeywords.any(
      (item) => item.trim() == normalizedKeyword,
    )) {
      final updated = preference.copyWith(
        favoriteKeywords: [...preference.favoriteKeywords, normalizedKeyword],
        lastUpdatedAt: DateTime.now(),
      );
      await localService.saveUserPreference(updated);
      debugPrint('saved favorite keywords: ${updated.favoriteKeywords}');
    }
  }

  /// 관심 키워드 제거
  Future<void> removeFavoriteKeyword(String keyword) async {
    final normalizedKeyword = keyword.trim();
    final preference = localService.getUserPreference();

    if (preference != null) {
      final updated = preference.copyWith(
        favoriteKeywords: preference.favoriteKeywords
            .where((k) => k.trim() != normalizedKeyword)
            .toList(),
        lastUpdatedAt: DateTime.now(),
      );
      await localService.saveUserPreference(updated);
      debugPrint(
        'saved favorite keywords after remove: ${updated.favoriteKeywords}',
      );
    }
  }

  /// 알림 레벨 변경
  Future<void> setAlertLevel(String level) async {
    var preference = localService.getUserPreference();

    preference ??= UserPreference(
      userId: 'default_user',
      createdAt: DateTime.now(),
      lastUpdatedAt: DateTime.now(),
    );

    final updated = preference.copyWith(
      alertLevel: level,
      lastUpdatedAt: DateTime.now(),
    );
    await localService.saveUserPreference(updated);
  }

  /// 알림 토글
  Future<void> toggleNotifications(bool enabled) async {
    var preference = localService.getUserPreference();

    preference ??= UserPreference(
      userId: 'default_user',
      createdAt: DateTime.now(),
      lastUpdatedAt: DateTime.now(),
    );

    final updated = preference.copyWith(
      notificationsEnabled: enabled,
      lastUpdatedAt: DateTime.now(),
    );
    await localService.saveUserPreference(updated);
  }

  /// 테마 모드 변경
  Future<void> setThemeMode(String themeMode) async {
    var preference = localService.getUserPreference();

    preference ??= UserPreference(
      userId: 'default_user',
      createdAt: DateTime.now(),
      lastUpdatedAt: DateTime.now(),
    );

    final updated = preference.copyWith(
      themeMode: UserPreference.isSupportedThemeMode(themeMode)
          ? themeMode
          : UserPreference.themeModeSystem,
      lastUpdatedAt: DateTime.now(),
    );
    await localService.saveUserPreference(updated);
  }
}
