import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 사용자 알림 설정 모델
class AlertSettings {
  /// 속보 알림 (importanceLevel >= minImportanceLevel) ON/OFF
  final bool breakingNewsEnabled;

  /// 키워드 알림 ON/OFF
  final bool keywordAlertsEnabled;

  /// 최소 중요도 (고정 5 — 긴급만 알림)
  final int minImportanceLevel;

  /// 급등 알림 ON/OFF (지수 변화율 >= surgeThreshold)
  final bool surgeAlertsEnabled;

  /// 폭락 알림 ON/OFF (지수 변화율 <= -surgeThreshold)
  final bool fallAlertsEnabled;

  /// 급등 임계 변화율 (기본 3.0%)
  final double surgeThreshold;

  /// 폭락 임계 변화율 (기본 3.0%, 급등과 별도 설정)
  final double fallThreshold;

  /// 장 시작/마감 알림 ON/OFF
  final bool marketHoursEnabled;

  const AlertSettings({
    this.breakingNewsEnabled = true,
    this.keywordAlertsEnabled = true,
    this.minImportanceLevel = 3,
    this.surgeAlertsEnabled = true,
    this.fallAlertsEnabled = true,
    this.surgeThreshold = 3.0,
    this.fallThreshold = 3.0,
    this.marketHoursEnabled = true,
  });

  AlertSettings copyWith({
    bool? breakingNewsEnabled,
    bool? keywordAlertsEnabled,
    int? minImportanceLevel,
    bool? surgeAlertsEnabled,
    bool? fallAlertsEnabled,
    double? surgeThreshold,
    double? fallThreshold,
    bool? marketHoursEnabled,
  }) {
    return AlertSettings(
      breakingNewsEnabled: breakingNewsEnabled ?? this.breakingNewsEnabled,
      keywordAlertsEnabled: keywordAlertsEnabled ?? this.keywordAlertsEnabled,
      minImportanceLevel: minImportanceLevel ?? this.minImportanceLevel,
      surgeAlertsEnabled: surgeAlertsEnabled ?? this.surgeAlertsEnabled,
      fallAlertsEnabled: fallAlertsEnabled ?? this.fallAlertsEnabled,
      surgeThreshold: surgeThreshold ?? this.surgeThreshold,
      fallThreshold: fallThreshold ?? this.fallThreshold,
      marketHoursEnabled: marketHoursEnabled ?? this.marketHoursEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'breakingNewsEnabled': breakingNewsEnabled,
    'keywordAlertsEnabled': keywordAlertsEnabled,
    'minImportanceLevel': minImportanceLevel,
    'surgeAlertsEnabled': surgeAlertsEnabled,
    'fallAlertsEnabled': fallAlertsEnabled,
    'surgeThreshold': surgeThreshold,
    'fallThreshold': fallThreshold,
    'marketHoursEnabled': marketHoursEnabled,
  };

  factory AlertSettings.fromJson(Map<String, dynamic> json) => AlertSettings(
    breakingNewsEnabled: json['breakingNewsEnabled'] as bool? ?? true,
    keywordAlertsEnabled: json['keywordAlertsEnabled'] as bool? ?? true,
    minImportanceLevel: json['minImportanceLevel'] as int? ?? 3,
    surgeAlertsEnabled: json['surgeAlertsEnabled'] as bool? ?? true,
    fallAlertsEnabled: json['fallAlertsEnabled'] as bool? ?? true,
    surgeThreshold: (json['surgeThreshold'] as num?)?.toDouble() ?? 3.0,
    fallThreshold: (json['fallThreshold'] as num?)?.toDouble() ?? 3.0,
    marketHoursEnabled: json['marketHoursEnabled'] as bool? ?? true,
  );

  static const _prefKey = 'alert_settings_v1';

  static Future<AlertSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null) return const AlertSettings();
    try {
      return AlertSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AlertSettings();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(toJson()));
  }
}
