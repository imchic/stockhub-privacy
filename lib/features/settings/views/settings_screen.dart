import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../config/index.dart';
import '../../../data/models/index.dart';
import '../../../providers/index.dart';
import '../../../services/app_update_service.dart';
import '../../../utils/app_toast.dart';
import '../../../utils/notification_permission_flow.dart';
import 'contact_info_screen.dart';

/// 설정 화면
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '설정',
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '개인 맞춤 설정',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: context.colors.border),
          const Expanded(child: _SettingsContent()),
        ],
      ),
    );
  }
}

/// 설정 콘텐츠
class _SettingsContent extends ConsumerWidget {
  const _SettingsContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: const [
        _SettingsSection(title: '관심 키워드', child: _KeywordSettings()),
        _SettingsSection(title: '알림 설정', child: _NotificationSettings()),
        _SettingsSection(title: '테마', child: _AppearanceSettings()),
        _SettingsSection(title: '앱 정보 및 문의', child: _SupportSettings()),
      ],
    );
  }
}

/// 설정 섹션
class _SettingsSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _SettingsSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.colors.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.border),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// 키워드 설정
class _KeywordSettings extends ConsumerStatefulWidget {
  const _KeywordSettings();

  @override
  ConsumerState<_KeywordSettings> createState() => _KeywordSettingsState();
}

class _KeywordSettingsState extends ConsumerState<_KeywordSettings> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    // FocusManager가 비동기로 알림을 보내므로, 다음 프레임에서 dispose하여
    // EditableTextState._handleFocusChanged가 먼저 완전히 정리되도록 함
    final controller = _controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    super.dispose();
  }

  Future<void> _showAddDialog() async {
    _controller.clear();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          '키워드 추가',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        content: TextField(
          controller: _controller,
          autofocus: true,
          style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: '쉼표로 여러 키워드 추가 가능 (삼성, 하이닉스, ...)',
            hintStyle: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 10,
            ),
            filled: true,
            fillColor: context.colors.surfaceLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: context.colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.of(ctx).pop(value);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
            },
            child: Text(
              '취소',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              final input = _controller.text.trim();
              if (input.isNotEmpty) {
                Navigator.of(ctx).pop(input);
              }
            },
            child: const Text(
              '추가',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      // 쉼표로 구분된 여러 키워드를 각각 등록
      final keywords = result
          .split(',')
          .map((k) => k.trim())
          .where((k) => k.isNotEmpty)
          .toList();

      for (final keyword in keywords) {
        await ref
            .read(favoriteKeywordsControllerProvider.notifier)
            .addKeyword(keyword);
      }
    }
  }

  Future<void> _removeKeyword(String keyword) async {
    try {
      await ref
          .read(favoriteKeywordsControllerProvider.notifier)
          .removeKeyword(keyword);
      if (!mounted) return;
      showAppToast(context, '관심 키워드 "$keyword" 삭제됨');
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        '키워드 삭제에 실패했습니다.',
        color: AppColors.red,
        icon: Icons.error_rounded,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final keywords = ref.watch(favoriteKeywordsControllerProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (keywords.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: keywords.map((keyword) {
                return Container(
                  key: ValueKey(keyword),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withAlpha(25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.accent.withAlpha(60)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 10,
                          top: 8,
                          bottom: 8,
                        ),
                        child: Text(
                          keyword,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _removeKeyword(keyword),
                        child: SizedBox(
                          width: 44,
                          height: 40,
                          child: Center(
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: context.colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
          GestureDetector(
            onTap: _showAddDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: context.colors.surfaceLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.colors.border),
              ),
              child: const Center(
                child: Text(
                  '+ 키워드 추가',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 알림 설정
class _NotificationSettings extends ConsumerWidget {
  const _NotificationSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pref = ref.watch(userPreferenceProvider).valueOrNull;
    final settings = ref.watch(alertSettingsProvider);
    final notificationsEnabled = pref?.notificationsEnabled ?? false;
    final alertLevel = pref?.alertLevel ?? 'medium';

    const levelDefs = [
      ('low', '낮음', '급등·폭락 등 긴급 알림만'),
      ('medium', '중간', '주요 시장 이벤트 포함'),
      ('high', '높음', '모든 뉴스·키워드 알림'),
    ];

    return Column(
      children: [
        // 알림 활성화
        InkWell(
          onTap: () async {
            final nextValue = !notificationsEnabled;

            if (nextValue) {
              await enableNotificationsFlow(context, ref);
              return;
            }

            await disableNotificationsFlow(context, ref);
          },
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '알림 활성화',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: context.colors.textPrimary,
                  ),
                ),
                _Toggle(
                  value: notificationsEnabled,
                  activeColor: AppColors.accent,
                ),
              ],
            ),
          ),
        ),
        Divider(
          height: 1,
          color: context.colors.border,
          indent: 16,
          endIndent: 16,
        ),
        // 알림 민감도 레이블
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              Text(
                '알림 민감도',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
              if (!notificationsEnabled) ...[
                const SizedBox(width: 6),
                Text(
                  '(알림 꺼짐)',
                  style: TextStyle(fontSize: 10, color: context.colors.border),
                ),
              ],
            ],
          ),
        ),
        // 알림 레벨 선택
        ...levelDefs.asMap().entries.map((entry) {
          final index = entry.key;
          final (level, label, desc) = entry.value;
          final isSelected = alertLevel == level;
          final isLast = index == levelDefs.length - 1;

          return Column(
            children: [
              InkWell(
                onTap: notificationsEnabled
                    ? () async {
                        await ref.read(setAlertLevelProvider(level).future);
                      }
                    : null,
                borderRadius: BorderRadius.vertical(
                  bottom: isLast ? const Radius.circular(12) : Radius.zero,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: !notificationsEnabled
                                    ? context.colors.border
                                    : isSelected
                                    ? AppColors.accent
                                    : context.colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              desc,
                              style: TextStyle(
                                fontSize: 11,
                                color: !notificationsEnabled
                                    ? context.colors.border
                                    : context.colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected && notificationsEnabled)
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.accent,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (!isLast)
                Divider(
                  height: 1,
                  color: context.colors.border,
                  indent: 16,
                  endIndent: 16,
                ),
            ],
          );
        }),
        Divider(
          height: 1,
          color: context.colors.border,
          indent: 16,
          endIndent: 16,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              Text(
                '알림 항목',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
              if (!notificationsEnabled) ...[
                const SizedBox(width: 6),
                Text(
                  '(알림 꺼짐)',
                  style: TextStyle(fontSize: 10, color: context.colors.border),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              _AlertRuleTile(
                icon: Icons.campaign_outlined,
                iconColor: AppColors.red,
                title: '긴급 속보 알림',
                subtitle: '긴급 뉴스(중요도 5단계)가 등록될 때만 알림',
                value: settings.breakingNewsEnabled,
                onChanged: notificationsEnabled
                    ? (value) => ref
                          .read(alertSettingsProvider.notifier)
                          .toggleBreakingNews(value)
                    : null,
              ),
              const SizedBox(height: 10),
              _AlertRuleTile(
                icon: Icons.search_outlined,
                iconColor: AppColors.accent,
                title: '키워드 알림',
                subtitle: '등록한 키워드가 뉴스에 포함되면 알림',
                value: settings.keywordAlertsEnabled,
                onChanged: notificationsEnabled
                    ? (value) => ref
                          .read(alertSettingsProvider.notifier)
                          .toggleKeywordAlerts(value)
                    : null,
              ),
              if (settings.keywordAlertsEnabled) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.colors.border),
                  ),
                  child: Text(
                    '관심 키워드는 위의 관심 키워드 섹션에서 관리합니다.',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _AlertRuleTile(
                icon: Icons.trending_up_rounded,
                iconColor: AppColors.green,
                title: '급등 알림',
                subtitle:
                    '시장 지수가 ${settings.surgeThreshold.toStringAsFixed(0)}% 이상 급등하면 알림',
                value: settings.surgeAlertsEnabled,
                onChanged: notificationsEnabled
                    ? (value) => ref
                          .read(alertSettingsProvider.notifier)
                          .toggleSurgeAlerts(value)
                    : null,
              ),
              const SizedBox(height: 10),
              _AlertRuleTile(
                icon: Icons.trending_down_rounded,
                iconColor: AppColors.red,
                title: '폭락 알림',
                subtitle:
                    '시장 지수가 ${settings.fallThreshold.toStringAsFixed(0)}% 이상 폭락하면 알림',
                value: settings.fallAlertsEnabled,
                onChanged: notificationsEnabled
                    ? (value) => ref
                          .read(alertSettingsProvider.notifier)
                          .toggleFallAlerts(value)
                    : null,
              ),
              if (settings.surgeAlertsEnabled ||
                  settings.fallAlertsEnabled) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.colors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (settings.surgeAlertsEnabled) ...[
                        Text(
                          '급등 임계값',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [2.0, 3.0, 5.0]
                              .map(
                                (threshold) => _ThresholdChoiceChip(
                                  label: '${threshold.toStringAsFixed(0)}%',
                                  color: AppColors.green,
                                  selected:
                                      settings.surgeThreshold == threshold,
                                  onTap: notificationsEnabled
                                      ? () => ref
                                            .read(
                                              alertSettingsProvider.notifier,
                                            )
                                            .setSurgeThreshold(threshold)
                                      : null,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      if (settings.surgeAlertsEnabled &&
                          settings.fallAlertsEnabled)
                        const SizedBox(height: 14),
                      if (settings.fallAlertsEnabled) ...[
                        Text(
                          '폭락 임계값',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [2.0, 3.0, 5.0]
                              .map(
                                (threshold) => _ThresholdChoiceChip(
                                  label: '${threshold.toStringAsFixed(0)}%',
                                  color: AppColors.red,
                                  selected: settings.fallThreshold == threshold,
                                  onTap: notificationsEnabled
                                      ? () => ref
                                            .read(
                                              alertSettingsProvider.notifier,
                                            )
                                            .setFallThreshold(threshold)
                                      : null,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _AlertRuleTile(
                icon: Icons.access_time_filled_rounded,
                iconColor: AppColors.accent,
                title: '장 시작/마감 알림',
                subtitle: '뉴스와 별개로 장 시작·마감 시간을 푸시로 알려드려요',
                value: settings.marketHoursEnabled,
                onChanged: notificationsEnabled
                    ? (value) async {
                        await ref
                            .read(alertSettingsProvider.notifier)
                            .toggleMarketHours(value);
                        if (!context.mounted) return;

                        final updated = ref
                            .read(alertSettingsProvider)
                            .marketHoursEnabled;
                        if (value && !updated) {
                          showAppToast(
                            context,
                            '권한이 허용되지 않아 장 시작/마감 알림을 켜지 못했어요.',
                            color: AppColors.red,
                            icon: Icons.access_time_filled_rounded,
                          );
                          return;
                        }

                        showAppToast(
                          context,
                          updated ? '장 시작/마감 알림을 켰어요.' : '장 시작/마감 알림을 껐어요.',
                          icon: Icons.access_time_filled_rounded,
                        );
                      }
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AlertRuleTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _AlertRuleTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.accent,
          ),
        ],
      ),
    );
  }
}

class _ThresholdChoiceChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  const _ThresholdChoiceChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.18)
              : context.colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : context.colors.border,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : context.colors.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// 테마 설정
class _AppearanceSettings extends ConsumerWidget {
  const _AppearanceSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMode =
        ref.watch(userPreferenceProvider).valueOrNull?.themeMode ??
        UserPreference.themeModeSystem;
    final deviceBrightness = MediaQuery.platformBrightnessOf(context);
    final isDeviceDark = deviceBrightness == Brightness.dark;
    final deviceThemeLabel = isDeviceDark ? '다크' : '라이트';

    Future<void> updateThemeMode(String mode) async {
      if (selectedMode == mode) return;
      await ref.read(setThemeModeProvider(mode).future);
    }

    Widget buildChoice({
      required String label,
      required String mode,
      required Color color,
    }) {
      return _ThresholdChoiceChip(
        label: label,
        color: color,
        selected: selectedMode == mode,
        onTap: () => updateThemeMode(mode),
      );
    }

    final helperText = switch (selectedMode) {
      UserPreference.themeModeLight => '항상 라이트 테마를 사용합니다.',
      UserPreference.themeModeDark => '항상 다크 테마를 사용합니다.',
      _ => '최초 기본값이며, 기기 테마 변경을 자동으로 따라갑니다.',
    };
    final appliedThemeLabel = switch (selectedMode) {
      UserPreference.themeModeLight => '앱 적용: 라이트',
      UserPreference.themeModeDark => '앱 적용: 다크',
      _ => '앱 적용: 기기 테마 따라감',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '앱 테마',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            helperText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: context.colors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: context.colors.surfaceLight,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: context.colors.border),
                ),
                child: Text(
                  '기기 테마: $deviceThemeLabel',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: selectedMode == UserPreference.themeModeSystem
                      ? AppColors.accent.withValues(alpha: 0.10)
                      : context.colors.surfaceLight,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selectedMode == UserPreference.themeModeSystem
                        ? AppColors.accent.withValues(alpha: 0.28)
                        : context.colors.border,
                  ),
                ),
                child: Text(
                  appliedThemeLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: selectedMode == UserPreference.themeModeSystem
                        ? AppColors.accent
                        : context.colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              buildChoice(
                label: '사용자 설정',
                mode: UserPreference.themeModeSystem,
                color: AppColors.accent,
              ),
              buildChoice(
                label: '라이트',
                mode: UserPreference.themeModeLight,
                color: AppColors.orange,
              ),
              buildChoice(
                label: '다크',
                mode: UserPreference.themeModeDark,
                color: AppColors.green,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SupportSettings extends ConsumerWidget {
  const _SupportSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUpdateAsync = ref.watch(appUpdateStatusProvider);
    final storeUpdateAsync = ref.watch(storeUpdateStatusProvider);
    final appUpdate = appUpdateAsync.valueOrNull;
    final storeUpdate = storeUpdateAsync.valueOrNull;
    final lastUpdatedLabel = switch (appUpdate?.lastUpdatedAt) {
      final DateTime value => DateFormat('yyyy.MM.dd HH:mm').format(value),
      _ => null,
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.colors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.colors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withAlpha(24),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.badge_outlined,
                        color: AppColors.accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '앱 정보 및 문의',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: context.colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '버전, 운영 주체, 연락처, 정책 링크를 한 곳에서 확인할 수 있어요.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.45,
                              color: context.colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _VersionStatusCard(
                appUpdate: appUpdate,
                storeUpdate: storeUpdate,
                lastUpdatedLabel: lastUpdatedLabel,
                onCopy: () => _copySupportValue(
                  context,
                  appUpdate?.currentVersion ?? '',
                  '앱 버전이 복사되었습니다',
                ),
              ),
              if (appUpdate != null && appUpdate.releaseNotes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _ReleaseNotesCard(
                    version: appUpdate.currentVersion,
                    notes: appUpdate.releaseNotes,
                  ),
                ),
            ],
          ),
        ),
        Divider(
          height: 1,
          color: context.colors.border,
          indent: 16,
          endIndent: 16,
        ),
        InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ContactInfoScreen()),
            );
          },
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withAlpha(24),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.support_agent_rounded,
                    color: AppColors.accent,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '앱 정보 및 문의 보기',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '운영 정보, 연락처, 정책, 데이터 출처를 확인합니다.',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: context.colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _copySupportValue(
    BuildContext context,
    String value,
    String message,
  ) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    showAppToast(context, message);
  }
}

class _ReleaseNotesCard extends StatelessWidget {
  final String version;
  final List<String> notes;

  const _ReleaseNotesCard({required this.version, required this.notes});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '릴리즈 노트',
            style: TextStyle(fontSize: 11, color: context.colors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            version,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      note,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _VersionStatusCard extends StatelessWidget {
  final AppUpdateStatus? appUpdate;
  final StoreUpdateStatus? storeUpdate;
  final String? lastUpdatedLabel;
  final VoidCallback onCopy;

  const _VersionStatusCard({
    required this.appUpdate,
    required this.storeUpdate,
    required this.lastUpdatedLabel,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final currentVersion = appUpdate?.currentVersion ?? '확인 중...';
    final statusLabel = switch ((
      storeUpdate?.isUpdateAvailable,
      storeUpdate?.isSupported,
    )) {
      (true, _) => '업데이트 가능',
      (_, true) => '최신 버전',
      _ => '확인 불가',
    };
    final statusColor = switch ((
      storeUpdate?.isUpdateAvailable,
      storeUpdate?.isSupported,
    )) {
      (true, _) => AppColors.orange,
      (_, true) => AppColors.green,
      _ => context.colors.textSecondary,
    };
    final actionLabel = storeUpdate?.isUpdateAvailable == true
        ? (storeUpdate!.immediateUpdateAllowed ? '업데이트' : '스토어 열기')
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.system_update_rounded,
              size: 18,
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '현재 버전',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            currentVersion,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: context.colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(onPressed: onCopy, child: const Text('복사')),
                  ],
                ),
                if (appUpdate?.previousVersion != null &&
                    lastUpdatedLabel != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '최근 업데이트',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${appUpdate!.previousVersion} -> ${appUpdate!.currentVersion}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                    if (lastUpdatedLabel != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          lastUpdatedLabel!,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () async {
                final launched = await AppUpdateService.launchUpdate();
                if (!context.mounted || launched) return;
                showAppToast(
                  context,
                  '업데이트 화면을 열지 못했습니다.',
                  color: AppColors.red,
                  icon: Icons.error_rounded,
                );
              },
              child: Text(actionLabel),
            ),
          ],
        ],
      ),
    );
  }
}

/// 커스텀 토글
class _Toggle extends StatelessWidget {
  final bool value;
  final Color activeColor;

  const _Toggle({required this.value, required this.activeColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 24,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: value ? activeColor : context.colors.border,
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            left: value ? 20 : 2,
            top: 2,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
