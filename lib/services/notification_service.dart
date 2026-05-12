import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/standalone.dart' as tz;

import '../data/models/index.dart';
import 'market_calendar_service.dart';

Future<bool> syncMarketAlerts({
  required bool notificationsEnabled,
  required bool onboardingSeen,
  required bool marketHoursEnabled,
}) async {
  final shouldSchedule =
      notificationsEnabled && onboardingSeen && marketHoursEnabled;
  if (!shouldSchedule) {
    await NotificationService.cancelMarketAlerts();
    return false;
  }

  return NotificationService.scheduleMarketAlerts();
}

/// 로컬 푸시 알림 서비스
///
/// 사용법:
///   1. `main()` 에서 `await NotificationService.init()` 호출
///   2. 새 속보/급등·폭락 이벤트 발생 시 `show(alert)` 호출
class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _androidRecoveryChannel = MethodChannel(
    'com.imchic.stockhub/notification_cache',
  );
  static const _marketHoursTestNotificationId = 39999991;
  static const _marketAlertsScheduledKey = 'market_alerts_scheduled';
  static const _marketAlertNotificationIdsKey = 'market_alert_notification_ids';
  static const _deepLinkDedupWindow = Duration(seconds: 2);

  // ─── 딥링크 스트림 ─────────────────────────────────
  /// 알림 탭 시 payload 스트림. HomeScreen에서 구독하여 탭 전환 / 웹뷰 열기에 사용
  static final _deepLinkController = StreamController<String>.broadcast();
  static String? _lastDeepLinkSignature;
  static DateTime? _lastDeepLinkDispatchedAt;
  static Stream<String> get deepLinkStream => _deepLinkController.stream;

  static void _dispatchDeepLink(
    String payload, {
    int? notificationId,
    String? actionId,
  }) {
    if (payload.isEmpty) {
      return;
    }

    final signature = '${notificationId ?? -1}|${actionId ?? ''}|$payload';
    final now = DateTime.now();
    final isDuplicate =
        _lastDeepLinkSignature == signature &&
        _lastDeepLinkDispatchedAt != null &&
        now.difference(_lastDeepLinkDispatchedAt!) <= _deepLinkDedupWindow;

    if (isDuplicate) {
      return;
    }

    _lastDeepLinkSignature = signature;
    _lastDeepLinkDispatchedAt = now;
    _deepLinkController.add(payload);
  }

  // ─── Android 채널 ─────────────────────────────────
  static const _channelId = 'PinStock_breaking';
  static const _channelName = '속보 알림';
  static const _channelDesc = 'PinStock 속보 및 시장 급변 알림';

  static const _androidChannel = AndroidNotificationChannel(
    _channelId,
    _channelName,
    description: _channelDesc,
    importance: Importance.high,
  );

  // ─── 장 시작/마감 채널 ──────────────────────────────
  static const _marketChannelId = 'PinStock_market_v2';
  static const _marketChannelName = '장 시작/마감 알림';
  static const _marketChannelDesc = '코스피·NXT 주요 장 시작 및 마감 사전 알림';
  static const _legacyMarketAlertIds = <int>[
    1001,
    1002,
    1003,
    1004,
    1005,
    1006,
    1007,
    1008,
    1009,
    1010,
    1011,
    1012,
    1013,
    1014,
    1015,
  ];

  static const _marketChannel = AndroidNotificationChannel(
    _marketChannelId,
    _marketChannelName,
    description: _marketChannelDesc,
    importance: Importance.high,
  );

  // ─── 키워드 채널 ──────────────────────────────────
  static const _keywordChannelId = 'PinStock_keyword';
  static const _keywordChannelName = '키워드 알림';
  static const _keywordChannelDesc = '등록한 키워드가 뉴스에 포함될 때 알림';

  static const _keywordChannel = AndroidNotificationChannel(
    _keywordChannelId,
    _keywordChannelName,
    description: _keywordChannelDesc,
  );

  // ─── 경제일정 채널 ───────────────────────────────
  static const _economicChannelId = 'PinStock_economic_calendar';
  static const _economicChannelName = '경제일정 알림';
  static const _economicChannelDesc = '중요 경제지표 발표 전 미리 알려주는 알림';
  static const _economicAlertIdsKey = 'economic_calendar_alert_ids';

  static const _economicChannel = AndroidNotificationChannel(
    _economicChannelId,
    _economicChannelName,
    description: _economicChannelDesc,
    importance: Importance.high,
  );

  // ─── 초기화 ───────────────────────────────────────
  static Future<void> init() async {
    tz_data.initializeTimeZones();
    // Android 채널 생성 (Android 8+ 필수)
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_androidChannel);

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_marketChannel);

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_keywordChannel);

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_economicChannel);

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _dispatchDeepLink(
            payload,
            notificationId: response.id,
            actionId: response.actionId,
          );
        }
      },
    );

    // 앱이 종료된 상태에서 알림 탭으로 시작된 경우 처리
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final payload = launchDetails!.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        // HomeScreen이 준비된 후 emit 되도록 지연
        Future.delayed(const Duration(milliseconds: 500), () {
          _dispatchDeepLink(
            payload,
            notificationId: launchDetails.notificationResponse?.id,
            actionId: launchDetails.notificationResponse?.actionId,
          );
        });
      }
    }
  }

  static Future<bool> requestNotificationsPermission() async {
    if (Platform.isIOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      return granted ?? false;
    }

    if (Platform.isMacOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      return granted ?? false;
    }

    if (Platform.isAndroid) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();

      return granted ?? false;
    }

    return true;
  }

  static Future<bool> requestExactAlarmsPermission() async {
    if (!Platform.isAndroid) {
      return true;
    }

    final granted = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestExactAlarmsPermission();

    return granted ?? false;
  }

  static Future<bool> canScheduleExactAlarms() async {
    if (!Platform.isAndroid) {
      return true;
    }

    final granted = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.canScheduleExactNotifications();

    return granted ?? false;
  }

  static Future<bool> scheduleMarketHoursTestNotification({
    Duration delay = const Duration(minutes: 1),
  }) async {
    final notificationsGranted = await requestNotificationsPermission();
    if (!notificationsGranted) {
      debugPrint('장 시작/마감 테스트 알림 예약 중단: 알림 권한이 없습니다.');
      return false;
    }

    if (Platform.isAndroid) {
      final exactGranted = await requestExactAlarmsPermission();
      if (!exactGranted) {
        debugPrint('장 시작/마감 테스트 알림 예약 중단: exact alarm 권한이 없습니다.');
        return false;
      }
    }

    final seoul = tz.getLocation('Asia/Seoul');
    final scheduledAt = tz.TZDateTime.now(seoul).add(delay);

    const notifDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _marketChannelId,
        _marketChannelName,
        channelDescription: _marketChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        category: AndroidNotificationCategory.reminder,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

    await _plugin.cancel(_marketHoursTestNotificationId);
    await _plugin.zonedSchedule(
      _marketHoursTestNotificationId,
      '장 시작/마감 테스트용 알림',
      '1분 뒤 장 시작/마감 알림 수신 여부를 확인하는 임시 테스트입니다.',
      scheduledAt,
      notifDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'market_hours_test_notification',
    );

    debugPrint('장 시작/마감 테스트 알림 예약 완료: ${scheduledAt.toIso8601String()}');
    return true;
  }

  static Future<bool> requestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) {
      return true;
    }

    final status = await Permission.ignoreBatteryOptimizations.status;
    if (status.isGranted) {
      return true;
    }

    final result = await Permission.ignoreBatteryOptimizations.request();
    return result.isGranted;
  }

  // ─── 장 시작/마감 예약 알림 ───────────────────────────

  static bool _isCorruptedScheduleCacheError(Object error) {
    final errorText = error.toString();
    return error is PlatformException &&
        (error.message?.contains('Missing type parameter') ??
            false ||
                error.details?.toString().contains('Missing type parameter') ==
                    true ||
                errorText.contains('Missing type parameter'));
  }

  static Future<bool> _wasMarketAlertsScheduled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_marketAlertsScheduledKey) ?? false;
  }

  static Future<void> _setMarketAlertsScheduled(bool scheduled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_marketAlertsScheduledKey, scheduled);
  }

  static Future<Set<int>> _getScheduledMarketAlertIds() async {
    final prefs = await SharedPreferences.getInstance();
    final values =
        prefs.getStringList(_marketAlertNotificationIdsKey) ?? const <String>[];
    return values.map(int.parse).toSet();
  }

  static Future<void> _setScheduledMarketAlertIds(Set<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _marketAlertNotificationIdsKey,
      ids.map((id) => id.toString()).toList()..sort(),
    );
  }

  static Future<void> _clearAndroidScheduledNotificationsCache() async {
    if (!Platform.isAndroid) {
      return;
    }

    await _androidRecoveryChannel.invokeMethod<void>(
      'clearScheduledNotificationsCache',
    );
  }

  static Future<void> _cancelNotificationIdsNatively(Iterable<int> ids) async {
    if (!Platform.isAndroid) {
      return;
    }

    await _androidRecoveryChannel.invokeMethod<void>(
      'cancelScheduledNotificationIds',
      <String, Object>{'ids': ids.toList()},
    );
  }

  static int _marketAlertNotificationId(DateTime date, int slot) {
    final compactDate =
        (date.year - 2000) * 10000 + date.month * 100 + date.day;
    return 30000000 + compactDate * 100 + slot;
  }

  static Future<bool> _scheduleMarketAlert({
    required int id,
    required String title,
    required String body,
    required tz.Location location,
    required tz.TZDateTime now,
    required DateTime date,
    required int hour,
    required int minute,
    required NotificationDetails details,
  }) async {
    var scheduledAt = tz.TZDateTime(
      location,
      date.year,
      date.month,
      date.day,
      hour,
      minute,
    );

    final isSameMinuteToday =
        date.year == now.year &&
        date.month == now.month &&
        date.day == now.day &&
        now.hour == hour &&
        now.minute == minute &&
        now.second < 55;

    if (isSameMinuteToday) {
      scheduledAt = now.add(const Duration(seconds: 3));
    }

    if (!scheduledAt.isAfter(now.add(const Duration(seconds: 2)))) {
      return false;
    }

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduledAt,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    return true;
  }

  static Future<void> _scheduleMarketAlertDefinition({
    required _MarketAlertDefinition definition,
    required DateTime date,
    required tz.Location location,
    required tz.TZDateTime now,
    required NotificationDetails details,
    required Set<int> scheduledIds,
  }) async {
    final notificationId = _marketAlertNotificationId(date, definition.slot);
    final didSchedule = await _scheduleMarketAlert(
      id: notificationId,
      title: definition.title,
      body: definition.body,
      location: location,
      now: now,
      date: date,
      hour: definition.hour,
      minute: definition.minute,
      details: details,
    );
    if (didSchedule) {
      scheduledIds.add(notificationId);
    }
  }

  static Future<void> _runWithRecoveredAndroidScheduleCache(
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on PlatformException catch (error) {
      if (!_isCorruptedScheduleCacheError(error) || !Platform.isAndroid) {
        rethrow;
      }

      await _clearAndroidScheduledNotificationsCache();
      await action();
    }
  }

  static const _marketAlertDefinitions = <_MarketAlertDefinition>[
    _MarketAlertDefinition(
      slot: 1,
      hour: 7,
      minute: 55,
      title: 'NXT 장 시작 5분 전',
      body: 'NXT 프리마켓이 5분 뒤 시작됩니다.',
    ),
    _MarketAlertDefinition(
      slot: 2,
      hour: 7,
      minute: 59,
      title: 'NXT 장 시작 1분 전',
      body: 'NXT 프리마켓이 1분 뒤 시작됩니다.',
    ),
    _MarketAlertDefinition(
      slot: 3,
      hour: 8,
      minute: 0,
      title: 'NXT 장 시작',
      body: 'NXT 프리마켓이 시작됐습니다.',
    ),
    _MarketAlertDefinition(
      slot: 4,
      hour: 8,
      minute: 55,
      title: '코스피 개장 5분 전',
      body: '코스피 정규장이 5분 뒤 시작됩니다.',
    ),
    _MarketAlertDefinition(
      slot: 5,
      hour: 8,
      minute: 59,
      title: '코스피 개장 1분 전',
      body: '코스피 정규장이 1분 뒤 시작됩니다.',
    ),
    _MarketAlertDefinition(
      slot: 6,
      hour: 9,
      minute: 0,
      title: '코스피 개장',
      body: '코스피 정규장이 시작됐습니다.',
    ),
    _MarketAlertDefinition(
      slot: 7,
      hour: 15,
      minute: 25,
      title: '코스피 마감 5분 전',
      body: '코스피 정규장이 5분 뒤 마감됩니다.',
    ),
    _MarketAlertDefinition(
      slot: 8,
      hour: 15,
      minute: 29,
      title: '코스피 마감 1분 전',
      body: '코스피 정규장이 1분 뒤 마감됩니다.',
    ),
    _MarketAlertDefinition(
      slot: 9,
      hour: 15,
      minute: 30,
      title: '코스피 마감',
      body: '코스피 정규장이 마감됐습니다.',
    ),
    _MarketAlertDefinition(
      slot: 10,
      hour: 15,
      minute: 25,
      title: 'NXT 종가매매 시작 5분 전',
      body: 'NXT 종가매매가 5분 뒤 시작됩니다.',
    ),
    _MarketAlertDefinition(
      slot: 11,
      hour: 15,
      minute: 29,
      title: 'NXT 종가매매 시작 1분 전',
      body: 'NXT 종가매매가 1분 뒤 시작됩니다.',
    ),
    _MarketAlertDefinition(
      slot: 12,
      hour: 15,
      minute: 30,
      title: 'NXT 종가매매 시작',
      body: 'NXT 종가매매가 시작됐습니다.',
    ),
    _MarketAlertDefinition(
      slot: 13,
      hour: 16,
      minute: 55,
      title: 'NXT 애프터마켓 시작 5분 전',
      body: 'NXT 애프터마켓이 5분 뒤 시작됩니다.',
    ),
    _MarketAlertDefinition(
      slot: 14,
      hour: 16,
      minute: 59,
      title: 'NXT 애프터마켓 시작 1분 전',
      body: 'NXT 애프터마켓이 1분 뒤 시작됩니다.',
    ),
    _MarketAlertDefinition(
      slot: 15,
      hour: 17,
      minute: 0,
      title: 'NXT 애프터마켓 시작',
      body: 'NXT 애프터마켓이 시작됐습니다.',
    ),
  ];
  static const _androidExactAlarmHeadroom = 80;

  static int get _androidMarketAlertTradingDayLimit {
    const availableSlots = 500 - _androidExactAlarmHeadroom;
    return availableSlots ~/ _marketAlertDefinitions.length;
  }

  /// NXT와 코스피 주요 장 시작·마감 알림을 거래일에만 예약
  static Future<bool> scheduleMarketAlerts() async {
    if (!await canScheduleExactAlarms()) {
      await _setScheduledMarketAlertIds(<int>{});
      await _setMarketAlertsScheduled(false);
      return false;
    }

    try {
      await cancelMarketAlerts();

      await _runWithRecoveredAndroidScheduleCache(() async {
        final seoul = tz.getLocation('Asia/Seoul');
        final now = tz.TZDateTime.now(seoul);
        final scheduledIds = <int>{};

        const notifDetails = NotificationDetails(
          android: AndroidNotificationDetails(
            _marketChannelId,
            _marketChannelName,
            channelDescription: _marketChannelDesc,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        );

        final tradingDays = MarketCalendarService.upcomingKoreanTradingDays(
          startDate: now,
        ).take(Platform.isAndroid ? _androidMarketAlertTradingDayLimit : 120);
        for (final tradingDay in tradingDays) {
          for (final definition in _marketAlertDefinitions) {
            await _scheduleMarketAlertDefinition(
              definition: definition,
              date: tradingDay,
              location: seoul,
              now: now,
              details: notifDetails,
              scheduledIds: scheduledIds,
            );
          }
        }

        await _setScheduledMarketAlertIds(scheduledIds);
        await _setMarketAlertsScheduled(scheduledIds.isNotEmpty);
      });
      return await _wasMarketAlertsScheduled();
    } catch (error, stackTrace) {
      debugPrint('Failed to schedule market alerts: $error');
      debugPrintStack(stackTrace: stackTrace);
      await _setScheduledMarketAlertIds(<int>{});
      await _setMarketAlertsScheduled(false);
      // 스케줄 실패는 앱 구동에 영향 없음
      return false;
    }
  }

  /// 장 시작/마감 예약 알림 취소
  static Future<void> cancelMarketAlerts() async {
    final storedIds = await _getScheduledMarketAlertIds();
    final targetIds = {..._legacyMarketAlertIds, ...storedIds};

    try {
      for (final id in targetIds) {
        await _plugin.cancel(id);
      }
    } on PlatformException catch (error) {
      if (!_isCorruptedScheduleCacheError(error) || !Platform.isAndroid) {
        rethrow;
      }

      await _clearAndroidScheduledNotificationsCache();
      await _cancelNotificationIdsNatively(targetIds);
    } finally {
      await _setScheduledMarketAlertIds(<int>{});
      await _setMarketAlertsScheduled(false);
    }
  }

  static Future<Set<String>> getScheduledEconomicAlertEventIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_economicAlertIdsKey) ?? []).toSet();
  }

  static Future<void> _setScheduledEconomicAlertEventIds(
    Set<String> ids,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_economicAlertIdsKey, ids.toList()..sort());
  }

  static int _economicAlertNotificationId(String eventId) {
    return 2000000 + (eventId.hashCode & 0x0FFFFFFF);
  }

  static String _formatEconomicEventTime(DateTime dateTime) {
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }

  static String _formatEconomicCountry(String country) {
    final normalized = country.toLowerCase();
    if (normalized.contains('united states') || normalized == 'us') {
      return '미국';
    }
    if (normalized.contains('korea')) {
      return '한국';
    }
    return country;
  }

  static Future<int> scheduleEconomicEventAlerts(
    List<EconomicCalendarEvent> events, {
    Duration leadTime = const Duration(minutes: 30),
  }) async {
    await cancelEconomicEventAlerts();

    if (events.isEmpty) {
      return 0;
    }

    final location = tz.getLocation('Asia/Seoul');
    final now = tz.TZDateTime.now(location);
    final scheduledIds = <String>{};

    const notifDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _economicChannelId,
        _economicChannelName,
        channelDescription: _economicChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        category: AndroidNotificationCategory.reminder,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

    await _runWithRecoveredAndroidScheduleCache(() async {
      for (final event in events) {
        final eventAt = tz.TZDateTime.from(event.date, location);
        if (!eventAt.isAfter(now.add(const Duration(minutes: 2)))) {
          continue;
        }

        var scheduledAt = tz.TZDateTime.from(
          event.date.subtract(leadTime),
          location,
        );
        if (!scheduledAt.isAfter(now.add(const Duration(seconds: 10)))) {
          scheduledAt = now.add(const Duration(seconds: 10));
        }

        if (!scheduledAt.isBefore(eventAt)) {
          continue;
        }

        await _plugin.zonedSchedule(
          _economicAlertNotificationId(event.id),
          '경제일정 임박',
          '${_formatEconomicCountry(event.country)} ${event.event} 발표가 ${_formatEconomicEventTime(event.date)} 예정이에요.',
          scheduledAt,
          notifDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: event.id,
        );
        scheduledIds.add(event.id);
      }
    });

    await _setScheduledEconomicAlertEventIds(scheduledIds);
    return scheduledIds.length;
  }

  static Future<void> cancelEconomicEventAlerts([
    Iterable<String>? eventIds,
  ]) async {
    final storedIds = await getScheduledEconomicAlertEventIds();
    final targetIds = eventIds == null ? storedIds : eventIds.toSet();

    if (targetIds.isEmpty) {
      if (eventIds == null) {
        await _setScheduledEconomicAlertEventIds(<String>{});
      }
      return;
    }

    for (final eventId in targetIds) {
      await _plugin.cancel(_economicAlertNotificationId(eventId));
    }

    final updatedIds = eventIds == null
        ? <String>{}
        : storedIds.difference(targetIds.toSet());
    await _setScheduledEconomicAlertEventIds(updatedIds);
  }

  // ─── 알림 표시 ────────────────────────────────────

  /// Alert 객체로 로컬 푸시 알림 전송
  static Future<void> show(Alert alert) async {
    final (title, body) = _buildContent(alert);
    final isKeyword = alert.alertType == 'keyword_match';

    final notifDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        isKeyword ? _keywordChannelId : _channelId,
        isKeyword ? _keywordChannelName : _channelName,
        channelDescription: isKeyword ? _keywordChannelDesc : _channelDesc,
        importance: isKeyword ? Importance.defaultImportance : Importance.high,
        priority: isKeyword ? Priority.defaultPriority : Priority.high,
        icon: '@mipmap/ic_launcher',
        ticker: title,
        color: isKeyword
            ? const Color(0xFF3B82F6) // accent blue
            : alert.alertType == 'finance_surge'
            ? const Color(0xFF22C55E) // green
            : alert.alertType == 'finance_fall'
            ? const Color(0xFFEF4444) // red
            : const Color(0xFFEF4444), // breaking red
        category: isKeyword
            ? AndroidNotificationCategory.reminder
            : AndroidNotificationCategory.event,
        styleInformation: isKeyword
            ? BigTextStyleInformation(
                body,
                contentTitle: title,
                summaryText: '키워드 매칭',
              )
            : null,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: isKeyword
            ? InterruptionLevel.active
            : InterruptionLevel.timeSensitive,
        subtitle: isKeyword ? alert.keyword : null,
      ),
    );

    await _plugin.show(
      alert.id.hashCode & 0x7FFFFFFF,
      title,
      body,
      notifDetails,
      payload: jsonEncode(alert.toJson()),
    );
  }

  // ─── 내부 헬퍼 ────────────────────────────────────

  static (String title, String body) _buildContent(Alert alert) {
    if (alert.alertType == 'keyword_match') {
      final keyword = alert.keyword.isNotEmpty ? alert.keyword : '키워드';
      final title = '[$keyword] 관련 뉴스';
      final body = alert.title.isNotEmpty ? alert.title : alert.message;
      return (title, body);
    }

    final prefix = switch (alert.alertType) {
      'finance_surge' => '급등',
      'finance_fall' => '급락',
      _ => '속보',
    };

    final title = '[$prefix] ${alert.title}';
    final body = alert.message.isNotEmpty ? alert.message : alert.title;
    return (title, body);
  }
}

class _MarketAlertDefinition {
  final int slot;
  final int hour;
  final int minute;
  final String title;
  final String body;

  const _MarketAlertDefinition({
    required this.slot,
    required this.hour,
    required this.minute,
    required this.title,
    required this.body,
  });
}
