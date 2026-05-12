import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'config/index.dart';
import 'data/models/index.dart';
import 'data/services/local_storage_service.dart';
import 'features/home/views/home_screen.dart';
import 'features/onboarding/views/notification_onboarding_screen.dart';
import 'providers/index.dart';
import 'services/app_onboarding_service.dart';
import 'services/background_task_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppOnboardingService.initializeAlertExperienceIfNeeded();
  await NotificationService.init();
  await MobileAds.instance.initialize();
  final isNotificationOnboardingSeen =
      await AppOnboardingService.isNotificationOnboardingSeen();

  final localStorage = await LocalStorageService.create();
  final notificationsEnabled =
      localStorage.getUserPreference()?.notificationsEnabled ?? false;

  // 마스터 알림 + 장 시작/마감 설정이 모두 켜져 있을 때만 재예약
  final alertSettings = await AlertSettings.load();
  await syncMarketAlerts(
    notificationsEnabled: notificationsEnabled,
    onboardingSeen: isNotificationOnboardingSeen,
    marketHoursEnabled: alertSettings.marketHoursEnabled,
  );

  // 백그라운드 뉴스 체크는 마스터 알림 상태에 맞춰 등록/해제
  await syncBackgroundAlertTask(
    enabled: notificationsEnabled && isNotificationOnboardingSeen,
  );

  await NotificationService.scheduleMarketHoursTestNotification();

  runApp(const ProviderScope(child: PinStockApp()));
}

class PinStockApp extends ConsumerWidget {
  const PinStockApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 네트워크 상태 감시 (오프라인 배너에 사용)
    final isOnline = ref.watch(isOnlineProvider);

    // 앱 진입 시 KRX 종목 목록 미리 로드
    ref.watch(krxStocksProvider);

    // 사용자 설정 감시 (다크 모드 등)
    final userPrefAsync = ref.watch(userPreferenceProvider);
    final onboardingSeenAsync = ref.watch(notificationOnboardingSeenProvider);

    return userPrefAsync.when(
      data: (preference) {
        final themeModeName =
            preference?.themeMode ?? UserPreference.themeModeSystem;
        final themeMode = switch (themeModeName) {
          UserPreference.themeModeLight => ThemeMode.light,
          UserPreference.themeModeDark => ThemeMode.dark,
          _ => ThemeMode.system,
        };

        return onboardingSeenAsync.when(
          data: (onboardingSeen) {
            if (onboardingSeen) {
              ref.listen(breakingNewsWatcherProvider, (_, next) {
                next.whenData((alert) {
                  NotificationService.show(alert);
                  // 새 속보 감지 시 속보 탭도 즉시 갱신 (finance 화면의 타이머와 무관하게)
                  ref.invalidate(stockMarketNewsProvider);
                });
              });
              ref.listen(marketSurgeWatcherProvider, (_, next) {
                next.whenData(NotificationService.show);
              });
            }

            return MaterialApp(
              title: AppConstants.appName,
              theme: AppTheme.lightTheme(),
              darkTheme: AppTheme.darkTheme(),
              themeMode: themeMode,
              debugShowCheckedModeBanner: false,
              // 안드로이드 SafeArea 및 텍스트 크기 접근성 향상
              builder: (context, child) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return AnnotatedRegion<SystemUiOverlayStyle>(
                  value: isDark
                      ? SystemUiOverlayStyle.light.copyWith(
                          statusBarColor: const Color(0xFF0A0A0A),
                        )
                      : SystemUiOverlayStyle.dark.copyWith(
                          statusBarColor: const Color(0xFFF2F4F6),
                        ),
                  child: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(1.2)),
                    child: Container(
                      color: isDark
                          ? const Color(0xFF0A0A0A)
                          : const Color(0xFFF2F4F6),
                      child: SafeArea(
                        bottom: false,
                        child: Column(
                          children: [
                            // 오프라인 배너
                            AnimatedSize(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                              child: isOnline || !onboardingSeen
                                  ? const SizedBox.shrink()
                                  : Container(
                                      width: double.infinity,
                                      color: const Color(0xFFE53E3E),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6,
                                        horizontal: 16,
                                      ),
                                      child: const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.wifi_off,
                                            color: Colors.white,
                                            size: 13,
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            '인터넷 연결 없음 — 캐시 데이터를 표시합니다',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                            Expanded(child: child!),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
              home: onboardingSeen
                  ? const HomeScreen()
                  : const NotificationOnboardingScreen(),
            );
          },
          loading: () => MaterialApp(
            title: AppConstants.appName,
            theme: AppTheme.lightTheme(),
            darkTheme: AppTheme.darkTheme(),
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (error, stack) => MaterialApp(
            title: AppConstants.appName,
            theme: AppTheme.lightTheme(),
            darkTheme: AppTheme.darkTheme(),
            home: Scaffold(
              body: Center(
                child: Text(
                  '온보딩 상태 로드 오류: $error',
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        );
      },
      loading: () => MaterialApp(
        title: AppConstants.appName,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        // 로딩 화면에도 SafeArea 및 텍스트 크기 향상 적용
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.2)),
            child: SafeArea(bottom: false, child: child!),
          );
        },
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      error: (error, stack) => MaterialApp(
        title: AppConstants.appName,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        // 에러 화면에도 SafeArea 및 텍스트 크기 향상 적용
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.2)),
            child: SafeArea(bottom: false, child: child!),
          );
        },
        home: Scaffold(
          body: Center(
            child: Text(
              '앱 초기화 오류: $error',
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
