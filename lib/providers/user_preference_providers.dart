import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/index.dart';
import '../services/app_onboarding_service.dart';
import '../services/background_task_service.dart';
import '../services/notification_service.dart';
import 'repositories_provider.dart';

/// 사용자 설정 관련 상태 프로바이더들

/// 사용자 설정
final userPreferenceProvider = FutureProvider<UserPreference?>((ref) async {
  final repository = await ref.watch(userPreferenceRepositoryProvider.future);
  return repository.getUserPreference();
});

class FavoriteKeywordsController extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final repository = await ref.watch(userPreferenceRepositoryProvider.future);
    final preference = await repository.getUserPreference();
    return List<String>.from(preference?.favoriteKeywords ?? const <String>[]);
  }

  Future<void> addKeyword(String keyword) async {
    final normalizedKeyword = keyword.trim();
    if (normalizedKeyword.isEmpty) return;

    final previous = List<String>.from(state.valueOrNull ?? await future);
    if (previous.contains(normalizedKeyword)) return;

    state = AsyncData(<String>[...previous, normalizedKeyword]);

    try {
      final repository = await ref.read(
        userPreferenceRepositoryProvider.future,
      );
      await repository.addFavoriteKeyword(normalizedKeyword);
      debugPrint('favorite keyword added: $normalizedKeyword');
      ref.invalidate(userPreferenceProvider);
    } catch (error, stackTrace) {
      state = AsyncData(previous);
      debugPrint('favorite keyword add failed: $normalizedKeyword, $error');
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> removeKeyword(String keyword) async {
    final normalizedKeyword = keyword.trim();
    final previous = List<String>.from(state.valueOrNull ?? await future);
    final updated = previous
        .where((item) => item.trim() != normalizedKeyword)
        .toList();

    if (updated.length == previous.length) return;

    state = AsyncData(updated);

    try {
      final repository = await ref.read(
        userPreferenceRepositoryProvider.future,
      );
      await repository.removeFavoriteKeyword(normalizedKeyword);
      debugPrint('favorite keyword removed: $normalizedKeyword');
      ref.invalidate(userPreferenceProvider);
    } catch (error, stackTrace) {
      state = AsyncData(previous);
      debugPrint('favorite keyword remove failed: $normalizedKeyword, $error');
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

class FavoriteKeywordsNotifier extends StateNotifier<List<String>> {
  FavoriteKeywordsNotifier(this.ref) : super(const <String>[]) {
    _load();
  }

  final Ref ref;

  Future<void> _load() async {
    final repository = await ref.read(userPreferenceRepositoryProvider.future);
    final preference = await repository.getUserPreference();
    state = List<String>.from(preference?.favoriteKeywords ?? const <String>[]);
  }

  Future<void> addKeyword(String keyword) async {
    final normalizedKeyword = keyword.trim();
    if (normalizedKeyword.isEmpty) return;
    if (state.any((item) => item.trim() == normalizedKeyword)) return;

    final previous = List<String>.from(state);
    state = <String>[...previous, normalizedKeyword];

    try {
      final repository = await ref.read(
        userPreferenceRepositoryProvider.future,
      );
      await repository.addFavoriteKeyword(normalizedKeyword);
      debugPrint('favorite keyword added: $normalizedKeyword');
      ref.invalidate(userPreferenceProvider);
    } catch (error, stackTrace) {
      state = previous;
      debugPrint('favorite keyword add failed: $normalizedKeyword, $error');
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> removeKeyword(String keyword) async {
    final normalizedKeyword = keyword.trim();
    final previous = List<String>.from(state);
    final updated = previous
        .where((item) => item.trim() != normalizedKeyword)
        .toList();

    if (updated.length == previous.length) return;

    state = updated;

    try {
      final repository = await ref.read(
        userPreferenceRepositoryProvider.future,
      );
      await repository.removeFavoriteKeyword(normalizedKeyword);
      debugPrint('favorite keyword removed: $normalizedKeyword');
      ref.invalidate(userPreferenceProvider);
    } catch (error, stackTrace) {
      state = previous;
      debugPrint('favorite keyword remove failed: $normalizedKeyword, $error');
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

final favoriteKeywordsControllerProvider =
    StateNotifierProvider<FavoriteKeywordsNotifier, List<String>>(
      (ref) => FavoriteKeywordsNotifier(ref),
    );

/// 관심 키워드
final favoriteKeywordsProvider = Provider<List<String>>((ref) {
  return ref.watch(favoriteKeywordsControllerProvider);
});

/// 알림 레벨
final alertLevelProvider = FutureProvider<String>((ref) async {
  final preference = await ref.watch(userPreferenceProvider.future);
  return preference?.alertLevel ?? 'medium';
});

/// 테마 모드 상태
final themeModeProvider = FutureProvider<String>((ref) async {
  final preference = await ref.watch(userPreferenceProvider.future);
  return preference?.themeMode ?? UserPreference.themeModeSystem;
});

/// 관심 키워드 추가
final addFavoriteKeywordProvider = FutureProvider.autoDispose
    .family<void, String>((ref, keyword) async {
      await ref
          .read(favoriteKeywordsControllerProvider.notifier)
          .addKeyword(keyword);
    });

/// 관심 키워드 제거
final removeFavoriteKeywordProvider = FutureProvider.autoDispose
    .family<void, String>((ref, keyword) async {
      await ref
          .read(favoriteKeywordsControllerProvider.notifier)
          .removeKeyword(keyword);
    });

/// 알림 레벨 변경
final setAlertLevelProvider = FutureProvider.autoDispose.family<void, String>((
  ref,
  level,
) async {
  final repository = await ref.read(userPreferenceRepositoryProvider.future);
  await repository.setAlertLevel(level);

  // 상태 갱신
  ref.invalidate(userPreferenceProvider);
  ref.invalidate(alertLevelProvider);
});

/// 알림 활성화 토글
final toggleNotificationsProvider = FutureProvider.autoDispose
    .family<void, bool>((ref, enabled) async {
      final repository = await ref.read(
        userPreferenceRepositoryProvider.future,
      );
      await repository.toggleNotifications(enabled);

      final onboardingSeen =
          await AppOnboardingService.isNotificationOnboardingSeen();
      final alertSettings = await AlertSettings.load();
      await syncMarketAlerts(
        notificationsEnabled: enabled,
        onboardingSeen: onboardingSeen,
        marketHoursEnabled: alertSettings.marketHoursEnabled,
      );

      await syncBackgroundAlertTask(enabled: enabled && onboardingSeen);

      // 상태 갱신
      ref.invalidate(userPreferenceProvider);
    });

/// 테마 모드 변경
final setThemeModeProvider = FutureProvider.autoDispose.family<void, String>((
  ref,
  themeMode,
) async {
  final repository = await ref.read(userPreferenceRepositoryProvider.future);
  await repository.setThemeMode(themeMode);

  // 상태 갱신
  ref.invalidate(userPreferenceProvider);
  ref.invalidate(themeModeProvider);
});
