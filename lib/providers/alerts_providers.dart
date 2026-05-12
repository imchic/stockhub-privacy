import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/models/index.dart';
import '../services/notification_service.dart';
import 'app_onboarding_provider.dart';
import 'finance_providers.dart';
import 'repositories_provider.dart';
import 'user_preference_providers.dart';

// ─────────────────────────────────────────────
// SharedPreferences 기반 seen ID 영속화 헬퍼
// ─────────────────────────────────────────────
const _kSeenNewsKey = 'seen_news_ids_v1';
const _kSeenIndexKey = 'seen_index_keys_v1';

Future<Set<String>> _loadSeenSet(String prefKey) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList(prefKey)?.toSet() ?? {};
}

Future<void> _saveSeenSet(String prefKey, Set<String> ids) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(prefKey, ids.toList());
}

/// 날짜가 바뀌면 오래된 seen 항목 정리 (당일 키만 유지)
Set<String> _pruneOldKeys(Set<String> keys) {
  final today = DateTime.now();
  final todayStr =
      '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
  return keys.where((k) => k.contains(todayStr)).toSet();
}

/// 알림 관련 상태 프로바이더들

/// 알림 리스트
final alertsProvider = FutureProvider<List<Alert>>((ref) async {
  final repository = await ref.watch(alertRepositoryProvider.future);
  return repository.getAlerts();
});

/// 읽지 않은 알림만 조회
final unreadAlertsProvider = FutureProvider<List<Alert>>((ref) async {
  final repository = await ref.watch(alertRepositoryProvider.future);
  return repository.getAlerts(unreadOnly: true);
});

/// 읽지 않은 알림 개수
final unreadAlertCountProvider = FutureProvider<int>((ref) async {
  final repository = await ref.watch(alertRepositoryProvider.future);
  return repository.getUnreadCount();
});

/// 알림 마크 읽음
final markAlertAsReadProvider = FutureProvider.family<void, String>((
  ref,
  alertId,
) async {
  final repository = await ref.watch(alertRepositoryProvider.future);
  await repository.markAsRead(alertId);

  // 상태 갱신
  ref.invalidate(alertsProvider);
  ref.invalidate(unreadAlertsProvider);
  ref.invalidate(unreadAlertCountProvider);
});

/// 읽은 알림만 삭제
final deleteReadAlertsProvider = FutureProvider.autoDispose<void>((ref) async {
  final repository = await ref.read(alertRepositoryProvider.future);
  await repository.deleteReadAlerts();

  ref.invalidate(alertsProvider);
  ref.invalidate(unreadAlertsProvider);
  ref.invalidate(unreadAlertCountProvider);
});

/// 모든 알림 삭제
final deleteAllAlertsProvider = FutureProvider.autoDispose<void>((ref) async {
  final repository = await ref.read(alertRepositoryProvider.future);
  await repository.deleteAllAlerts();

  ref.invalidate(alertsProvider);
  ref.invalidate(unreadAlertsProvider);
  ref.invalidate(unreadAlertCountProvider);
});

/// 모든 알림 읽음으로 표시
final markAllAlertsAsReadProvider = FutureProvider.autoDispose<void>((
  ref,
) async {
  final repository = await ref.read(alertRepositoryProvider.future);
  await repository.markAllAsRead();

  // 상태 갱신
  ref.invalidate(alertsProvider);
  ref.invalidate(unreadAlertsProvider);
  ref.invalidate(unreadAlertCountProvider);
});

/// 알림 삭제
final deleteAlertProvider = FutureProvider.family<void, String>((
  ref,
  alertId,
) async {
  final repository = await ref.watch(alertRepositoryProvider.future);
  await repository.deleteAlert(alertId);

  // 상태 갱신
  ref.invalidate(alertsProvider);
  ref.invalidate(unreadAlertsProvider);
  ref.invalidate(unreadAlertCountProvider);
});

/// 금융 관련 알림만 조회
final financeAlertsProvider = FutureProvider<List<Alert>>((ref) async {
  final allAlerts = await ref.watch(alertsProvider.future);
  return allAlerts
      .where((alert) => alert.alertType.startsWith('finance_'))
      .toList();
});

/// 읽지 않은 금융 알림
final unreadFinanceAlertsProvider = FutureProvider<List<Alert>>((ref) async {
  final financeAlerts = await ref.watch(financeAlertsProvider.future);
  return financeAlerts.where((alert) => !alert.isRead).toList();
});

/// 급등 알림만
final surgeAlertsProvider = FutureProvider<List<Alert>>((ref) async {
  final financeAlerts = await ref.watch(financeAlertsProvider.future);
  return financeAlerts
      .where((alert) => alert.alertType == 'finance_surge')
      .toList();
});

/// 폭락 알림만
final fallingAlertsProvider = FutureProvider<List<Alert>>((ref) async {
  final financeAlerts = await ref.watch(financeAlertsProvider.future);
  return financeAlerts
      .where((alert) => alert.alertType == 'finance_fall')
      .toList();
});

/// 경제 뉴스 알림만 (alertType 기준 — 하위 호환용)
final economicAlertsProvider = FutureProvider<List<Alert>>((ref) async {
  final financeAlerts = await ref.watch(financeAlertsProvider.future);
  return financeAlerts
      .where((alert) => alert.alertType == 'finance_economic')
      .toList();
});

// ── 탭별 키워드 필터 providers ─────────────────────────────────

bool _alertContains(Alert a, List<String> keywords) {
  final text = '${a.title} ${a.message}';
  return keywords.any((k) => text.contains(k));
}

/// alertLevel 문자열 → minImportanceLevel 정수 변환
/// 'low': 긴급만(4+), 'medium': 주요(3+), 'high': 모든 알림(1+)
int _alertLevelToMinImportance(String? alertLevel) {
  return switch (alertLevel) {
    'low' => 4,
    'high' => 1,
    _ => 3,
  };
}

/// 전쟁·지정학 충돌 관련 알림
final warAlertsProvider = FutureProvider<List<Alert>>((ref) async {
  final all = await ref.watch(alertsProvider.future);
  const kws = [
    '전쟁',
    '전투',
    '공습',
    '폭격',
    '미사일',
    '포격',
    '교전',
    '이스라엘',
    '하마스',
    '가자',
    '이란',
    '헤즈볼라',
    '중동',
    '우크라이나',
    '러시아',
    '분쟁',
    '확전',
    '휴전',
    '군사',
    '병력',
  ];
  return all.where((a) => _alertContains(a, kws)).toList();
});

/// 속보 알림만 (alertType == 'breaking_news')
/// keyword_match 알림은 별도 키워드 탭에서 표시
final breakingNewsAlertsProvider = FutureProvider<List<Alert>>((ref) async {
  final all = await ref.watch(alertsProvider.future);
  return all.where((a) => a.alertType == 'breaking_news').toList();
});

/// 코스피 관련 알림
final kospiAlertsProvider = FutureProvider<List<Alert>>((ref) async {
  final all = await ref.watch(alertsProvider.future);
  const kws = ['코스피', 'KOSPI', 'kospi', '유가증권', '코스피지수'];
  return all.where((a) => _alertContains(a, kws)).toList();
});

/// 코스닥 관련 알림
final kosdaqAlertsProvider = FutureProvider<List<Alert>>((ref) async {
  final all = await ref.watch(alertsProvider.future);
  const kws = ['코스닥', 'KOSDAQ', 'kosdaq', '코스닥지수'];
  return all.where((a) => _alertContains(a, kws)).toList();
});

/// 나스닥 관련 알림
final nasdaqAlertsProvider = FutureProvider<List<Alert>>((ref) async {
  final all = await ref.watch(alertsProvider.future);
  const kws = [
    '나스닥',
    'nasdaq',
    'NASDAQ',
    'S&P',
    's&p',
    '다우',
    '뉴욕증시',
    '미국증시',
    '월가',
  ];
  return all.where((a) => _alertContains(a, kws)).toList();
});

/// 코인(암호화폐) 관련 알림
final coinAlertsProvider = FutureProvider<List<Alert>>((ref) async {
  final all = await ref.watch(alertsProvider.future);
  const kws = [
    '비트코인',
    '이더리움',
    '코인',
    'BTC',
    'ETH',
    '암호화폐',
    '가상화폐',
    '솔라나',
    '리플',
    'XRP',
    'SOL',
  ];
  return all.where((a) => _alertContains(a, kws)).toList();
});

/// 사용자 키워드 매칭 알림만
final keywordMatchAlertsProvider = FutureProvider<List<Alert>>((ref) async {
  final all = await ref.watch(alertsProvider.future);
  return all.where((a) => a.alertType == 'keyword_match').toList();
});

/// 경제·지정학 관련 알림
final economyTabAlertsProvider = FutureProvider<List<Alert>>((ref) async {
  final all = await ref.watch(alertsProvider.future);
  const kws = [
    '금리',
    '연준',
    '한국은행',
    '관세',
    '무역',
    '트럼프',
    '이란',
    '이스라엘',
    '중동',
    'GDP',
    '인플레이션',
    '환율',
    '경기',
    '재정',
    '제재',
    '긴축',
  ];
  return all.where((a) => _alertContains(a, kws)).toList();
});

// ─────────────────────────────────────────────
// 알림 설정
// ─────────────────────────────────────────────

/// 알림 설정 StateNotifier
class AlertSettingsNotifier extends StateNotifier<AlertSettings> {
  late final Future<void> _loadFuture;
  final Ref ref;

  AlertSettingsNotifier(this.ref) : super(const AlertSettings()) {
    _loadFuture = _load();
  }

  Future<void> _load() async {
    state = await AlertSettings.load();
  }

  Future<void> toggleBreakingNews(bool value) async {
    await _loadFuture;
    state = state.copyWith(breakingNewsEnabled: value);
    await state.save();
  }

  Future<void> toggleKeywordAlerts(bool value) async {
    await _loadFuture;
    state = state.copyWith(keywordAlertsEnabled: value);
    await state.save();
  }

  Future<void> setMinImportanceLevel(int level) async {
    await _loadFuture;
    state = state.copyWith(minImportanceLevel: level);
    await state.save();
  }

  Future<void> toggleSurgeAlerts(bool value) async {
    await _loadFuture;
    state = state.copyWith(surgeAlertsEnabled: value);
    await state.save();
  }

  Future<void> toggleFallAlerts(bool value) async {
    await _loadFuture;
    state = state.copyWith(fallAlertsEnabled: value);
    await state.save();
  }

  Future<void> setSurgeThreshold(double threshold) async {
    await _loadFuture;
    state = state.copyWith(surgeThreshold: threshold);
    await state.save();
  }

  Future<void> setFallThreshold(double threshold) async {
    await _loadFuture;
    state = state.copyWith(fallThreshold: threshold);
    await state.save();
  }

  Future<void> toggleMarketHours(bool value) async {
    await _loadFuture;

    if (value) {
      final notificationsGranted =
          await NotificationService.requestNotificationsPermission();
      if (!notificationsGranted) {
        return;
      }

      final exactAlarmGranted =
          await NotificationService.requestExactAlarmsPermission();
      if (!exactAlarmGranted) {
        return;
      }
    }

    state = state.copyWith(marketHoursEnabled: value);
    await state.save();
    final notificationsEnabled =
        ref.read(userPreferenceProvider).valueOrNull?.notificationsEnabled ??
        false;
    final scheduled = await syncMarketAlerts(
      notificationsEnabled: notificationsEnabled,
      onboardingSeen: true,
      marketHoursEnabled: value,
    );
    if (value && notificationsEnabled && !scheduled) {
      state = state.copyWith(marketHoursEnabled: false);
      await state.save();
    }
  }
}

final alertSettingsProvider =
    StateNotifierProvider<AlertSettingsNotifier, AlertSettings>(
      (ref) => AlertSettingsNotifier(ref),
    );

// ─────────────────────────────────────────────
// 속보 + 키워드 감시 — 새 Alert 발생 시 스트림으로 방출
// ─────────────────────────────────────────────

/// 60초마다 뉴스를 확인하고 새 속보/키워드 알림을 Alert 스트림으로 방출
final breakingNewsWatcherProvider = StreamProvider<Alert>((ref) async* {
  // 앱 시작 후 5초 대기 (초기 뉴스 로딩 완료 후 감시 시작)
  await Future.delayed(const Duration(seconds: 5));

  const uuid = Uuid();
  final repo = await ref.read(alertRepositoryProvider.future);
  final newsRepo = await ref.read(newsRepositoryProvider.future);
  // SharedPreferences에서 이미 처리한 뉴스 ID 로드 (재시작 후 중복 방지)
  var seenIds = await _loadSeenSet(_kSeenNewsKey);
  var isFirstBaselinePending = seenIds.isEmpty;

  while (true) {
    final settings = ref.read(alertSettingsProvider);
    final userPref = ref.read(userPreferenceProvider).valueOrNull;
    final onboardingSeen =
        ref.read(notificationOnboardingSeenProvider).valueOrNull ?? false;
    final notificationsEnabled = userPref?.notificationsEnabled ?? false;

    // 온보딩 전이거나 알림이 비활성화되어 있으면 이번 루프 스킵
    if (!onboardingSeen || !notificationsEnabled) {
      await Future.delayed(const Duration(seconds: 60));
      continue;
    }

    // alertLevel → minImportanceLevel 변환
    final minImportance = _alertLevelToMinImportance(userPref?.alertLevel);

    // 설정 화면 관심 키워드를 키워드 알림에 사용
    final favKeywords = userPref?.favoriteKeywords ?? [];
    final allKeywords = favKeywords;

    final shouldWatch =
        settings.breakingNewsEnabled ||
        (settings.keywordAlertsEnabled && allKeywords.isNotEmpty);

    if (shouldWatch) {
      try {
        // UI가 갱신한 로컬 캐시를 그대로 읽음 → API 호출 없음, provider 재구독 없음
        final freshNews = newsRepo.getCachedNews();
        final now = DateTime.now();
        final allNews = freshNews
            .where((n) => n.stockRelevanceScore >= 0.1)
            .toList();
        final newSeenIds = <String>{...seenIds};

        // 당일 00:00 이후 발행된 뉴스만 알림 생성 (옛날 뉴스 알림 방지)
        final todayMidnight = DateTime(now.year, now.month, now.day);

        // 첫 진입에서는 현재 보이는 기사들을 기준선으로만 저장하고,
        // 이후 새로 유입된 기사부터 알림을 보낸다.
        if (isFirstBaselinePending) {
          newSeenIds.addAll(
            allNews
                .where((news) => !news.publishedAt.isBefore(todayMidnight))
                .map((news) => news.id),
          );
          seenIds = newSeenIds;
          isFirstBaselinePending = false;
          await _saveSeenSet(_kSeenNewsKey, seenIds);
          await Future.delayed(const Duration(seconds: 60));
          continue;
        }

        for (final news in allNews) {
          if (seenIds.contains(news.id)) continue;
          // 오늘 이전 기사는 알림 생략
          if (news.publishedAt.isBefore(todayMidnight)) continue;

          String? matchedKeyword;
          bool isBreaking = false;

          // 속보 조건 체크 (alertLevel 기반 minImportance 사용)
          if (settings.breakingNewsEnabled &&
              news.importanceLevel >= minImportance) {
            isBreaking = true;
          }

          // 키워드 매칭 체크 (설정 화면 관심 키워드 포함)
          if (settings.keywordAlertsEnabled && allKeywords.isNotEmpty) {
            final text = '${news.title} ${news.description}'.toLowerCase();
            for (final kw in allKeywords) {
              if (text.contains(kw.toLowerCase())) {
                matchedKeyword = kw;
                break;
              }
            }
          }

          if (!isBreaking && matchedKeyword == null) continue;

          // ── 뉴스 내용 기반 alertType 분류 ──────────────────
          // 키워드 매칭 알림은 keyword_match 유지
          // 속보는 뉴스 내용을 분석해 finance_surge / finance_fall /
          // finance_economic / breaking_news 중 하나로 분류
          String alertType;
          if (matchedKeyword != null) {
            alertType = 'keyword_match';
          } else {
            final text = '${news.title} ${news.description}'.toLowerCase();

            // 급등 시그널
            const surgeKws = [
              '급등',
              '폭등',
              '급상승',
              '상한가',
              '최고가',
              '신고가',
              '강세',
              '호재',
              '반등',
              '급반등',
              '대폭 상승',
              '급격히 올',
              'surged',
              'rallied',
              'soared',
              'jumped',
              'skyrocketed',
            ];
            // 폭락 시그널
            const fallKws = [
              '폭락',
              '급락',
              '급하락',
              '하한가',
              '연저가',
              '최저가',
              '약세',
              '악재',
              '급격히 하락',
              '대폭 하락',
              '투매',
              'plunged',
              'crashed',
              'slumped',
              'tumbled',
              'collapsed',
            ];
            // 경제 시그널
            const econKws = [
              '금리',
              '기준금리',
              '연준',
              'fed',
              '인플레이션',
              '물가',
              'cpi',
              'gdp',
              '환율',
              '무역',
              '관세',
              '재정',
              '긴축',
              '경기침체',
              '경기부양',
              '재정정책',
              '통화정책',
            ];

            final hasSurge = surgeKws.any((k) => text.contains(k));
            final hasFall = fallKws.any((k) => text.contains(k));
            final hasEcon = econKws.any((k) => text.contains(k));

            if (hasSurge && !hasFall) {
              alertType = 'finance_surge';
            } else if (hasFall && !hasSurge) {
              alertType = 'finance_fall';
            } else if (hasFall && hasSurge) {
              // 양쪽 다 있는 경우 감성 점수로 판단
              alertType = news.sentimentScore >= 0
                  ? 'finance_surge'
                  : 'finance_fall';
            } else if (hasEcon) {
              alertType = 'finance_economic';
            } else {
              alertType = 'breaking_news';
            }
          }
          // ────────────────────────────────────────────────────
          final alert = Alert(
            id: 'auto_${uuid.v4()}',
            keyword: matchedKeyword ?? '속보',
            region: '전체',
            title: news.title, // 이모지 없이 순수 헤드라인만 저장
            message: news.description.isNotEmpty
                ? news.description
                : news.title,
            newsUrl: news.newsUrl.isNotEmpty ? news.newsUrl : null,
            riskLevel: news.importanceLevel,
            alertType: alertType,
            createdAt: news.publishedAt,
            isRead: false,
            changeRate: news.sentimentScore,
            currentMentionCount: 1,
            previousMentionCount: 0,
          );

          await repo.addAlert(alert);
          newSeenIds.add(news.id);

          // providers 갱신
          ref.invalidate(alertsProvider);
          ref.invalidate(unreadAlertCountProvider);
          ref.invalidate(unreadAlertsProvider);

          yield alert;
        }

        seenIds = newSeenIds;
        // 영속 저장 (앱 재시작 후 중복 방지)
        await _saveSeenSet(_kSeenNewsKey, seenIds);
      } catch (_) {
        // 에러는 무시하고 계속 감시
      }
    }

    await Future.delayed(const Duration(seconds: 60));
  }
});

// ─────────────────────────────────────────────
// 시장 지수 급등/폭락 감시 — 60초마다 변화율 체크
// ─────────────────────────────────────────────

/// 60초마다 시장 지수를 확인하고 급등/폭락 알림을 방출
final marketSurgeWatcherProvider = StreamProvider<Alert>((ref) async* {
  // 속보 와처와 겹치지 않도록 8초 후 시작
  await Future.delayed(const Duration(seconds: 8));

  const uuid = Uuid();
  final repo = await ref.read(alertRepositoryProvider.future);
  // SharedPreferences에서 이미 처리한 지수 키 로드 + 오늘 것만 유지
  var seenKeys = _pruneOldKeys(await _loadSeenSet(_kSeenIndexKey));
  var isFirstBaselinePending = seenKeys.isEmpty;

  while (true) {
    final settings = ref.read(alertSettingsProvider);
    final onboardingSeen =
        ref.read(notificationOnboardingSeenProvider).valueOrNull ?? false;
    final notificationsEnabled =
        ref.read(userPreferenceProvider).valueOrNull?.notificationsEnabled ??
        false;
    final shouldWatch =
        onboardingSeen &&
        notificationsEnabled &&
        (settings.surgeAlertsEnabled || settings.fallAlertsEnabled);

    if (shouldWatch) {
      try {
        final indices = await ref.read(marketIndicesProvider.future);
        final newSeenKeys = <String>{...seenKeys};
        final today = DateTime.now();
        final dateStr =
            '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

        if (isFirstBaselinePending) {
          for (final index in indices) {
            final isSurge =
                settings.surgeAlertsEnabled &&
                index.change >= settings.surgeThreshold;
            final isFall =
                settings.fallAlertsEnabled &&
                index.change <= -settings.fallThreshold;

            if (!isSurge && !isFall) continue;

            final direction = isSurge ? 'surge' : 'fall';
            newSeenKeys.add('${index.symbol}_${dateStr}_$direction');
          }

          seenKeys = newSeenKeys;
          isFirstBaselinePending = false;
          await _saveSeenSet(_kSeenIndexKey, seenKeys);
          await Future.delayed(const Duration(seconds: 60));
          continue;
        }

        for (final index in indices) {
          final isSurge =
              settings.surgeAlertsEnabled &&
              index.change >= settings.surgeThreshold;
          final isFall =
              settings.fallAlertsEnabled &&
              index.change <= -settings.fallThreshold;

          if (!isSurge && !isFall) continue;

          final direction = isSurge ? 'surge' : 'fall';
          final key = '${index.symbol}_${dateStr}_$direction';
          if (seenKeys.contains(key)) continue;

          final alertType = isSurge ? 'finance_surge' : 'finance_fall';
          final changeStr = index.formattedChange;
          final emoji = isSurge ? '📈' : '📉';
          final title =
              '$emoji ${index.name} $changeStr ${isSurge ? '급등' : '폭락'}';
          final message =
              '${index.name}이(가) $changeStr 변동했습니다. 현재가: ${index.formattedPrice} ${index.currency}';

          final alert = Alert(
            id: 'idx_${uuid.v4()}',
            keyword: isSurge ? '급등' : '폭락',
            region: '전체',
            title: title,
            message: message,
            riskLevel: isSurge ? 4 : 5,
            alertType: alertType,
            createdAt: DateTime.now(),
            isRead: false,
            changeRate: index.change,
            currentMentionCount: 1,
            previousMentionCount: 0,
          );

          await repo.addAlert(alert);
          newSeenKeys.add(key);

          ref.invalidate(alertsProvider);
          ref.invalidate(unreadAlertCountProvider);
          ref.invalidate(unreadAlertsProvider);

          yield alert;
        }

        seenKeys = newSeenKeys;
        // 영속 저장
        await _saveSeenSet(_kSeenIndexKey, seenKeys);
      } catch (_) {
        // 에러는 무시하고 계속 감시
      }
    }

    await Future.delayed(const Duration(seconds: 60));
  }
});
