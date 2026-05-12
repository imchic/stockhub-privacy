import 'dart:io';

import 'package:flutter/foundation.dart';

/// 광고 Unit ID 관리
class AdHelper {
  // ── Android 실제 ID ──
  static const String _androidBannerId =
      'ca-app-pub-1570138379392319/5680174451';
  static const String _androidInterstitialId =
      'ca-app-pub-1570138379392319/5354695228';
  static const String _androidAppOpenId =
      'ca-app-pub-1570138379392319/5024432867';

  // ── Google 공식 테스트 ID ──
  static const String _testBannerIdAndroid =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testInterstitialIdAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testAppOpenIdAndroid =
      'ca-app-pub-3940256099942544/9257395921';
  static const String _testBannerIdIos =
      'ca-app-pub-3940256099942544/2934735716';
  static const String _testInterstitialIdIos =
      'ca-app-pub-3940256099942544/4411468910';
  static const String _testAppOpenIdIos =
      'ca-app-pub-3940256099942544/5575463023';

  static String get bannerAdUnitId {
    if (Platform.isAndroid) {
      return kDebugMode ? _testBannerIdAndroid : _androidBannerId;
    }
    if (Platform.isIOS) return _testBannerIdIos;
    throw UnsupportedError('지원하지 않는 플랫폼입니다.');
  }

  static String get interstitialAdUnitId {
    if (Platform.isAndroid) {
      return kDebugMode ? _testInterstitialIdAndroid : _androidInterstitialId;
    }
    if (Platform.isIOS) return _testInterstitialIdIos;
    throw UnsupportedError('지원하지 않는 플랫폼입니다.');
  }

  static String get appOpenAdUnitId {
    if (Platform.isAndroid) {
      return kDebugMode ? _testAppOpenIdAndroid : _androidAppOpenId;
    }
    if (Platform.isIOS) return _testAppOpenIdIos;
    throw UnsupportedError('지원하지 않는 플랫폼입니다.');
  }
}
