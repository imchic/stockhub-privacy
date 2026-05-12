import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/alert_settings.dart';
import '../services/app_onboarding_service.dart';
import '../services/background_task_service.dart';
import '../services/notification_service.dart';
import 'user_preference_providers.dart';

final notificationOnboardingSeenProvider = FutureProvider<bool>((ref) async {
  return AppOnboardingService.isNotificationOnboardingSeen();
});

final completeNotificationOnboardingProvider = FutureProvider.autoDispose<void>(
  (ref) async {
    await AppOnboardingService.markNotificationOnboardingSeen();

    final userPreference = await ref.read(userPreferenceProvider.future);
    final notificationsEnabled = userPreference?.notificationsEnabled ?? false;
    final alertSettings = await AlertSettings.load();

    await syncMarketAlerts(
      notificationsEnabled: notificationsEnabled,
      onboardingSeen: true,
      marketHoursEnabled: alertSettings.marketHoursEnabled,
    );

    await syncBackgroundAlertTask(enabled: notificationsEnabled);

    ref.invalidate(notificationOnboardingSeenProvider);
  },
);
