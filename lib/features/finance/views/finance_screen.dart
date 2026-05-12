import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinstock/config/constants.dart';
import 'package:pinstock/config/theme/colors.dart';
import 'package:shimmer/shimmer.dart';

import '../../../data/models/finance_news.dart';
import '../../../data/models/index.dart' show Keyword, News;
import '../../../data/models/market_index.dart';
import '../../../providers/index.dart';
import '../../../utils/ad_service.dart';
import '../../../utils/app_toast.dart';
import '../../feed/views/news_popup.dart';
import '../../feed/views/news_web_view_screen.dart';

/// 금융 뉴스 화면
class _MarketStatusInfo {
  final String label;
  final String detail;
  final Color color;

  const _MarketStatusInfo({
    required this.label,
    required this.detail,
    required this.color,
  });
}

class _EconomicCalendarEvent {
  final String title;
  final String market;
  final String detail;
  final String scheduleLabel;
  final DateTime scheduledAt;
  final Color color;
  final IconData icon;

  const _EconomicCalendarEvent({
    required this.title,
    required this.market,
    required this.detail,
    required this.scheduleLabel,
    required this.scheduledAt,
    required this.color,
    required this.icon,
  });
}

typedef _AiFallbackPickItem = ({
  String name,
  String linkKeyword,
  String sectorTag,
  String reason,
});

typedef _AiFallbackPickRow = ({String market, List<_AiFallbackPickItem> items});

/// 금융 뉴스 화면
class FinanceScreen extends ConsumerStatefulWidget {
  final bool showEconomicOnly;

  const FinanceScreen({super.key, this.showEconomicOnly = false});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  Timer? _newsRefreshTimer;
  Timer? _marketStatusTimer;
  bool _isRefreshingAiSummary = false;
  bool _showBullishAiPicks = true;
  String? _selectedAiSector;
  bool? _selectedAiSectorIsBull;

  @override
  void initState() {
    super.initState();
    if (!widget.showEconomicOnly) {
      _tabController = TabController(length: 7, vsync: this);
    }
    _newsRefreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (!mounted) return;
      ref.invalidate(stockMarketNewsProvider);
    });
    _marketStatusTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant FinanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.showEconomicOnly == widget.showEconomicOnly) {
      return;
    }

    if (widget.showEconomicOnly) {
      _tabController?.dispose();
      _tabController = null;
      return;
    }

    _tabController?.dispose();
    _tabController = TabController(length: 7, vsync: this);
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _newsRefreshTimer?.cancel();
    _marketStatusTimer?.cancel();
    super.dispose();
  }

  void _showToast(String message, {Color? color}) {
    showAppToast(context, message, color: color);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showEconomicOnly) {
      return Scaffold(
        backgroundColor: context.colors.bg,
        body: SafeArea(bottom: false, child: _buildEconomicTab()),
      );
    }

    return Scaffold(
      backgroundColor: context.colors.bg,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildMarketIndicesRow()),
          SliverToBoxAdapter(child: _buildAiSummaryCard()),
          SliverToBoxAdapter(child: _buildTabBar()),
          SliverToBoxAdapter(
            child: Divider(height: 1, color: context.colors.border),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildStockNewsTab(),
            const _FinanceKeywordTab(),
            _buildWarNewsTab(),
            _buildKospiTab(),
            _buildKosdaqTab(),
            _buildNasdaqTab(),
            _buildCoinTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final domesticMarketStatus = _getCurrentMarketStatus();
    final usMarketStatus = _getUsMarketStatus();

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '오늘의 증시 분석',
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '실시간 시장 분석',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Consumer(
              builder: (context, ref, _) {
                final indicesAsync = ref.watch(marketIndicesProvider);
                final updatedAt =
                    indicesAsync.valueOrNull?.firstOrNull?.updatedAt;
                final timeStr = updatedAt != null
                    ? '${updatedAt.hour.toString().padLeft(2, '0')}:${updatedAt.minute.toString().padLeft(2, '0')}:${updatedAt.second.toString().padLeft(2, '0')}'
                    : null;
                final statusColor = indicesAsync.isLoading
                    ? AppColors.orange
                    : indicesAsync.hasError
                    ? AppColors.red
                    : AppColors.green;
                final statusLabel = indicesAsync.isLoading
                    ? '동기화 중'
                    : indicesAsync.hasError
                    ? '오류 발생'
                    : '실시간 반영';

                return GestureDetector(
                  onTap: () {
                    ref.invalidate(marketIndicesProvider);
                    _showToast('시장 지수 새로고침 중…');
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.colors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.query_stats_rounded,
                            size: 18,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '시장 지수 업데이트',
                                    style: TextStyle(
                                      color: context.colors.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: statusColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      statusLabel,
                                      style: TextStyle(
                                        color: context.colors.textSecondary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.1,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                timeStr == null
                                    ? '데이터 수신 대기 중'
                                    : '최근 반영 시각 $timeStr',
                                style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: context.colors.surfaceLight,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '새로고침',
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Flexible(
                  child: _buildMarketStatusBadge(
                    title: '국내',
                    status: domesticMarketStatus,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: _buildMarketStatusBadge(
                    title: '해외',
                    status: usMarketStatus,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildInvestmentDisclaimer(),
          ],
        ),
      ),
    );
  }

  Widget _buildInvestmentDisclaimer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: context.colors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '본 서비스에서 제공하는 정보는 단순 참고용이며, 투자를 권유하거나 종목을 추천하기 위한 목적이 아니에요.',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.4,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarketStatusBadge({
    required String title,
    required _MarketStatusInfo status,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: status.color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: status.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(
              color: status.color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            status.detail,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  DateTime _utcNow() => DateTime.now().toUtc();

  DateTime _koreaNow() => _utcNow().add(const Duration(hours: 9));

  DateTime _newYorkNow() {
    final nowUtc = _utcNow();
    final offsetHours = _isUsEasternDst(nowUtc) ? -4 : -5;
    return nowUtc.add(Duration(hours: offsetHours));
  }

  int _usToKoreaOffsetHours() {
    return _isUsEasternDst(_utcNow()) ? 13 : 14;
  }

  String _formatTime(int hour, int minute) {
    final hourText = hour.toString().padLeft(2, '0');
    final minuteText = minute.toString().padLeft(2, '0');
    return '$hourText:$minuteText';
  }

  String _formatUsMarketTimeInKorea(int hour, int minute) {
    final base = DateTime.utc(2000, 1, 1, hour, minute);
    final koreaTime = base.add(Duration(hours: _usToKoreaOffsetHours()));
    return _formatTime(koreaTime.hour, koreaTime.minute);
  }

  bool _isUsEasternDst(DateTime utcTime) {
    final year = utcTime.year;
    final dstStartUtc = _nthWeekdayOfMonthUtc(
      year,
      3,
      DateTime.sunday,
      2,
      hour: 7,
    );
    final dstEndUtc = _nthWeekdayOfMonthUtc(
      year,
      11,
      DateTime.sunday,
      1,
      hour: 6,
    );
    return !utcTime.isBefore(dstStartUtc) && utcTime.isBefore(dstEndUtc);
  }

  DateTime _nthWeekdayOfMonthUtc(
    int year,
    int month,
    int weekday,
    int occurrence, {
    int hour = 0,
    int minute = 0,
  }) {
    final firstDay = DateTime.utc(year, month);
    final offset = (weekday - firstDay.weekday + 7) % 7;
    final day = 1 + offset + (occurrence - 1) * 7;
    return DateTime.utc(year, month, day, hour, minute);
  }

  _MarketStatusInfo _getCurrentMarketStatus() {
    final now = _koreaNow();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return _MarketStatusInfo(
        label: '휴장',
        detail: _formatTime(8, 0),
        color: const Color(0xFF9AA4AF),
      );
    }

    final seconds = now.hour * 3600 + now.minute * 60 + now.second;

    if (seconds < _marketTimeSeconds(8, 0)) {
      return _MarketStatusInfo(
        label: '개장 전',
        detail: _formatTime(8, 0),
        color: AppColors.orange,
      );
    }

    if (seconds < _marketTimeSeconds(8, 50)) {
      return _MarketStatusInfo(
        label: '프리마켓',
        detail: _formatTime(8, 50),
        color: AppColors.green,
      );
    }

    if (seconds < _marketTimeSeconds(9, 0)) {
      return _MarketStatusInfo(
        label: '정규장',
        detail: _formatTime(9, 0),
        color: AppColors.orange,
      );
    }

    if (seconds < _marketTimeSeconds(9, 0, 30)) {
      return _MarketStatusInfo(
        label: '정규장',
        detail: _formatTime(9, 0),
        color: AppColors.accent,
      );
    }

    if (seconds < _marketTimeSeconds(15, 20)) {
      return _MarketStatusInfo(
        label: '정규장',
        detail: _formatTime(15, 20),
        color: AppColors.green,
      );
    }

    if (seconds < _marketTimeSeconds(15, 30)) {
      return _MarketStatusInfo(
        label: '정규장',
        detail: _formatTime(15, 30),
        color: AppColors.green,
      );
    }

    if (seconds < _marketTimeSeconds(15, 40)) {
      return _MarketStatusInfo(
        label: '종가매매',
        detail: _formatTime(15, 40),
        color: AppColors.accent,
      );
    }

    if (seconds < _marketTimeSeconds(16, 0)) {
      return _MarketStatusInfo(
        label: '애프터마켓',
        detail: _formatTime(16, 0),
        color: AppColors.info,
      );
    }

    if (seconds < _marketTimeSeconds(20, 0)) {
      return _MarketStatusInfo(
        label: '애프터마켓',
        detail: _formatTime(20, 0),
        color: AppColors.info,
      );
    }

    return _MarketStatusInfo(
      label: '장마감',
      detail: _formatTime(8, 0),
      color: const Color(0xFF9AA4AF),
    );
  }

  _MarketStatusInfo _getUsMarketStatus() {
    final now = _newYorkNow();
    final isWeekend =
        now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;

    if (isWeekend) {
      return _MarketStatusInfo(
        label: '휴장',
        detail: _formatUsMarketTimeInKorea(4, 0),
        color: const Color(0xFF9AA4AF),
      );
    }

    final seconds = now.hour * 3600 + now.minute * 60 + now.second;

    if (seconds < _marketTimeSeconds(4, 0)) {
      return _MarketStatusInfo(
        label: '장마감',
        detail: _formatUsMarketTimeInKorea(4, 0),
        color: const Color(0xFF9AA4AF),
      );
    }

    if (seconds < _marketTimeSeconds(9, 30)) {
      return _MarketStatusInfo(
        label: '데이마켓',
        detail: _formatUsMarketTimeInKorea(9, 30),
        color: AppColors.orange,
      );
    }

    if (seconds < _marketTimeSeconds(16, 0)) {
      return _MarketStatusInfo(
        label: '정규장',
        detail: _formatUsMarketTimeInKorea(16, 0),
        color: AppColors.green,
      );
    }

    if (seconds < _marketTimeSeconds(20, 0)) {
      return _MarketStatusInfo(
        label: '애프터마켓',
        detail: _formatUsMarketTimeInKorea(20, 0),
        color: AppColors.info,
      );
    }

    return _MarketStatusInfo(
      label: '장마감',
      detail: _formatUsMarketTimeInKorea(4, 0),
      color: const Color(0xFF9AA4AF),
    );
  }

  int _marketTimeSeconds(int hour, int minute, [int second = 0]) {
    return hour * 3600 + minute * 60 + second;
  }

  List<_EconomicCalendarEvent> _buildUpcomingEconomicEvents() {
    final events = [
      _EconomicCalendarEvent(
        title: '한국 수출입 동향',
        market: '한국',
        detail: '월간 수출입과 무역수지 발표',
        scheduleLabel: '매월 1일 09:00',
        scheduledAt: _nextKoreaMonthlyOccurrence(day: 1, hour: 9),
        color: AppColors.accent,
        icon: Icons.local_shipping_rounded,
      ),
      _EconomicCalendarEvent(
        title: '미국 신규 실업수당',
        market: '미국',
        detail: '고용시장 둔화 여부를 빠르게 확인하는 주간 지표',
        scheduleLabel: '매주 목요일 21:30/22:30',
        scheduledAt: _nextEasternWeeklyOccurrence(
          weekday: DateTime.thursday,
          hour: 8,
          minute: 30,
        ),
        color: AppColors.warning,
        icon: Icons.work_outline_rounded,
      ),
      _EconomicCalendarEvent(
        title: '미국 고용보고서',
        market: '미국',
        detail: '비농업 고용과 실업률 발표',
        scheduleLabel: '매월 첫째 금요일 21:30/22:30',
        scheduledAt: _nextEasternNthWeekdayOccurrence(
          weekday: DateTime.friday,
          occurrence: 1,
          hour: 8,
          minute: 30,
        ),
        color: AppColors.orange,
        icon: Icons.badge_rounded,
      ),
      _EconomicCalendarEvent(
        title: '미국 CPI',
        market: '미국',
        detail: '소비자물가 발표로 금리 기대가 크게 움직일 수 있어요',
        scheduleLabel: '매월 12일 21:30/22:30',
        scheduledAt: _nextEasternMonthlyOccurrence(
          day: 12,
          hour: 8,
          minute: 30,
        ),
        color: AppColors.red,
        icon: Icons.local_fire_department_rounded,
      ),
      _EconomicCalendarEvent(
        title: '미국 PPI',
        market: '미국',
        detail: '생산자물가로 인플레이션 선행 압력을 확인해요',
        scheduleLabel: '매월 13일 21:30/22:30',
        scheduledAt: _nextEasternMonthlyOccurrence(
          day: 13,
          hour: 8,
          minute: 30,
        ),
        color: AppColors.info,
        icon: Icons.factory_rounded,
      ),
      _EconomicCalendarEvent(
        title: '미국 소매판매',
        market: '미국',
        detail: '소비 경기 강도를 가늠하는 핵심 지표예요',
        scheduleLabel: '매월 15일 21:30/22:30',
        scheduledAt: _nextEasternMonthlyOccurrence(
          day: 15,
          hour: 8,
          minute: 30,
        ),
        color: AppColors.green,
        icon: Icons.shopping_bag_rounded,
      ),
    ]..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    return events;
  }

  DateTime _nextKoreaMonthlyOccurrence({
    required int day,
    required int hour,
    int minute = 0,
  }) {
    final now = _koreaNow();
    var year = now.year;
    var month = now.month;

    while (true) {
      final lastDay = DateTime.utc(year, month + 1, 0).day;
      final candidateDay = day <= lastDay ? day : lastDay;
      final candidate = DateTime.utc(year, month, candidateDay, hour, minute);
      if (!candidate.isBefore(now)) {
        return candidate;
      }
      if (month == 12) {
        year += 1;
        month = 1;
      } else {
        month += 1;
      }
    }
  }

  DateTime _nextEasternMonthlyOccurrence({
    required int day,
    required int hour,
    int minute = 0,
  }) {
    final now = _koreaNow();
    var year = now.year;
    var month = now.month;

    while (true) {
      final lastDay = DateTime.utc(year, month + 1, 0).day;
      final candidateDay = day <= lastDay ? day : lastDay;
      final candidate = _easternLocalToKoreaTime(
        year,
        month,
        candidateDay,
        hour,
        minute,
      );
      if (!candidate.isBefore(now)) {
        return candidate;
      }
      if (month == 12) {
        year += 1;
        month = 1;
      } else {
        month += 1;
      }
    }
  }

  DateTime _nextEasternWeeklyOccurrence({
    required int weekday,
    required int hour,
    int minute = 0,
  }) {
    final now = _koreaNow();
    var candidate = _easternLocalToKoreaTime(
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    final weekdayDelta = (weekday - candidate.weekday + 7) % 7;
    candidate = candidate.add(Duration(days: weekdayDelta));

    if (candidate.isBefore(now)) {
      candidate = candidate.add(const Duration(days: 7));
    }
    return candidate;
  }

  DateTime _nextEasternNthWeekdayOccurrence({
    required int weekday,
    required int occurrence,
    required int hour,
    int minute = 0,
  }) {
    final now = _koreaNow();
    var year = now.year;
    var month = now.month;

    while (true) {
      final candidateDay = _nthWeekdayOfMonthDay(
        year,
        month,
        weekday,
        occurrence,
      );
      final candidate = _easternLocalToKoreaTime(
        year,
        month,
        candidateDay,
        hour,
        minute,
      );
      if (!candidate.isBefore(now)) {
        return candidate;
      }
      if (month == 12) {
        year += 1;
        month = 1;
      } else {
        month += 1;
      }
    }
  }

  int _nthWeekdayOfMonthDay(int year, int month, int weekday, int occurrence) {
    final firstDay = DateTime.utc(year, month);
    final offset = (weekday - firstDay.weekday + 7) % 7;
    return 1 + offset + (occurrence - 1) * 7;
  }

  DateTime _easternLocalToKoreaTime(
    int year,
    int month,
    int day,
    int hour,
    int minute,
  ) {
    return _easternLocalToUtc(
      year,
      month,
      day,
      hour,
      minute,
    ).add(const Duration(hours: 9));
  }

  DateTime _easternLocalToUtc(
    int year,
    int month,
    int day,
    int hour,
    int minute,
  ) {
    final dstCandidate = DateTime.utc(year, month, day, hour + 4, minute);
    if (_isUsEasternDst(dstCandidate)) {
      return dstCandidate;
    }
    return DateTime.utc(year, month, day, hour + 5, minute);
  }

  String _formatEconomicEventDate(DateTime scheduledAt) {
    return '${scheduledAt.month.toString().padLeft(2, '0')}/${scheduledAt.day.toString().padLeft(2, '0')}';
  }

  String _formatEconomicEventTime(DateTime scheduledAt) {
    final hour = scheduledAt.hour.toString().padLeft(2, '0');
    final minute = scheduledAt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _weekdayLabel(int weekday) {
    const labels = ['월', '화', '수', '목', '금', '토', '일'];
    return labels[weekday - 1];
  }

  String _formatEconomicCountdown(DateTime scheduledAt) {
    final diff = scheduledAt.difference(_koreaNow());
    if (diff.inMinutes <= 0) {
      return '진행 중';
    }
    if (diff.inDays == 0) {
      if (diff.inHours >= 1) {
        return '${diff.inHours}시간 후';
      }
      return '${diff.inMinutes}분 후';
    }
    if (diff.inDays == 1) {
      return '내일';
    }
    return 'D-${diff.inDays}';
  }

  Widget _buildEconomicCalendarSection() {
    return _buildFallbackEconomicCalendarSection(
      helperText:
          '실시간 API 대신 반복적으로 확인하는 핵심 정기 일정만 보여드려요. 실제 발표일은 기관 공지에 따라 조금씩 달라질 수 있어요.',
    );
  }

  Widget _buildFallbackEconomicCalendarSection({String? helperText}) {
    final events = _buildUpcomingEconomicEvents().take(6).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.event_note_rounded,
                  color: AppColors.accent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '정기 경제일정',
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '오늘 기준으로 가장 가까운 주요 발표를 먼저 보여줘요',
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: context.colors.surfaceLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'KST',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Container(
          //   width: double.infinity,
          //   padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          //   decoration: BoxDecoration(
          //     color: context.colors.surfaceLight,
          //     borderRadius: BorderRadius.circular(12),
          //   ),
          //   child: Text(
          //     helperText ??
          //         '실시간 캘린더 API 대신 반복적으로 확인하는 핵심 일정만 정리한 카드예요. 실제 발표일은 기관 공지에 따라 조금씩 달라질 수 있어요.',
          //     style: TextStyle(
          //       color: context.colors.textSecondary,
          //       fontSize: 11,
          //       fontWeight: FontWeight.w500,
          //       height: 1.45,
          //       letterSpacing: -0.15,
          //     ),
          //   ),
          // ),
          // const SizedBox(height: 14),
          ...List.generate(
            events.length,
            (index) => _buildEconomicTimelineItem(
              event: events[index],
              isLast: index == events.length - 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEconomicTimelineItem({
    required _EconomicCalendarEvent event,
    required bool isLast,
  }) {
    final countdown = _formatEconomicCountdown(event.scheduledAt);
    final isSoon = event.scheduledAt.difference(_koreaNow()).inHours < 24;

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatEconomicEventDate(event.scheduledAt),
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_weekdayLabel(event.scheduledAt.weekday)} · ${_formatEconomicEventTime(event.scheduledAt)}',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: event.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: event.color.withValues(alpha: 0.24),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 82,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: context.colors.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
              decoration: BoxDecoration(
                color: context.colors.surfaceLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: event.color.withValues(alpha: isSoon ? 0.34 : 0.18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(event.icon, size: 15, color: event.color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          event.title,
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: event.color.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          event.market,
                          style: TextStyle(
                            color: event.color,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    event.detail,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                      letterSpacing: -0.15,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.scheduleLabel,
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: event.color.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          countdown,
                          style: TextStyle(
                            color: event.color,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEconomicNewsSectionLabel() {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        '경제 뉴스',
        style: TextStyle(
          color: context.colors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  Widget _buildInlineEmptyCard(String message, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 24, color: context.colors.textSecondary),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshAiSummary({required bool countForAd}) async {
    if (_isRefreshingAiSummary || !mounted) {
      return;
    }

    setState(() => _isRefreshingAiSummary = true);

    try {
      ref.invalidate(stockMarketNewsProvider);
      ref.invalidate(allFinanceNewsProvider);
      ref.invalidate(marketIndicesProvider);

      final refreshedSummary = await ref.refresh(
        aiMarketSummaryProvider.future,
      );
      if (!mounted) {
        return;
      }

      if (refreshedSummary.trim().isEmpty) {
        _showToast('AI 요약 결과가 비어 있어요.', color: AppColors.orange);
        return;
      }

      _showToast('AI 요약을 새로고침했어요.');

      if (countForAd) {
        unawaited(maybeShowAiSummaryRefreshAd(context));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showToast('AI 요약을 새로고침하지 못했어요: $error', color: AppColors.red);
    } finally {
      if (mounted) {
        setState(() => _isRefreshingAiSummary = false);
      }
    }
  }

  // ── AI 한줄 요약 카드 ──────────────────────────
  Widget _buildAiSummaryCard() {
    return Consumer(
      builder: (context, ref, _) {
        final summaryAsync = ref.watch(aiMarketSummaryProvider);
        final isAiRefreshing = _isRefreshingAiSummary || summaryAsync.isLoading;
        return GestureDetector(
          onTap: summaryAsync.hasValue
              ? () => _showAiRelatedNewsSheet(
                  context,
                  ref,
                  summaryAsync.value!,
                  selectedSector: _selectedAiSector,
                  selectedSectorIsBull: _selectedAiSectorIsBull,
                )
              : null,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 14,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'AI',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (summaryAsync.hasValue)
                      Text(
                        '관련 뉴스 보기',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    const Spacer(),
                    if (summaryAsync.hasValue)
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 14,
                        color: context.colors.textSecondary,
                      ),
                    const SizedBox(width: 4),
                    if (isAiRefreshing)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AppColors.accent,
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: () => _refreshAiSummary(
                          countForAd: summaryAsync.hasValue,
                        ),
                        child: Icon(
                          Icons.refresh_rounded,
                          size: 16,
                          color: context.colors.textSecondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: summaryAsync.when(
                    data: (text) => SingleChildScrollView(
                      primary: false,
                      child: _buildHighlightedSummary(text),
                    ),
                    loading: () => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(
                        3,
                        (i) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Shimmer.fromColors(
                            baseColor: context.colors.surfaceLight,
                            highlightColor: context.colors.border,
                            child: Container(
                              height: 12,
                              width: i == 2 ? 160 : double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    error: (e, _) => GestureDetector(
                      onTap: () => _refreshAiSummary(countForAd: false),
                      child: Text(
                        AppConstants.geminiApiKey.isEmpty
                            ? 'Gemini API 키를 설정하면 AI 요약이 활성화됩니다'
                            : 'AI 요약 실패 — 탭하여 재시도',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// AI 요약 텍스트에서 핵심 키워드를 추출해 관련 뉴스를 모아 바텀시트로 표시
  void _showAiRelatedNewsSheet(
    BuildContext context,
    WidgetRef ref,
    String summaryText, {
    String? selectedSector,
    bool? selectedSectorIsBull,
  }) {
    // 요약 텍스트에서 단어 단위 키워드 추출 (2글자 이상 한글/영문)
    final keywords = RegExp(r'[가-힣a-zA-Z]{2,}')
        .allMatches(summaryText)
        .map((m) => m.group(0)!)
        .where((w) => !_aiStopWords.contains(w))
        .toSet()
        .toList();

    if (selectedSector != null && selectedSector.trim().isNotEmpty) {
      keywords.addAll(_extractSectorKeywords(selectedSector));

      final pickPattern = RegExp(r'^(강세추천|약세주의)\s+(코스피|코스닥|나스닥|코인)\s*:');
      final itemPattern = RegExp(r'^(.+?)(?:\[([^\]]+)\])?\((.+?)\)$');
      final trailingTickerPattern = RegExp(r'^(.*?)\s+([A-Z]{2,5})$');

      for (final line in summaryText.split('\n')) {
        final trimmed = line.trim();
        if (!pickPattern.hasMatch(trimmed)) continue;

        final pickMatch = pickPattern.firstMatch(trimmed);
        final sentiment = pickMatch?.group(1);
        if (selectedSectorIsBull != null) {
          final isBullLine = sentiment == '강세추천';
          if (isBullLine != selectedSectorIsBull) continue;
        }

        final rest = trimmed.replaceFirst(pickPattern, '').trim();
        final rawItems = rest.split(RegExp(r',\s*(?=[^)]*(?:\(|$))'));

        for (final rawItem in rawItems) {
          final item = rawItem.trim();
          if (item.isEmpty) continue;

          final match = itemPattern.firstMatch(item);
          if (match == null) continue;

          final rawName = match.group(1)?.trim() ?? '';
          final sectorTag = match.group(2)?.trim() ?? '';
          final reason = match.group(3)?.trim() ?? '';

          if (!_matchesSectorTag(selectedSector, sectorTag)) continue;

          final tickerMatch = trailingTickerPattern.firstMatch(rawName);
          final displayName = tickerMatch != null
              ? tickerMatch.group(1)!.trim()
              : rawName;

          keywords.add(displayName);
          keywords.addAll(_extractSectorKeywords(sectorTag));
          keywords.addAll(_extractSectorKeywords(reason));
        }
      }
    }

    final allNewsAsync = ref.read(allFinanceNewsProvider);
    final allNews = allNewsAsync.valueOrNull ?? [];

    // 키워드가 제목 또는 설명에 포함된 뉴스 필터링 (relevance score 순 정렬)
    final scored = <(int, FinanceNews)>[];
    for (final news in allNews) {
      final corpus = '${news.title} ${news.description}'.toLowerCase();
      final score = keywords
          .where((kw) => corpus.contains(kw.toLowerCase()))
          .length;
      if (score > 0) scored.add((score, news));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    final related = scored.take(30).map((e) => e.$2).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _AiRelatedNewsSheet(newsList: related, titleSuffix: selectedSector),
    );
  }

  static const _aiStopWords = {
    '분석',
    '요약',
    '하이라이트',
    '분석제목',
    '분석내용',
    '강세섹터',
    '약세섹터',
    '코스피',
    '코스닥',
    '나스닥',
    '코인',
    '주목',
    '섹터',
    '종목',
    '추천',
    '시장',
    '뉴스',
    '오늘',
    '현재',
    '전일',
    '전망',
    '상승',
    '하락',
    '기술',
    '금융',
    '에너지',
    '소비재',
    '산업재',
    'AI',
    'the',
    'and',
    'or',
    'of',
    'in',
    'is',
    'to',
  };

  String _normalizeAiText(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'[^0-9a-zA-Z가-힣]+'), ' ');
  }

  Set<String> _extractSectorKeywords(String sector) {
    final normalized = _normalizeAiText(sector).trim();
    final keywords = <String>{};

    if (normalized.isNotEmpty) {
      keywords.add(normalized);
    }

    for (final match in RegExp(r'[a-zA-Z]+|[가-힣]{2,}').allMatches(sector)) {
      final token = match.group(0)?.toLowerCase().trim() ?? '';
      if (token.length >= 2) {
        keywords.add(token);
      }
    }

    return keywords;
  }

  int _scorePickForSector({
    required String sector,
    required String market,
    required String name,
    required String sectorTag,
    required String reason,
  }) {
    final keywords = _extractSectorKeywords(sector);
    if (keywords.isEmpty) return 0;

    final corpus = _normalizeAiText('$market $name $sectorTag $reason');
    var score = 0;

    if (_matchesSectorTag(sector, sectorTag)) {
      score += 8;
    }

    for (final keyword in keywords) {
      if (corpus.contains(keyword)) {
        score += keyword.length >= 4 ? 3 : 2;
      }
    }

    if (corpus.contains(_normalizeAiText(sector))) {
      score += 4;
    }

    return score;
  }

  bool _matchesSectorTag(String selectedSector, String sectorTag) {
    if (sectorTag.trim().isEmpty) return false;

    final selectedKeywords = _extractSectorKeywords(selectedSector);
    final tagKeywords = _extractSectorKeywords(sectorTag);

    if (selectedKeywords.isEmpty || tagKeywords.isEmpty) {
      return false;
    }

    final selectedText = _normalizeAiText(selectedSector).trim();
    final tagText = _normalizeAiText(sectorTag).trim();

    return selectedKeywords.any((keyword) {
      if (keyword.length < 2) return false;
      return tagKeywords.contains(keyword) ||
          (selectedText.isNotEmpty && tagText == selectedText) ||
          (selectedText.isNotEmpty && tagText.contains(selectedText)) ||
          (tagText.isNotEmpty && selectedText.contains(tagText));
    });
  }

  // ── AI 요약 하이라이트 렌더러 ─────────────────────
  Widget _buildHighlightedSummary(String text) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();

    final highlightPattern = RegExp(r'^하이라이트\s*:');
    final analysisTitlePattern = RegExp(r'^분석제목\s*:');
    final analysisContentPattern = RegExp(r'^분석내용\s*:');
    final sectorPattern = RegExp(r'^(강세섹터|약세섹터)\s*:');
    final pickPattern = RegExp(r'^(강세추천|약세주의)\s+(코스피|코스닥|나스닥|코인)\s*:');

    final highlights = <String>[];
    final analysisTitles = <String>[];
    final analysisContents = <String>[];
    final sectorLines = <String>[];
    final pickLines = <String>[];

    for (final l in lines) {
      final t = l.trim();
      if (highlightPattern.hasMatch(t)) {
        highlights.add(t.replaceFirst(highlightPattern, '').trim());
      } else if (analysisTitlePattern.hasMatch(t)) {
        analysisTitles.add(t.replaceFirst(analysisTitlePattern, '').trim());
      } else if (analysisContentPattern.hasMatch(t)) {
        analysisContents.add(t.replaceFirst(analysisContentPattern, '').trim());
      } else if (sectorPattern.hasMatch(t)) {
        sectorLines.add(t);
      } else if (pickPattern.hasMatch(t)) {
        pickLines.add(t);
      }
    }

    final selectedSector = _selectedAiSector;
    final selectedSectorIsBull = _selectedAiSectorIsBull;

    /// **굵게** 마크다운을 파싱해 TextSpan 반환
    List<TextSpan> parseBold(String line, {TextStyle? base}) {
      final baseStyle =
          base ??
          TextStyle(
            color: context.colors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 1.55,
          );
      final spans = <TextSpan>[];
      final boldRegex = RegExp(r'\*\*(.+?)\*\*');
      int cursor = 0;
      for (final m in boldRegex.allMatches(line)) {
        if (m.start > cursor) {
          spans.add(
            TextSpan(text: line.substring(cursor, m.start), style: baseStyle),
          );
        }
        spans.add(
          TextSpan(
            text: m.group(1),
            style: baseStyle.copyWith(
              fontWeight: FontWeight.w800,
              color: context.colors.textPrimary,
            ),
          ),
        );
        cursor = m.end;
      }
      if (cursor < line.length) {
        spans.add(TextSpan(text: line.substring(cursor), style: baseStyle));
      }
      return spans.isEmpty ? [TextSpan(text: line, style: baseStyle)] : spans;
    }

    // ── 섹터 칩 줄 ──
    Widget buildSectorRow(String line) {
      final m = sectorPattern.firstMatch(line.trim());
      final label = m?.group(1) ?? '';
      final isBull = label == '강세섹터';
      final color = isBull ? AppColors.green : AppColors.red;
      final icon = isBull ? '▲' : '▼';
      final rest = line.trim().replaceFirst(sectorPattern, '').trim();
      final sectors = rest
          .split(RegExp(r'[,，、]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      return Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                icon,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Wrap(
                spacing: 4,
                runSpacing: 3,
                children: sectors.map((sector) {
                  final isSelected = selectedSector == sector;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedAiSector = isSelected ? null : sector;
                        _selectedAiSectorIsBull = isSelected ? null : isBull;
                        if (!isSelected) {
                          _showBullishAiPicks = isBull;
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? color.withValues(alpha: 0.18)
                            : color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isSelected
                              ? color.withValues(alpha: 0.75)
                              : color.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        sector,
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: isSelected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      );
    }

    final parsedPickRows = pickLines
        .map((line) {
          final m = pickPattern.firstMatch(line.trim());
          final sentiment = m?.group(1) ?? '';
          final marketLabel = m?.group(2) ?? '';
          final label = '$sentiment $marketLabel';
          final rest = line.trim().replaceFirst(pickPattern, '').trim();
          final isNasdaq = marketLabel == '나스닥';
          final isCoin = marketLabel == '코인';

          final itemPattern = RegExp(r'^(.+?)(?:\[([^\]]+)\])?\((.+?)\)$');
          final trailingTickerPattern = RegExp(r'^(.*?)\s+([A-Z]{2,5})$');
          final rawItems = rest.split(RegExp(r',\s*(?=[^)]*(?:\(|$))'));
          final items = rawItems
              .map((t) => t.trim())
              .where((t) => _isValidAiPickToken(t))
              .map((t) {
                final im = itemPattern.firstMatch(t);
                final rawName = im != null ? im.group(1)!.trim() : t;
                final sectorTag = im?.group(2)?.trim() ?? '';
                final tickerMatch = trailingTickerPattern.firstMatch(rawName);
                final coinEnglishKeyword = switch (rawName) {
                  '비트코인' => 'Bitcoin',
                  '비트코인 BTC' => 'BTC',
                  _ => null,
                };
                final displayName = isNasdaq && tickerMatch != null
                    ? tickerMatch.group(1)!.trim()
                    : rawName;
                final linkKeyword = isNasdaq && tickerMatch != null
                    ? tickerMatch.group(2)!.trim()
                    : isCoin && coinEnglishKeyword != null
                    ? coinEnglishKeyword
                    : rawName;
                final reason = im != null ? im.group(3)!.trim() : '';
                final sectorScore = selectedSector == null
                    ? 0
                    : _scorePickForSector(
                        sector: selectedSector,
                        market: marketLabel,
                        name: displayName,
                        sectorTag: sectorTag,
                        reason: reason,
                      );
                return (
                  name: displayName,
                  linkKeyword: linkKeyword,
                  sectorTag: sectorTag,
                  reason: reason,
                  sectorScore: sectorScore,
                );
              })
              .where((item) => _isValidAiPickToken(item.name))
              .toList();

          final matchesSentiment = selectedSectorIsBull == null
              ? true
              : (sentiment == '강세추천') == selectedSectorIsBull;

          final visibleItems = selectedSector == null
              ? items
              : (matchesSentiment
                      ? items.where((item) => item.sectorScore > 0).toList()
                      : <
                          ({
                            String name,
                            String linkKeyword,
                            String sectorTag,
                            String reason,
                            int sectorScore,
                          })
                        >[]
                  ..sort((a, b) => b.sectorScore.compareTo(a.sectorScore)));

          return (label: label, sentiment: sentiment, items: visibleItems);
        })
        .where((row) => row.items.isNotEmpty)
        .toList();

    final displayPickRows = selectedSector != null
        ? parsedPickRows
        : pickLines.map((line) {
            final m = pickPattern.firstMatch(line.trim());
            final sentiment = m?.group(1) ?? '';
            final marketLabel = m?.group(2) ?? '';
            final label = '$sentiment $marketLabel';
            final rest = line.trim().replaceFirst(pickPattern, '').trim();
            final isNasdaq = marketLabel == '나스닥';
            final isCoin = marketLabel == '코인';
            final itemPattern = RegExp(r'^(.+?)(?:\[([^\]]+)\])?\((.+?)\)$');
            final trailingTickerPattern = RegExp(r'^(.*?)\s+([A-Z]{2,5})$');
            final rawItems = rest.split(RegExp(r',\s*(?=[^)]*(?:\(|$))'));
            final items = rawItems
                .map((t) => t.trim())
                .where((t) => _isValidAiPickToken(t))
                .map((t) {
                  final im = itemPattern.firstMatch(t);
                  final rawName = im != null ? im.group(1)!.trim() : t;
                  final sectorTag = im?.group(2)?.trim() ?? '';
                  final tickerMatch = trailingTickerPattern.firstMatch(rawName);
                  final coinEnglishKeyword = switch (rawName) {
                    '비트코인' => 'Bitcoin',
                    '비트코인 BTC' => 'BTC',
                    _ => null,
                  };
                  final displayName = isNasdaq && tickerMatch != null
                      ? tickerMatch.group(1)!.trim()
                      : rawName;
                  final linkKeyword = isNasdaq && tickerMatch != null
                      ? tickerMatch.group(2)!.trim()
                      : isCoin && coinEnglishKeyword != null
                      ? coinEnglishKeyword
                      : rawName;
                  final reason = im != null ? im.group(3)!.trim() : '';
                  return (
                    name: displayName,
                    linkKeyword: linkKeyword,
                    sectorTag: sectorTag,
                    reason: reason,
                    sectorScore: 0,
                  );
                })
                .where((item) => _isValidAiPickToken(item.name))
                .toList();
            return (label: label, sentiment: sentiment, items: items);
          }).toList();

    final hasSectorFilteredPicks =
        selectedSector != null && parsedPickRows.isNotEmpty;

    Widget buildPickRow(
      ({
        String label,
        String sentiment,
        List<
          ({
            String name,
            String linkKeyword,
            String sectorTag,
            String reason,
            int sectorScore,
          })
        >
        items,
      })
      row,
      bool isLast,
    ) {
      final marketLabel = row.label.split(' ').last;
      final items = row.items;
      final isBullishRow = row.sentiment == '강세추천';
      final accentColor = isBullishRow ? AppColors.green : AppColors.red;

      return Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      marketLabel,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${items.length}개 종목',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: items
                      .map(
                        (item) => GestureDetector(
                          onTap: () {
                            final url =
                                'https://m.stock.naver.com/searchItem?keyword=${Uri.encodeComponent(item.linkKeyword)}';
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NewsWebViewScreen(
                                  url: url,
                                  title: '${item.name} 주가',
                                ),
                              ),
                            );
                          },
                          child: Container(
                            width: 156,
                            height: 124,
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                            decoration: BoxDecoration(
                              color: context.colors.surfaceLight,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: accentColor.withValues(alpha: 0.16),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.name,
                                        style: TextStyle(
                                          color: context.colors.textPrimary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.3,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.open_in_new_rounded,
                                      size: 12,
                                      color: context.colors.textSecondary,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 25,
                                  child: item.sectorTag.isNotEmpty
                                      ? Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 7,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: accentColor.withValues(
                                                alpha: 0.08,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              item.sectorTag,
                                              style: TextStyle(
                                                color: accentColor,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: Text(
                                    item.reason.isNotEmpty
                                        ? item.reason
                                        : '관련 뉴스 흐름을 반영한 종목입니다.',
                                    style: TextStyle(
                                      color: context.colors.textSecondary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      height: 1.4,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildPickSection({
      required String title,
      required String subtitle,
      required IconData icon,
      required List<
        ({
          String label,
          String sentiment,
          List<
            ({
              String name,
              String linkKeyword,
              String sectorTag,
              String reason,
              int sectorScore,
            })
          >
          items,
        })
      >
      rows,
      required String emptyText,
    }) {
      final isBullishSection = title == '강세추천';
      final accentColor = isBullishSection ? AppColors.green : AppColors.red;

      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: context.colors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 14, color: accentColor),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: context.colors.border),
                  ),
                  child: Text(
                    '${rows.length}개 시장',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.colors.border),
                ),
                child: Text(
                  emptyText,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            else
              ...List.generate(
                rows.length,
                (i) => buildPickRow(rows[i], i == rows.length - 1),
              ),
          ],
        ),
      );
    }

    final bullishRows = displayPickRows
        .where((row) => row.sentiment == '강세추천')
        .toList();
    final bearishRows = displayPickRows
        .where((row) => row.sentiment == '약세주의')
        .toList();
    final activeRows = _showBullishAiPicks ? bullishRows : bearishRows;
    final activeTitle = _showBullishAiPicks ? '강세추천' : '약세주의';
    final activeSubtitle = _showBullishAiPicks
        ? (selectedSector == null ? '상승 모멘텀 중심 종목' : '선택한 강세 섹터와 연결된 종목')
        : (selectedSector == null ? '회피 또는 하락 압력 점검 종목' : '선택한 약세 섹터와 연결된 종목');
    final activeEmptyText = _showBullishAiPicks
        ? (selectedSector == null
              ? '강세추천 종목이 없습니다.'
              : '선택한 섹터와 맞는 강세추천 종목이 없습니다.')
        : (selectedSector == null
              ? '약세주의 종목이 없습니다.'
              : '선택한 섹터와 맞는 약세주의 종목이 없습니다.');
    final activeIcon = _showBullishAiPicks
        ? Icons.north_east_rounded
        : Icons.south_east_rounded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 하이라이트 섹션 ──
        if (highlights.isNotEmpty) ...[
          const Row(
            children: [
              Icon(Icons.bolt_rounded, size: 11, color: AppColors.accent),
              SizedBox(width: 3),
              Text(
                '하이라이트',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: context.colors.surfaceLight,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: highlights
                  .map(
                    (h) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '•',
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 11,
                              height: 1.55,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: RichText(
                              text: TextSpan(children: parseBold(h)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // ── 분석 섹션 ──
        if (analysisTitles.isNotEmpty) ...[
          Row(
            children: [
              Icon(
                Icons.bar_chart_rounded,
                size: 11,
                color: context.colors.textSecondary,
              ),
              const SizedBox(width: 3),
              Text(
                '분석',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...List.generate(analysisTitles.length, (i) {
            final title = analysisTitles[i];
            final content = i < analysisContents.length
                ? analysisContents[i]
                : '';
            return Padding(
              padding: EdgeInsets.only(
                bottom: i < analysisTitles.length - 1 ? 8 : 0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (content.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    RichText(text: TextSpan(children: parseBold(content))),
                  ],
                ],
              ),
            );
          }),
          const SizedBox(height: 10),
        ],

        // ── 섹터 ──
        if (sectorLines.isNotEmpty) ...[
          Divider(height: 10, thickness: 0.5, color: context.colors.border),
          const SizedBox(height: 1),
          Row(
            children: [
              const Icon(
                Icons.grid_view_rounded,
                size: 10,
                color: AppColors.accent,
              ),
              const SizedBox(width: 4),
              const Text(
                '주목 섹터',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (selectedSector != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => setState(() {
                    _selectedAiSector = null;
                    _selectedAiSectorIsBull = null;
                  }),
                  child: Text(
                    '전체 보기',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 5),
          ...sectorLines.map(buildSectorRow),
        ],

        // ── 추천 종목 ──
        if (pickLines.isNotEmpty) ...[
          Divider(height: 10, thickness: 0.5, color: context.colors.border),
          const SizedBox(height: 1),
          Row(
            children: [
              const Icon(Icons.star_rounded, size: 10, color: AppColors.accent),
              const SizedBox(width: 4),
              const Text(
                '추천 종목',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (selectedSector != null) ...[
                const SizedBox(width: 6),
                Text(
                  '${selectedSectorIsBull == true ? '강세' : '약세'} · $selectedSector',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          if (selectedSector != null && !hasSectorFilteredPicks)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '선택한 섹터와 직접 연결된 추천 종목이 없습니다.',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          const SizedBox(height: 2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: context.colors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildPickToggleTab(
                    label: '강세추천',
                    isSelected: _showBullishAiPicks,
                    onTap: () => setState(() => _showBullishAiPicks = true),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildPickToggleTab(
                    label: '약세주의',
                    isSelected: !_showBullishAiPicks,
                    onTap: () => setState(() => _showBullishAiPicks = false),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (!_showBullishAiPicks && bearishRows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '약세주의가 비어 있으면 AI가 악재 연결을 약하게 본 경우가 많아요. 새로고침하면 다시 계산합니다.',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ),
          buildPickSection(
            title: activeTitle,
            subtitle: activeSubtitle,
            icon: activeIcon,
            rows: activeRows,
            emptyText: activeEmptyText,
          ),
        ],
      ],
    );
  }

  Widget _buildPickToggleTab({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? context.colors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected
                ? context.colors.textPrimary
                : context.colors.textSecondary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }

  bool _isValidAiPickToken(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return false;
    return normalized != '-' &&
        normalized != '없음' &&
        normalized != '없음.' &&
        normalized != '해당 없음' &&
        normalized != '미제공';
  }

  // ── 마켓 인덱스 가로 스크롤 ────────────────────
  Widget _buildMarketIndicesRow() {
    return Consumer(
      builder: (context, ref, _) {
        final indicesAsync = ref.watch(marketIndicesProvider);
        final isLoading = indicesAsync.isLoading;
        final indices =
            indicesAsync.valueOrNull ??
            (indicesAsync.hasError ? _fallbackIndices : []);
        return _MarketTickerBar(indices: indices, isLoading: isLoading);
      },
    );
  }

  // ── 탭 바 ──────────────────────────────────────
  Widget _buildTabBar() {
    const tabDefs = [
      (0, '속보', AppColors.green, 'LIVE'),
      (1, '키워드', AppColors.info, 'MY'),
      (2, '전쟁', AppColors.red, null),
      (3, '코스피', Color(0xFF3B82F6), null),
      (4, '코스닥', Color(0xFF14B8A6), null),
      (5, '나스닥', Color(0xFFF59E0B), null),
      (6, '코인', Color(0xFFF7931A), null),
    ];

    return Container(
      color: context.colors.bg,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: AnimatedBuilder(
        animation: _tabController!,
        builder: (context, _) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < tabDefs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _buildPillTab(
                    tabDefs[i].$1,
                    tabDefs[i].$2,
                    tabDefs[i].$3,
                    tabDefs[i].$4,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPillTab(int index, String label, Color color, String? badge) {
    final isSelected = _tabController!.index == index;
    final foregroundColor = isSelected
        ? context.colors.textPrimary
        : context.colors.textSecondary;

    return GestureDetector(
      onTap: () => _tabController!.animateTo(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.08)
              : context.colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? color.withValues(alpha: 0.34)
                : context.colors.border,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: isSelected ? color : color.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: -0.3,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: 0.14)
                      : context.colors.surfaceLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: isSelected ? color : context.colors.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── 속보 탭 (importanceLevel 4+, 신뢰 언론 or 증시 고관련) ─────
  Widget _buildStockNewsTab() {
    return Consumer(
      builder: (context, ref, child) {
        final newsAsync = ref.watch(breakingNewsProvider);
        return RefreshIndicator(
          color: AppColors.green,
          backgroundColor: context.colors.surface,
          onRefresh: () async {
            ref.invalidate(breakingNewsProvider);
            ref.invalidate(stockMarketNewsProvider);
            _showToast('속보 뉴스 새로고침 중…');
          },
          child: newsAsync.when(
            data: (news) {
              if (news.isEmpty) {
                return _buildEmptyState('중요 속보가 없습니다', Icons.article_outlined);
              }
              return ListView.builder(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 32),
                itemCount: news.length + 1,
                itemBuilder: (ctx, index) {
                  if (index == 0) return _buildBreakingHeader();
                  final item = news[index - 1];
                  final publishedAt = item.publishedAt as DateTime?;
                  final isNew =
                      publishedAt != null &&
                      DateTime.now().difference(publishedAt).inMinutes < 10;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Stack(
                      children: [
                        _FinanceNewsCard(
                          item: item,
                          detailContextLabel: '속보 탭',
                        ),
                        if (isNew)
                          Positioned(
                            top: 10,
                            right: 14,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.red,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'NEW',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(
                color: AppColors.green,
                strokeWidth: 2,
              ),
            ),
            error: (e, _) => _buildEmptyState('오류: $e', Icons.error_outline),
          ),
        );
      },
    );
  }

  Widget _buildBreakingHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(child: _FinanceLiveIndicator(isSelected: true)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '속보',
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.green.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'LIVE',
                        style: TextStyle(
                          color: AppColors.green,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '중요도 높은 기사만 먼저 정리해 보여줘요',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 전쟁·지정학 탭 ────────────────────────────
  Widget _buildWarNewsTab() {
    return Consumer(
      builder: (context, ref, child) {
        final newsAsync = ref.watch(warNewsProvider);
        return RefreshIndicator(
          color: AppColors.red,
          backgroundColor: context.colors.surface,
          onRefresh: () async {
            ref.invalidate(warNewsProvider);
            _showToast('전쟁·지정학 뉴스 새로고침 중…');
          },
          child: newsAsync.when(
            data: (news) {
              if (news.isEmpty) {
                return _buildEmptyState(
                  '전쟁·지정학 뉴스가 없습니다',
                  Icons.public_outlined,
                );
              }
              final sorted = [...news]
                ..sort((a, b) => (b.publishedAt).compareTo(a.publishedAt));
              return ListView.separated(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: sorted.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) => _FinanceNewsCard(
                  item: sorted[index],
                  detailContextLabel: '전쟁 탭',
                ),
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(
                color: AppColors.red,
                strokeWidth: 2,
              ),
            ),
            error: (e, _) => _buildEmptyState('오류: $e', Icons.error_outline),
          ),
        );
      },
    );
  }

  // ── 코스닥 탭 ─────────────────────────────────
  Widget _buildKosdaqTab() {
    return Consumer(
      builder: (context, ref, child) {
        final newsAsync = ref.watch(kosdaqNewsProvider);
        return RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: context.colors.surface,
          onRefresh: () async {
            ref.invalidate(kosdaqNewsProvider);
            _showToast('코스닥 뉴스 새로고침 중…');
          },
          child: newsAsync.when(
            data: (news) {
              if (news.isEmpty) {
                return _buildEmptyState('코스닥 뉴스가 없습니다', Icons.show_chart);
              }
              final sorted = [...news]
                ..sort((a, b) => (b.publishedAt).compareTo(a.publishedAt));
              return ListView.separated(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: sorted.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) => _FinanceNewsCard(
                  item: sorted[index],
                  detailContextLabel: '코스닥 탭',
                ),
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(
                color: AppColors.accent,
                strokeWidth: 2,
              ),
            ),
            error: (e, _) => _buildEmptyState('오류: $e', Icons.error_outline),
          ),
        );
      },
    );
  }

  // ── 코스피 탭 ─────────────────────────────────
  Widget _buildKospiTab() {
    return Consumer(
      builder: (context, ref, child) {
        final newsAsync = ref.watch(kospiNewsProvider);
        return RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: context.colors.surface,
          onRefresh: () async {
            ref.invalidate(kospiNewsProvider);
            _showToast('코스피 뉴스 새로고침 중…');
          },
          child: newsAsync.when(
            data: (news) {
              if (news.isEmpty) {
                return _buildEmptyState('코스피 뉴스가 없습니다', Icons.show_chart);
              }
              final sorted = [...news]
                ..sort((a, b) => (b.publishedAt).compareTo(a.publishedAt));
              return ListView.separated(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: sorted.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) => _FinanceNewsCard(
                  item: sorted[index],
                  detailContextLabel: '코스피 탭',
                ),
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(
                color: AppColors.accent,
                strokeWidth: 2,
              ),
            ),
            error: (e, _) => _buildEmptyState('오류: $e', Icons.error_outline),
          ),
        );
      },
    );
  }

  // ── 나스닥 탭 ─────────────────────────────────
  Widget _buildNasdaqTab() {
    return Consumer(
      builder: (context, ref, child) {
        final newsAsync = ref.watch(nasdaqNewsProvider);
        return RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: context.colors.surface,
          onRefresh: () async {
            ref.invalidate(nasdaqNewsProvider);
            _showToast('나스닥 뉴스 새로고침 중…');
          },
          child: newsAsync.when(
            data: (news) {
              if (news.isEmpty) {
                return _buildEmptyState('나스닥 뉴스가 없습니다', Icons.show_chart);
              }
              final sorted = [...news]
                ..sort((a, b) => (b.publishedAt).compareTo(a.publishedAt));
              return ListView.separated(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: sorted.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) => _FinanceNewsCard(
                  item: sorted[index],
                  detailContextLabel: '나스닥 탭',
                ),
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(
                color: AppColors.accent,
                strokeWidth: 2,
              ),
            ),
            error: (e, _) => _buildEmptyState('오류: $e', Icons.error_outline),
          ),
        );
      },
    );
  }

  // ── 코인 탭 ───────────────────────────────────
  Widget _buildCoinTab() {
    return Consumer(
      builder: (context, ref, child) {
        final newsAsync = ref.watch(coinNewsProvider);
        return RefreshIndicator(
          color: const Color(0xFFF7931A),
          backgroundColor: context.colors.surface,
          onRefresh: () async {
            ref.invalidate(coinNewsProvider);
            _showToast('코인 뉴스 새로고침 중…');
          },
          child: newsAsync.when(
            data: (news) {
              if (news.isEmpty) {
                return _buildEmptyState('코인 뉴스가 없습니다', Icons.currency_bitcoin);
              }
              final sorted = [...news]
                ..sort((a, b) => (b.publishedAt).compareTo(a.publishedAt));
              return ListView.separated(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: sorted.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) => _FinanceNewsCard(
                  item: sorted[index],
                  detailContextLabel: '코인 탭',
                ),
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFF7931A),
                strokeWidth: 2,
              ),
            ),
            error: (e, _) => _buildEmptyState('오류: $e', Icons.error_outline),
          ),
        );
      },
    );
  }

  // ── 경제 탭 ───────────────────────────────────
  Widget _buildEconomicTab() {
    return Consumer(
      builder: (context, ref, child) {
        final newsAsync = ref.watch(economicNewsProvider);
        return RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: context.colors.surface,
          onRefresh: () async {
            ref.invalidate(economicNewsProvider);
            _showToast('경제 뉴스 새로고침 중…');
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _buildEconomicCalendarSection(),
              const SizedBox(height: 18),
              _buildEconomicNewsSectionLabel(),
              const SizedBox(height: 8),
              ...newsAsync.when(
                data: (news) {
                  final sorted = [...news]
                    ..sort((a, b) => (b.publishedAt).compareTo(a.publishedAt));

                  if (sorted.isEmpty) {
                    return [
                      _buildInlineEmptyCard(
                        '경제 뉴스가 아직 없습니다',
                        Icons.business_outlined,
                      ),
                    ];
                  }

                  return List.generate(
                    sorted.length,
                    (index) => Padding(
                      padding: EdgeInsets.only(
                        bottom: index == sorted.length - 1 ? 0 : 6,
                      ),
                      child: _FinanceNewsCard(
                        item: sorted[index],
                        detailContextLabel: '경제 탭',
                      ),
                    ),
                  );
                },
                loading: () => [
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(
                        color: AppColors.accent,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                ],
                error: (e, _) => [
                  _buildInlineEmptyCard('오류: $e', Icons.error_outline),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 44, color: context.colors.border),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 폴백 더미 데이터 (API 오류 시 표시)
// ─────────────────────────────────────────────
final _fallbackIndices = [
  MarketIndex(
    symbol: '^KS11',
    name: '코스피',
    price: 0,
    change: 0,
    changeAmt: 0,
    currency: 'KRW',
    updatedAt: DateTime(2000),
  ),
  MarketIndex(
    symbol: '^KQ11',
    name: '코스닥',
    price: 0,
    change: 0,
    changeAmt: 0,
    currency: 'KRW',
    updatedAt: DateTime(2000),
  ),
  MarketIndex(
    symbol: '^IXIC',
    name: '나스닥',
    price: 0,
    change: 0,
    changeAmt: 0,
    currency: 'USD',
    updatedAt: DateTime(2000),
  ),
  MarketIndex(
    symbol: '^GSPC',
    name: 'S&P 500',
    price: 0,
    change: 0,
    changeAmt: 0,
    currency: 'USD',
    updatedAt: DateTime(2000),
  ),
  MarketIndex(
    symbol: 'KRW=X',
    name: '달러/원',
    price: 0,
    change: 0,
    changeAmt: 0,
    currency: 'KRW',
    updatedAt: DateTime(2000),
  ),
  MarketIndex(
    symbol: 'CL=F',
    name: '국제유가',
    price: 0,
    change: 0,
    changeAmt: 0,
    currency: 'USD',
    updatedAt: DateTime(2000),
  ),
];

// ─────────────────────────────────────────────
// 마켓 티커 바 (자동 무한 스크롤)
// ─────────────────────────────────────────────
class _MarketTickerBar extends StatefulWidget {
  final List<MarketIndex> indices;
  final bool isLoading;
  const _MarketTickerBar({required this.indices, this.isLoading = false});
  @override
  State<_MarketTickerBar> createState() => _MarketTickerBarState();
}

class _MarketTickerBarState extends State<_MarketTickerBar>
    with TickerProviderStateMixin {
  late AnimationController _ctrl;
  final _measureKey = GlobalKey();
  double _measuredWidth = 0;

  // 스크롤 속도 (px/s)
  static const double _speed = 52.0;

  @override
  void initState() {
    super.initState();
    // 주스 임시 컨트롤러 — 첫 프레임 후 컨트롤러 재생성
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    WidgetsBinding.instance.addPostFrameCallback(_measureAndStart);
  }

  void _measureAndStart(_) {
    final box = _measureKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final w = box.size.width;
    if (w <= 0 || w == _measuredWidth) return;
    _measuredWidth = w;
    _ctrl.dispose();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (w / _speed * 1000).round()),
    )..repeat();
    if (mounted) setState(() {});
  }

  double get _totalWidth => _measuredWidth;

  @override
  void didUpdateWidget(_MarketTickerBar old) {
    super.didUpdateWidget(old);
    if (old.indices != widget.indices) {
      WidgetsBinding.instance.addPostFrameCallback(_measureAndStart);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = context.colors.border;

    return Container(
      height: 38,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0E0E0E) : const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Row(
        children: [
          // LIVE 배지
          // Padding(
          //   padding: const EdgeInsets.symmetric(horizontal: 10),
          //   child: Container(
          //     padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          //     decoration: BoxDecoration(
          //       color: AppColors.red,
          //       borderRadius: BorderRadius.circular(3),
          //     ),
          //     child: const Text(
          //       'LIVE',
          //       style: TextStyle(
          //         color: Colors.white,
          //         fontSize: 8,
          //         fontWeight: FontWeight.w900,
          //         letterSpacing: 0.8,
          //       ),
          //     ),
          //   ),
          // ),
          // Container(width: 0.5, height: 16, color: borderColor),
          // 티커 스크롤 영역
          Expanded(
            child: ClipRect(
              child: widget.isLoading || widget.indices.isEmpty
                  ? _buildLoadingRow(context)
                  : AnimatedBuilder(
                      animation: _ctrl,
                      builder: (context, child) {
                        final offset = _ctrl.value * _totalWidth;
                        return OverflowBox(
                          maxWidth: double.infinity,
                          alignment: Alignment.centerLeft,
                          child: Transform.translate(
                            offset: Offset(-offset, 0),
                            child: child,
                          ),
                        );
                      },
                      // 원본(측정용) + 복사본을 이어 붙여 원형 루프 구현
                      child: Row(
                        key: _measureKey,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final idx in [
                            ...widget.indices,
                            ...widget.indices,
                          ])
                            _TickerItem(index: idx),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingRow(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Row(
        children: List.generate(
          5,
          (i) => Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Container(
              width: 80,
              height: 12,
              decoration: BoxDecoration(
                color: context.colors.surfaceLight,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 개별 티커 아이템 (한 줄 컴팩트) ──────────────
class _TickerItem extends StatelessWidget {
  final MarketIndex index;
  const _TickerItem({required this.index});

  @override
  Widget build(BuildContext context) {
    final isError = index.price == 0 && index.updatedAt.year == 2000;
    final isUp = index.isUp;
    final changeColor = isUp ? AppColors.green : AppColors.red;
    final borderColor = context.colors.border;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 8),
        // 방향 인디케이터 바
        if (!isError)
          //   Container(
          //     width: 2,
          //     height: 12,
          //     margin: const EdgeInsets.only(right: 4),
          //   decoration: BoxDecoration(
          //     color: changeColor,
          //     borderRadius: BorderRadius.circular(1),
          //   ),
          // ),
          // 이름
          Text(
            index.name,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        const SizedBox(width: 5),
        // 현재가
        Text(
          isError ? '-' : index.formattedPrice,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        if (!isError) ...[
          const SizedBox(width: 3),
          Text(
            index.formattedChange,
            style: TextStyle(
              color: changeColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(width: 8),
        // 구분선
        Container(width: 0.5, height: 14, color: borderColor),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// 통계: 강세/약세 게이지 카드
// ─────────────────────────────────────────────
class _StatsGaugeCard extends StatelessWidget {
  final int bullCount;
  final int bearCount;
  final int bullPct;
  final int bearPct;
  final int total;

  const _StatsGaugeCard({
    required this.bullCount,
    required this.bearCount,
    required this.bullPct,
    required this.bearPct,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '시장 통계',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '총 $total건',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 게이지 바
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                Flexible(
                  flex: bullCount == 0 && bearCount == 0 ? 1 : bullPct,
                  child: Container(height: 12, color: AppColors.green),
                ),
                Flexible(
                  flex: bullCount == 0 && bearCount == 0
                      ? 1
                      : bearPct.clamp(1, 100),
                  child: Container(height: 12, color: AppColors.red),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _GaugeLegend(
                label: '매수(강세)',
                count: bullCount,
                pct: bullPct,
                color: AppColors.green,
                align: CrossAxisAlignment.start,
              ),
              _GaugeLegend(
                label: '매도(약세)',
                count: bearCount,
                pct: bearPct,
                color: AppColors.red,
                align: CrossAxisAlignment.end,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugeLegend extends StatelessWidget {
  final String label;
  final int count;
  final int pct;
  final Color color;
  final CrossAxisAlignment align;

  const _GaugeLegend({
    required this.label,
    required this.count,
    required this.pct,
    required this.color,
    required this.align,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Row(
          children: [
            if (align == CrossAxisAlignment.start) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (align == CrossAxisAlignment.end) ...[
              const SizedBox(width: 5),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Text(
          '$count건',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        Text(
          '$pct%',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// 통계: 수치 요약 카드
// ─────────────────────────────────────────────
class _StatValueCard extends StatelessWidget {
  final String label;
  final String value;
  final int pct;
  final Color color;
  final IconData icon;

  const _StatValueCard({
    required this.label,
    required this.value,
    required this.pct,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '전체의 $pct%',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 통계: 인덱스별 통계 모델
// ─────────────────────────────────────────────
class _IndexStat {
  final String name;
  final int bull;
  final int bear;
  final double marketChange;
  const _IndexStat(this.name, this.bull, this.bear, this.marketChange);
}

// ─────────────────────────────────────────────
// 통계: 인덱스별 강세/약세 Row
// ─────────────────────────────────────────────
class _IndexStatRow extends StatelessWidget {
  final _IndexStat stat;
  const _IndexStatRow({required this.stat});

  @override
  Widget build(BuildContext context) {
    final total = stat.bull + stat.bear;
    final bullPct = total == 0 ? 50 : ((stat.bull / total) * 100).round();
    final bearPct = 100 - bullPct;
    final isUp = stat.marketChange >= 0;
    final changeColor = isUp ? AppColors.green : AppColors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                stat.name,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Icon(
                isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                color: changeColor,
                size: 16,
              ),
              Text(
                '${isUp ? '+' : ''}${stat.marketChange.toStringAsFixed(2)}%',
                style: TextStyle(
                  color: changeColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                Flexible(
                  flex: bullPct == 0 ? 1 : bullPct,
                  child: Container(height: 6, color: AppColors.green),
                ),
                Flexible(
                  flex: bearPct == 0 ? 1 : bearPct,
                  child: Container(height: 6, color: AppColors.red),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '강세 $bullPct%',
                style: const TextStyle(
                  color: AppColors.green,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '약세 $bearPct%',
                style: const TextStyle(
                  color: AppColors.red,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '총 $total건',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 통계: 섹션 헤더
// ─────────────────────────────────────────────
class _StatsSectionHeader extends StatelessWidget {
  final String label;
  final Color color;

  const _StatsSectionHeader({
    required this.label,
    this.color = AppColors.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// 뉴스 카드
// ─────────────────────────────────────────────
class _FinanceNewsCard extends StatelessWidget {
  final dynamic item;
  final String? detailContextLabel;

  const _FinanceNewsCard({required this.item, this.detailContextLabel});

  // 더 길고 정확한 키가 먼저 와야 부분일치 방지
  static const _sourceMap = {
    // ▶ 한국 주요 일간지
    'chosunilbo': '조선일보',
    'sportschosun': '스포츠조선',
    'tvchosun': 'TV조선',
    'chosun': '조선일보',
    'joongang': '중앙일보',
    'joins': '중앙일보',
    'donga': '동아일보',
    'sportsdonga': '스포츠동아',
    'hankookilbo': '한국일보',
    'hankooki': '한국일보',
    'hani': '한겨례',
    'khan': '경향신문',
    'munhwa': '문화일보',
    'segye': '세계일보',
    'm-in': '매일일보',
    'kmib': '국민일보',
    'seoul': '서울신문',
    'naeil': '내일신문',
    'imaeil': '매일신문',
    'busan': '부산일보',
    // ▶ 한국 경제지
    'hankyung': '한국경제',
    'mk': '매일경제',
    'maeil': '매일경제',
    'mt': '머니투데이',
    'moneytoday': '머니투데이',
    'money today': '머니투데이',
    'sedaily': '서울경제',
    'seoul economic': '서울경제',
    'edaily': '이데일리',
    'asiae': '아시아경제',
    'heraldcorp': '헤럴드경제',
    'herald': '헤럴드경제',
    'fnnews': '파이낸셜뉴스',
    'ajunews': '아주경제',
    'businesspost': '비즈니스포스트',
    'thebell': '더벨',
    'inews24': '아이뉴스24',
    'newspim': '뉴스핌',
    'dealsites': '딜사이트',
    'dealsitetv': '딜사이트TV',
    'newsway': '뉴스웨이',
    'econonews': '이코노뉴스',
    'topstarnews': '톱스타뉴스',
    'ebn': 'EBN',
    'etoday': '이투데이',
    'junggil': '중기이코노미',
    'newsfc': '금융소비자뉴스',
    'viva100': '브릿지경제',
    'gukjnews': '국제뉴스',
    'mstoday': 'MS투데이',
    'bntnews': 'BNT뉴스',
    'newstomato': '뉴스토마토',
    'm-i': '매일일보',
    'mhns': '더쎈뉴스',
    'g-enews': '글로벌이코노믹',
    'theguru': '더구루',
    'mediapen': '미디어펜',
    'gokorea': '공감신문',
    // ▶ 한국 IT·전문지
    'etnews': '전자신문',
    'dt': '디지털타임스',
    'zdnet': 'ZDNet코리아',
    'bloter': '블로터',
    'itchosun': 'IT조선',
    // ▶ 한국 방송·통신
    'yonhapnewstv': '연합뉴스TV',
    'yonhapnews': '연합뉴스',
    'yonhap news agency': '연합뉴스',
    'yonhap news': '연합뉴스',
    'yonhap': '연합뉴스',
    'yna': '연합뉴스',
    'news1': '뉴스1',
    'newsis': '뉴시스',
    'kbs': 'KBS',
    'mbc': 'MBC',
    'sbs': 'SBS',
    'jtbc': 'JTBC',
    'ichannela': '채널A',
    'mbn': 'MBN',
    'ytn': 'YTN',
    'ohmynews': '오마이뉴스',
    'pressian': '프레시안',
    'dailian': '데일리안',
    'nocutnews': '노컷뉴스',
    'mediatoday': '미디어오늘',
    'sisain': '시사인',
    'sportseoul': '스포츠서울',
    'isplus': '일간스포츠',
    'startuptoday': '스타트업투데이',
    'einfomax': '연합인포맥스',
    'korea herald': '코리아헤럴드',
    'korea times': '코리아타임스',
    'korea joongang': '중앙일보',
    'hankyoreh': '한겨례',
    // ▶ 해외 주요 언론
    'reuters': '로이터',
    'bloomberg': '블룸버그',
    'cnbc': 'CNBC',
    'wsj': 'WSJ',
    'wall street journal': 'WSJ',
    'financial times': 'FT',
    'ft': 'FT',
    'associated press': 'AP통신',
    'ap news': 'AP통신',
    'nikkei': '닛케이',
    'marketwatch': '마켓워치',
    'seeking alpha': '시킹알파',
    'barrons': '배런스',
    'forbes': '포브스',
    'business insider': '비즈인사이더',
    'the economist': '이코노미스트',
    'bbc': 'BBC',
    'nytimes': 'NYT',
    'huffpost': '허프포스트',
    'investopedia': '인베스토피디아',
    'coinreaders': '코인리더스',
    'asiatime': '아시아타임즈',
    'tokenpost': '토큰포스트',
  };

  static const _faviconDomainMap = {
    // 일간지
    'chosunilbo': 'chosun.com',
    'sportschosun': 'sportschosun.com',
    'tvchosun': 'tvchosun.com',
    'chosun': 'chosun.com',
    'joongang': 'joongang.co.kr',
    'joins': 'joins.com',
    'donga': 'donga.com',
    'sportsdonga': 'donga.com',
    'hankookilbo': 'hankookilbo.com',
    'hankooki': 'hankooki.com',
    'hani': 'hani.co.kr',
    'khan': 'khan.co.kr',
    'munhwa': 'munhwa.com',
    'segye': 'segye.com',
    'kukinews': 'kukinews.com',
    'seoul': 'seoul.co.kr',
    'naeil': 'naeil.com',
    'imaeil': 'imaeil.com',
    'busan': 'busan.com',
    // 경제지
    'hankyung': 'hankyung.com',
    'mk': 'mk.co.kr',
    'maeil': 'maeil.com',
    'mt': 'mt.co.kr',
    'moneytoday': 'mt.co.kr',
    'money today': 'mt.co.kr',
    'sedaily': 'sedaily.com',
    'edaily': 'edaily.co.kr',
    'asiae': 'asiae.co.kr',
    'heraldcorp': 'heraldcorp.com',
    'fnnews': 'fnnews.com',
    'ajunews': 'ajunews.com',
    'businesspost': 'businesspost.co.kr',
    'thebell': 'thebell.co.kr',
    'newspim': 'newspim.com',
    // IT·전문
    'etnews': 'etnews.com',
    'dt': 'dt.co.kr',
    'zdnet': 'zdnet.co.kr',
    'bloter': 'bloter.net',
    'itchosun': 'it.chosun.com',
    // 방송·통신
    'yonhapnewstv': 'yonhapnewstv.co.kr',
    'yonhapnews': 'yna.co.kr',
    'yonhap': 'yna.co.kr',
    'yna': 'yna.co.kr',
    'news1': 'news1.kr',
    'newsis': 'newsis.com',
    'kbs': 'kbs.co.kr',
    'mbc': 'mbc.co.kr',
    'sbs': 'sbs.co.kr',
    'jtbc': 'jtbc.co.kr',
    'ichannela': 'ichannela.com',
    'mbn': 'mbn.co.kr',
    'ytn': 'ytn.co.kr',
    'ohmynews': 'ohmynews.com',
    'pressian': 'pressian.com',
    'dailian': 'dailian.co.kr',
    'nocutnews': 'nocutnews.co.kr',
    'mediatoday': 'mediatoday.co.kr',
    'sisain': 'sisain.co.kr',
    'sportseoul': 'sportseoul.com',
    'inews24': 'inews24.com',
    'startuptoday': 'startuptoday.co.kr',
    'einfomax': 'einfomax.com',
    'korea herald': 'koreaherald.com',
    'korea times': 'koreatimes.co.kr',
    'korea joongang': 'koreajoongangdaily.joins.com',
    'hankyoreh': 'english.hani.co.kr',
    // 해외
    'reuters': 'reuters.com',
    'bloomberg': 'bloomberg.com',
    'cnbc': 'cnbc.com',
    'wsj': 'wsj.com',
    'wall street journal': 'wsj.com',
    'financial times': 'ft.com',
    'ft': 'ft.com',
    'associated press': 'apnews.com',
    'ap news': 'apnews.com',
    'seeking alpha': 'seekingalpha.com',
    'business insider': 'businessinsider.com',
    'the economist': 'economist.com',
    'nikkei': 'nikkei.com',
    'marketwatch': 'marketwatch.com',
    'forbes': 'forbes.com',
    'bbc': 'bbc.com',
    'nytimes': 'nytimes.com',
    'huffpost': 'huffpost.com',
  };

  // ▶ 해외 언론사 키 집합
  static const _overseasKeys = {
    'reuters',
    'bloomberg',
    'cnbc',
    'wsj',
    'wall street journal',
    'financial times',
    'ft',
    'associated press',
    'ap news',
    'nikkei',
    'marketwatch',
    'seeking alpha',
    'barrons',
    'forbes',
    'business insider',
    'the economist',
    'bbc',
    'nytimes',
    'huffpost',
    'investopedia',
    'coinreaders',
  };

  static bool _isOverseas(String rawSource) {
    final key = rawSource.toLowerCase().trim();
    return _overseasKeys.any((k) => key.contains(k));
  }

  static String _localizeSource(String raw) {
    final key = raw.toLowerCase().trim();
    for (final entry in _sourceMap.entries) {
      if (key.contains(entry.key)) return entry.value;
    }
    return raw;
  }

  static String? _getFaviconUrl(String rawSource, {String? url}) {
    // 1순위: 기사 URL에서 도메인 직접 추출 (가장 정확)
    if (url != null && url.isNotEmpty) {
      try {
        final host = Uri.parse(url).host.replaceFirst('www.', '');
        if (host.isNotEmpty) {
          return 'https://www.google.com/s2/favicons?domain=$host&sz=64';
        }
      } catch (_) {}
    }
    // 2순위: 소스명 → 도메인 맵 조회
    final key = rawSource.toLowerCase().trim();
    for (final entry in _faviconDomainMap.entries) {
      if (key.contains(entry.key)) {
        return 'https://www.google.com/s2/favicons?domain=${entry.value}&sz=64';
      }
    }
    // 3순위: 소스명 자체가 도메인 형태인 경우
    if (key.contains('.')) {
      return 'https://www.google.com/s2/favicons?domain=$key&sz=64';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final title = (item.title as String?) ?? '';
    final description = (item.description as String?) ?? '';
    final rawSource = item.source as String? ?? '뉴스';
    final source = _localizeSource(rawSource);
    final overseas = _isOverseas(rawSource);
    final publishedAt = item.publishedAt as DateTime?;
    final sentiment = item.sentimentScore as double? ?? 0.0;
    // url 필드 (FinanceNews: url, News: newsUrl)
    final String? url = () {
      try {
        return item.url as String?;
      } catch (_) {}
      try {
        return item.newsUrl as String?;
      } catch (_) {}
      return null;
    }();
    final faviconUrl = _getFaviconUrl(rawSource, url: url);
    // tickers/keywords 표시 (있는 경우)
    final List<String> tickers = () {
      try {
        return List<String>.from(item.tickers as List? ?? []);
      } catch (_) {
        return <String>[];
      }
    }();

    final sentimentColor = sentiment > 0.3
        ? const Color(0xFF3B82F6)
        : sentiment < -0.3
        ? AppColors.red
        : context.colors.textSecondary;
    final sentimentLabel = sentiment > 0.5
        ? '강한 호재'
        : sentiment > 0.1
        ? '호재'
        : sentiment < -0.5
        ? '강한 악재'
        : sentiment < -0.1
        ? '악재'
        : '중립';
    final sentimentIcon = sentiment > 0.1
        ? Icons.trending_up
        : sentiment < -0.1
        ? Icons.trending_down
        : Icons.remove;

    String timeAgo = '';
    if (publishedAt != null) {
      final diff = DateTime.now().difference(publishedAt);
      if (diff.inMinutes < 60) {
        timeAgo = '${diff.inMinutes}분 전';
      } else if (diff.inHours < 24) {
        timeAgo = '${diff.inHours}시간 전';
      }
    } else {
      timeAgo = '시간 정보 없음';
    }

    return GestureDetector(
      onTap: () {
        if (item is News) {
          showNewsDetailSheet(
            context,
            item as News,
            contextLabel: detailContextLabel,
          );
        } else if (url != null && url.isNotEmpty) {
          showUrlNewsSheet(context, title: title, url: url);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.colors.border),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // 좌측 감정 컬러 바
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: sentimentColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10),
                    bottomLeft: Radius.circular(10),
                  ),
                ),
              ),
              // 본문
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 상단 메타
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: AppColors.accent.withValues(alpha: 0.35),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (faviconUrl != null) ...[
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: Image.network(
                                      faviconUrl,
                                      width: 12,
                                      height: 12,
                                      errorBuilder: (_, __, ___) =>
                                          const SizedBox.shrink(),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  source,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 5),
                          // 국내/해외 딱지
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: overseas
                                  ? AppColors.orange.withValues(alpha: 0.15)
                                  : AppColors.green.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: overseas
                                    ? AppColors.orange.withValues(alpha: 0.45)
                                    : AppColors.green.withValues(alpha: 0.40),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              overseas ? '해외' : '국내',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: overseas
                                    ? AppColors.orange
                                    : AppColors.green,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          // 호재/악재 딱지
                          if (sentimentLabel != '중립')
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: sentimentColor.withValues(alpha: 0.13),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: sentimentColor.withValues(alpha: 0.45),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    sentimentIcon,
                                    size: 9,
                                    color: sentimentColor,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    sentimentLabel,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: sentimentColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(width: 6),
                          if (tickers.isNotEmpty) ...[
                            ...tickers
                                .take(2)
                                .map(
                                  (t) => Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.accent.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        t,
                                        style: const TextStyle(
                                          fontSize: 9,
                                          color: AppColors.accent,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                          ],
                          const Spacer(),
                          Text(
                            timeAgo,
                            style: TextStyle(
                              fontSize: 9,
                              color: context.colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      // 제목
                      Text(
                        title,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 11,
                            height: 1.4,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 키워드 탭 — 관심 키워드 필터링 뉴스
// ─────────────────────────────────────────────
class _FinanceKeywordTab extends ConsumerStatefulWidget {
  const _FinanceKeywordTab();

  @override
  ConsumerState<_FinanceKeywordTab> createState() => _FinanceKeywordTabState();
}

class _FinanceKeywordTabState extends ConsumerState<_FinanceKeywordTab> {
  String? _selectedKeyword;
  bool _showBullishSectorFallback = true;

  final bool _stocksLoading = false;
  final List<MarketIndex> _keywordStocks = [];

  List<String> _extractFallbackSectors(
    String summary, {
    required bool bullish,
  }) {
    final pattern = RegExp(bullish ? r'^강세섹터\s*:' : r'^약세섹터\s*:');
    for (final rawLine in summary.split('\n')) {
      final line = rawLine.trim();
      if (!pattern.hasMatch(line)) continue;

      return line
          .replaceFirst(pattern, '')
          .split(RegExp(r'[,，、]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  List<_AiFallbackPickRow> _extractFallbackPickRows(
    String summary, {
    required bool bullish,
  }) {
    final pickPattern = RegExp(
      bullish
          ? r'^강세추천\s+(코스피|코스닥|나스닥|코인)\s*:'
          : r'^약세주의\s+(코스피|코스닥|나스닥|코인)\s*:',
    );
    final itemPattern = RegExp(r'^(.+?)(?:\[([^\]]+)\])?\((.+?)\)$');
    final trailingTickerPattern = RegExp(r'^(.*?)\s+([A-Z]{2,5})$');

    return summary
        .split('\n')
        .map((line) => line.trim())
        .where((line) => pickPattern.hasMatch(line))
        .map((line) {
          final match = pickPattern.firstMatch(line);
          final market = match?.group(1) ?? '';
          final rest = line.replaceFirst(pickPattern, '').trim();
          final isNasdaq = market == '나스닥';
          final isCoin = market == '코인';
          final items = rest
              .split(RegExp(r',\s*(?=[^)]*(?:\(|$))'))
              .map((token) => token.trim())
              .where((token) => token.isNotEmpty && token != '없음')
              .map((token) {
                final itemMatch = itemPattern.firstMatch(token);
                final rawName = itemMatch != null
                    ? itemMatch.group(1)!.trim()
                    : token;
                final sectorTag = itemMatch?.group(2)?.trim() ?? '';
                final tickerMatch = trailingTickerPattern.firstMatch(rawName);
                final coinEnglishKeyword = switch (rawName) {
                  '비트코인' => 'Bitcoin',
                  '비트코인 BTC' => 'BTC',
                  _ => null,
                };
                final displayName = isNasdaq && tickerMatch != null
                    ? tickerMatch.group(1)!.trim()
                    : rawName;
                final linkKeyword = isNasdaq && tickerMatch != null
                    ? tickerMatch.group(2)!.trim()
                    : isCoin && coinEnglishKeyword != null
                    ? coinEnglishKeyword
                    : rawName;
                final reason = itemMatch?.group(3)?.trim() ?? '';
                return (
                  name: displayName,
                  linkKeyword: linkKeyword,
                  sectorTag: sectorTag,
                  reason: reason,
                );
              })
              .where((item) => item.name.trim().isNotEmpty)
              .toList();

          return (market: market, items: items);
        })
        .where((row) => row.items.isNotEmpty)
        .toList();
  }

  Widget _buildSectorLeaderFallback() {
    final aiSummaryAsync = ref.watch(aiMarketSummaryProvider);

    return aiSummaryAsync.when(
      loading: () => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '섹터별 주도주를 불러오는 중입니다',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      error: (_, __) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.analytics_outlined,
                size: 30,
                color: context.colors.textSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                '등록 키워드는 없지만 섹터별 주도주도 아직 준비되지 않았어요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '잠시 후 다시 열면 오늘의 주도주를 자동으로 보여드립니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
      data: (summary) {
        final bullishSectors = _extractFallbackSectors(summary, bullish: true);
        final bearishSectors = _extractFallbackSectors(summary, bullish: false);
        final activeRows = _extractFallbackPickRows(
          summary,
          bullish: _showBullishSectorFallback,
        );
        final activeSectors = _showBullishSectorFallback
            ? bullishSectors
            : bearishSectors;
        final accentColor = _showBullishSectorFallback
            ? AppColors.green
            : AppColors.red;
        final emptyText = _showBullishSectorFallback
            ? '오늘 강세 주도주가 아직 없습니다.'
            : '오늘 약세 점검 종목이 아직 없습니다.';

        return CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                      decoration: BoxDecoration(
                        color: context.colors.surfaceLight,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.colors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.hub_rounded,
                                  size: 18,
                                  color: accentColor,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '등록 키워드가 없어요',
                                      style: TextStyle(
                                        color: context.colors.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '대신 오늘의 섹터별 주도주를 먼저 보여드릴게요.',
                                      style: TextStyle(
                                        color: context.colors.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    if (_showBullishSectorFallback) return;
                                    setState(() {
                                      _showBullishSectorFallback = true;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _showBullishSectorFallback
                                          ? AppColors.green.withValues(
                                              alpha: 0.12,
                                            )
                                          : context.colors.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: _showBullishSectorFallback
                                            ? AppColors.green.withValues(
                                                alpha: 0.45,
                                              )
                                            : context.colors.border,
                                      ),
                                    ),
                                    child: Text(
                                      '강세추천',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: _showBullishSectorFallback
                                            ? AppColors.green
                                            : context.colors.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    if (!_showBullishSectorFallback) return;
                                    setState(() {
                                      _showBullishSectorFallback = false;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: !_showBullishSectorFallback
                                          ? AppColors.red.withValues(
                                              alpha: 0.10,
                                            )
                                          : context.colors.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: !_showBullishSectorFallback
                                            ? AppColors.red.withValues(
                                                alpha: 0.40,
                                              )
                                            : context.colors.border,
                                      ),
                                    ),
                                    child: Text(
                                      '약세주의',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: !_showBullishSectorFallback
                                            ? AppColors.red
                                            : context.colors.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (activeSectors.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        _showBullishSectorFallback ? '주목 강세 섹터' : '점검 약세 섹터',
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: activeSectors
                            .map(
                              (sector) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: accentColor.withValues(alpha: 0.22),
                                  ),
                                ),
                                child: Text(
                                  sector,
                                  style: TextStyle(
                                    color: accentColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (activeRows.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    emptyText,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                sliver: SliverList.builder(
                  itemCount: activeRows.length,
                  itemBuilder: (context, index) {
                    final row = activeRows[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        decoration: BoxDecoration(
                          color: context.colors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.colors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    row.market,
                                    style: TextStyle(
                                      color: accentColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${row.items.length}개 종목',
                                  style: TextStyle(
                                    color: context.colors.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: row.items.map((item) {
                                  return GestureDetector(
                                    onTap: () {
                                      final url =
                                          'https://m.stock.naver.com/searchItem?keyword=${Uri.encodeComponent(item.linkKeyword)}';
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => NewsWebViewScreen(
                                            url: url,
                                            title: '${item.name} 주가',
                                          ),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      width: 158,
                                      height: 126,
                                      margin: const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.fromLTRB(
                                        10,
                                        10,
                                        10,
                                        10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: context.colors.surfaceLight,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: accentColor.withValues(
                                            alpha: 0.16,
                                          ),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.name,
                                            style: TextStyle(
                                              color: context.colors.textPrimary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 8),
                                          if (item.sectorTag.isNotEmpty)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 7,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: accentColor.withValues(
                                                  alpha: 0.08,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                item.sectorTag,
                                                style: TextStyle(
                                                  color: accentColor,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            )
                                          else
                                            const SizedBox(height: 24),
                                          const SizedBox(height: 8),
                                          Expanded(
                                            child: Text(
                                              item.reason.isNotEmpty
                                                  ? item.reason
                                                  : '섹터 흐름을 반영한 주도주입니다.',
                                              style: TextStyle(
                                                color: context
                                                    .colors
                                                    .textSecondary,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500,
                                                height: 1.4,
                                              ),
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final keywords = ref.watch(favoriteKeywordsControllerProvider);
    final newsAsync = ref.watch(stockMarketNewsProvider);

    if (keywords.isEmpty) {
      return _buildSectorLeaderFallback();
    }

    if (_selectedKeyword != null && !keywords.contains(_selectedKeyword)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedKeyword = null);
      });
    }

    return CustomScrollView(
      physics: const ClampingScrollPhysics(),
      slivers: [
        // 키워드 칩 가로 스크롤
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Text(
                      _selectedKeyword ?? '맞춤 키워드',
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: context.colors.surfaceLight,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _selectedKeyword == null
                            ? '${keywords.length}개'
                            : '필터 적용',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  '노이즈를 줄이고 보고 싶은 키워드만 골라보세요',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    _buildKeywordChip(
                      label: '전체',
                      isSelected: _selectedKeyword == null,
                      onTap: () => setState(() => _selectedKeyword = null),
                    ),
                    ...keywords.map((kw) {
                      final isSelected = _selectedKeyword == kw;
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _buildKeywordChip(
                          label: kw,
                          isSelected: isSelected,
                          onTap: () => setState(() => _selectedKeyword = kw),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Divider(height: 1, color: context.colors.border),
        ),
        // ─── 관련 종목 주가 섹션 ───
        if (_stocksLoading || _keywordStocks.isNotEmpty) ...[
          SliverToBoxAdapter(child: _buildStockSection(context)),
          SliverToBoxAdapter(
            child: Divider(height: 1, color: context.colors.border),
          ),
        ],
        // 뉴스 리스트
        ...newsAsync.when(
          data: (allNews) {
            final filtered = allNews.where((n) {
              final text = '${n.title} ${n.description}'.toLowerCase();
              if (_selectedKeyword != null) {
                return text.contains(_selectedKeyword!.toLowerCase());
              }
              return keywords.any((kw) => text.contains(kw.toLowerCase()));
            }).toList()..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

            if (filtered.isEmpty) {
              return [
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: context.colors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: context.colors.border),
                          ),
                          child: Icon(
                            Icons.article_outlined,
                            size: 28,
                            color: context.colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _selectedKeyword != null
                              ? "'$_selectedKeyword' 관련 뉴스가 없어요"
                              : '키워드 관련 뉴스가 없어요',
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '잠시 후 뉴스가 업데이트될 수 있어요',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ];
            }

            return [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _FinanceNewsCard(
                        item: filtered[i],
                        detailContextLabel: _selectedKeyword != null
                            ? '키워드 탭 · $_selectedKeyword'
                            : '키워드 탭',
                      ),
                    ),
                    childCount: filtered.length,
                  ),
                ),
              ),
            ];
          },
          loading: () => [
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                  strokeWidth: 2,
                ),
              ),
            ),
          ],
          error: (e, _) => [
            SliverFillRemaining(
              child: Center(
                child: Text(
                  '오류: $e',
                  style: const TextStyle(color: AppColors.red, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStockSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '관련 종목 주가',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          if (_stocksLoading)
            SizedBox(
              height: 104,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                itemCount: 3,
                itemBuilder: (_, __) => _StockBannerSkeleton(),
              ),
            )
          else
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                itemCount: _keywordStocks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) =>
                    _StockBannerTile(stock: _keywordStocks[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildKeywordChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accent.withValues(alpha: 0.08)
              : context.colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.accent.withValues(alpha: 0.30)
                : context.colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.accent
                    : context.colors.textSecondary.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? context.colors.textPrimary
                    : context.colors.textSecondary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 주가 배너 종목 타일
// ─────────────────────────────────────────────
class _StockBannerTile extends StatelessWidget {
  final MarketIndex stock;
  const _StockBannerTile({required this.stock});

  @override
  Widget build(BuildContext context) {
    final isUp = stock.isUp;
    final changeColor = isUp ? AppColors.green : AppColors.red;

    return Container(
      constraints: const BoxConstraints(minWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: changeColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: changeColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 종목명
          Text(
            stock.name,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          // 현재가
          Text(
            stock.formattedPrice,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 3),
          // 변화율
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                color: changeColor,
                size: 14,
              ),
              Text(
                stock.formattedChange,
                style: TextStyle(
                  color: changeColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 주가 배너 스켈레톤
// ─────────────────────────────────────────────
class _StockBannerSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.border),
      ),
      child: Shimmer.fromColors(
        baseColor: context.colors.surfaceLight,
        highlightColor: context.colors.border,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 70,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Container(
                width: 55,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Container(
                width: 40,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 속보 탭 깜빡이는 LIVE 인디케이터
// ─────────────────────────────────────────────
class _FinanceLiveIndicator extends StatefulWidget {
  final bool isSelected;
  const _FinanceLiveIndicator({required this.isSelected});

  @override
  State<_FinanceLiveIndicator> createState() => _FinanceLiveIndicatorState();
}

class _FinanceLiveIndicatorState extends State<_FinanceLiveIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: AppColors.green.withValues(alpha: 0.9),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 통계 독립 화면 (하단 네비에서 사용)
// ─────────────────────────────────────────────
class FinanceStatsScreen extends ConsumerWidget {
  const FinanceStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positiveAsync = ref.watch(positiveFinanceNewsProvider);
    final negativeAsync = ref.watch(negativeFinanceNewsProvider);
    final trendingKeywordsAsync = ref.watch(topTrendingKeywordsProvider);
    final trendingNewsAsync = ref.watch(newsListProvider);

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
                        '시장 통계',
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '강세/약세 뉴스 분석',
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
          Expanded(
            child: positiveAsync.when(
              data: (positiveNews) => negativeAsync.when(
                data: (negativeNews) {
                  final total = positiveNews.length + negativeNews.length;
                  final bullRatio = total == 0
                      ? 0.5
                      : positiveNews.length / total;
                  final bullPct = total == 0 ? 50 : (bullRatio * 100).round();
                  final bearPct = 100 - bullPct;

                  final indicesStats = [
                    _IndexStat(
                      'KOSPI',
                      positiveNews
                          .where(
                            (n) =>
                                (n.title).contains('코스피') ||
                                (n.description).contains('코스피'),
                          )
                          .length,
                      negativeNews
                          .where(
                            (n) =>
                                (n.title).contains('코스피') ||
                                (n.description).contains('코스피'),
                          )
                          .length,
                      0.47,
                    ),
                    _IndexStat(
                      'KOSDAQ',
                      positiveNews
                          .where((n) => (n.title).contains('코스닥'))
                          .length,
                      negativeNews
                          .where((n) => (n.title).contains('코스닥'))
                          .length,
                      -0.32,
                    ),
                    _IndexStat(
                      'NASDAQ',
                      positiveNews
                          .where(
                            (n) =>
                                (n.title).contains('나스닥') ||
                                (n.title).contains('Nasdaq'),
                          )
                          .length,
                      negativeNews
                          .where(
                            (n) =>
                                (n.title).contains('나스닥') ||
                                (n.title).contains('Nasdaq'),
                          )
                          .length,
                      1.12,
                    ),
                    _IndexStat(
                      'S&P500',
                      positiveNews
                          .where(
                            (n) =>
                                (n.title).contains('S&P') ||
                                (n.title).contains('SP500'),
                          )
                          .length,
                      negativeNews
                          .where(
                            (n) =>
                                (n.title).contains('S&P') ||
                                (n.title).contains('SP500'),
                          )
                          .length,
                      0.78,
                    ),
                  ];

                  return RefreshIndicator(
                    color: AppColors.accent,
                    backgroundColor: context.colors.surface,
                    onRefresh: () async {
                      ref.invalidate(allFinanceNewsProvider);
                      await Future.wait([
                        ref.read(positiveFinanceNewsProvider.future),
                        ref.read(negativeFinanceNewsProvider.future),
                      ]);
                    },
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: [
                        _StatsGaugeCard(
                          bullCount: positiveNews.length,
                          bearCount: negativeNews.length,
                          bullPct: bullPct,
                          bearPct: bearPct,
                          total: total,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _StatValueCard(
                                label: '강세 뉴스',
                                value: '${positiveNews.length}건',
                                pct: bullPct,
                                color: AppColors.green,
                                icon: Icons.trending_up,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _StatValueCard(
                                label: '약세 뉴스',
                                value: '${negativeNews.length}건',
                                pct: bearPct,
                                color: AppColors.red,
                                icon: Icons.trending_down,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const _StatsSectionHeader(label: '인덱스별 강세/약세'),
                        const SizedBox(height: 10),
                        ...indicesStats.map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _IndexStatRow(stat: s),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const _StatsSectionHeader(label: '트렌딩 키워드'),
                        const SizedBox(height: 10),
                        trendingKeywordsAsync.when(
                          data: (keywords) {
                            if (keywords.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  '트렌딩 키워드가 없습니다',
                                  style: TextStyle(
                                    color: context.colors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              );
                            }

                            final newsList =
                                trendingNewsAsync.valueOrNull ?? const <News>[];

                            return SizedBox(
                              height: 112,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: keywords.take(8).length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final keyword = keywords[index];
                                  return _StatsTrendingKeywordCard(
                                    keyword: keyword,
                                    onTap: () {
                                      final relatedNews =
                                          _filterTrendingKeywordNews(
                                            keyword: keyword,
                                            newsList: newsList,
                                          );
                                      _showStatsTrendingKeywordNewsSheet(
                                        context,
                                        keyword: keyword,
                                        newsList: relatedNews,
                                      );
                                    },
                                  );
                                },
                              ),
                            );
                          },
                          loading: () => SizedBox(
                            height: 112,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: 4,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (_, __) => Container(
                                width: 132,
                                decoration: BoxDecoration(
                                  color: context.colors.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: context.colors.border,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          error: (e, _) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              '트렌딩 키워드를 불러오지 못했어요',
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const _StatsSectionHeader(
                          label: '강세 뉴스 TOP 3',
                          color: AppColors.green,
                        ),
                        const SizedBox(height: 10),
                        if (positiveNews.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              '강세 뉴스가 없습니다',
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          )
                        else
                          ...positiveNews
                              .take(3)
                              .map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: _FinanceNewsCard(item: item),
                                ),
                              ),
                        const SizedBox(height: 16),
                        const _StatsSectionHeader(
                          label: '약세 뉴스 TOP 3',
                          color: AppColors.red,
                        ),
                        const SizedBox(height: 10),
                        if (negativeNews.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              '약세 뉴스가 없습니다',
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          )
                        else
                          ...negativeNews
                              .take(3)
                              .map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: _FinanceNewsCard(item: item),
                                ),
                              ),
                      ],
                    ),
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.accent,
                    strokeWidth: 2,
                  ),
                ),
                error: (e, _) => Center(
                  child: Text(
                    '오류: $e',
                    style: TextStyle(color: context.colors.textSecondary),
                  ),
                ),
              ),
              loading: () => const Center(
                child: CircularProgressIndicator(
                  color: AppColors.accent,
                  strokeWidth: 2,
                ),
              ),
              error: (e, _) => Center(
                child: Text(
                  '오류: $e',
                  style: TextStyle(color: context.colors.textSecondary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<News> _filterTrendingKeywordNews({
  required Keyword keyword,
  required List<News> newsList,
}) {
  final normalizedKeyword = keyword.name.toLowerCase().trim();

  final filtered = newsList.where((news) {
    final keywordMatches = news.keywords.any(
      (item) => item.toLowerCase().contains(normalizedKeyword),
    );
    final corpus = '${news.title} ${news.description} ${news.category}'
        .toLowerCase();
    return keywordMatches || corpus.contains(normalizedKeyword);
  }).toList()..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

  return filtered;
}

void _showStatsTrendingKeywordNewsSheet(
  BuildContext context, {
  required Keyword keyword,
  required List<News> newsList,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _StatsTrendingKeywordNewsSheet(keyword: keyword, newsList: newsList),
  );
}

class _StatsTrendingKeywordCard extends StatelessWidget {
  final Keyword keyword;
  final VoidCallback onTap;

  const _StatsTrendingKeywordCard({required this.keyword, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final changeColor = keyword.changeRate >= 0
        ? AppColors.green
        : AppColors.red;
    final changeText =
        '${keyword.changeRate > 0 ? '+' : ''}${keyword.changeRate.toStringAsFixed(1)}%';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 140,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: changeColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  keyword.changeRate >= 0
                      ? Icons.north_east_rounded
                      : Icons.south_east_rounded,
                  size: 14,
                  color: changeColor,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                keyword.name,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '${keyword.mentionCount}회 언급',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Text(
                    changeText,
                    style: TextStyle(
                      color: changeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '뉴스 보기',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsTrendingKeywordNewsSheet extends StatelessWidget {
  final Keyword keyword;
  final List<News> newsList;

  const _StatsTrendingKeywordNewsSheet({
    required this.keyword,
    required this.newsList,
  });

  @override
  Widget build(BuildContext context) {
    final changeColor = keyword.changeRate >= 0
        ? AppColors.green
        : AppColors.red;
    final changeText =
        '${keyword.changeRate > 0 ? '+' : ''}${keyword.changeRate.toStringAsFixed(1)}%';

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            keyword.name,
                            style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: changeColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            changeText,
                            style: TextStyle(
                              color: changeColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StatsKeywordMetaChip(
                          label: '${keyword.mentionCount}회 언급',
                        ),
                        if (keyword.category.trim().isNotEmpty)
                          _StatsKeywordMetaChip(label: keyword.category),
                        _StatsKeywordMetaChip(
                          label: '관련 뉴스 ${newsList.length}건',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '이 키워드가 포함된 기사만 모아봤어요',
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.colors.border),
              Expanded(
                child: newsList.isEmpty
                    ? Center(
                        child: Text(
                          '직접 연결된 뉴스가 아직 없습니다',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: EdgeInsets.fromLTRB(
                          16,
                          12,
                          16,
                          MediaQuery.of(context).padding.bottom + 16,
                        ),
                        itemCount: newsList.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final news = newsList[index];
                          final sentimentColor = news.sentimentScore > 0.1
                              ? AppColors.green
                              : news.sentimentScore < -0.1
                              ? AppColors.red
                              : context.colors.textSecondary;

                          return GestureDetector(
                            onTap: () => showNewsDetailSheet(
                              context,
                              news,
                              contextLabel: '통계 · 트렌딩 키워드 · ${keyword.name}',
                            ),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                12,
                                12,
                                12,
                              ),
                              decoration: BoxDecoration(
                                color: context.colors.surfaceLight,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: context.colors.border,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          news.source,
                                          style: TextStyle(
                                            color: context.colors.textSecondary,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: sentimentColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _timeAgo(news.publishedAt),
                                        style: TextStyle(
                                          color: context.colors.textSecondary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    news.title,
                                    style: TextStyle(
                                      color: context.colors.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      height: 1.4,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (news.description.isNotEmpty) ...[
                                    const SizedBox(height: 5),
                                    Text(
                                      news.description,
                                      style: TextStyle(
                                        color: context.colors.textSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        height: 1.35,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    return '${diff.inDays}일 전';
  }
}

class _StatsKeywordMetaChip extends StatelessWidget {
  final String label;

  const _StatsKeywordMetaChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: context.colors.surfaceLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: context.colors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// AI 관련 뉴스 바텀시트
// ─────────────────────────────────────────────
class _AiRelatedNewsSheet extends StatelessWidget {
  final List<FinanceNews> newsList;
  final String? titleSuffix;

  const _AiRelatedNewsSheet({required this.newsList, this.titleSuffix});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 드래그 핸들
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 헤더
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 16,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      titleSuffix == null || titleSuffix!.isEmpty
                          ? 'AI 요약 관련 뉴스'
                          : 'AI 요약 관련 뉴스 · $titleSuffix',
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${newsList.length}건',
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.colors.border),
              // 뉴스 리스트
              Expanded(
                child: newsList.isEmpty
                    ? Center(
                        child: Text(
                          '관련 뉴스가 없습니다',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: EdgeInsets.fromLTRB(
                          0,
                          8,
                          0,
                          MediaQuery.of(context).padding.bottom + 16,
                        ),
                        itemCount: newsList.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: context.colors.border),
                        itemBuilder: (context, i) {
                          final news = newsList[i];
                          final urlStr = news.url ?? '';
                          final host = urlStr.isNotEmpty
                              ? () {
                                  try {
                                    return Uri.parse(
                                      urlStr,
                                    ).host.replaceFirst('www.', '');
                                  } catch (_) {
                                    return '';
                                  }
                                }()
                              : '';
                          final sentiment = news.sentimentScore;
                          final sentimentColor = sentiment > 0.1
                              ? AppColors.green
                              : sentiment < -0.1
                              ? AppColors.red
                              : context.colors.textSecondary;

                          return InkWell(
                            onTap: urlStr.isNotEmpty
                                ? () => showUrlNewsSheet(
                                    context,
                                    title: news.title,
                                    url: urlStr,
                                  )
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 소스 + 시간 + 감정
                                  Row(
                                    children: [
                                      if (host.isNotEmpty) ...[
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                          child: Image.network(
                                            'https://www.google.com/s2/favicons?domain=$host&sz=64',
                                            width: 12,
                                            height: 12,
                                            errorBuilder: (_, __, ___) =>
                                                const SizedBox.shrink(),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      Text(
                                        news.source,
                                        style: TextStyle(
                                          color: context.colors.textSecondary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _timeAgo(news.publishedAt),
                                        style: TextStyle(
                                          color: context.colors.textSecondary,
                                          fontSize: 10,
                                        ),
                                      ),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: sentimentColor.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          _sentimentLabel(sentiment),
                                          style: TextStyle(
                                            color: sentimentColor,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    news.title,
                                    style: TextStyle(
                                      color: context.colors.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      height: 1.4,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (news.description.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      news.description,
                                      style: TextStyle(
                                        color: context.colors.textSecondary,
                                        fontSize: 11,
                                        height: 1.4,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    return '${diff.inDays}일 전';
  }

  static String _sentimentLabel(double score) {
    if (score > 0.5) return '강한 호재';
    if (score > 0.1) return '호재';
    if (score < -0.5) return '강한 악재';
    if (score < -0.1) return '악재';
    return '중립';
  }
}
