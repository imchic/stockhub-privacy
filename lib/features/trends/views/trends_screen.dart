import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../../config/index.dart';
import '../../../data/models/index.dart';
import '../../../providers/index.dart';
import '../../../widgets/news_feed_banner_ad.dart';

class TrendsScreen extends ConsumerWidget {
  const TrendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positiveAsync = ref.watch(positiveFinanceNewsProvider);
    final negativeAsync = ref.watch(negativeFinanceNewsProvider);
    final newsAsync = ref.watch(newsListProvider);
    final topKeywordsAsync = ref.watch(topTrendingKeywordsProvider);
    final surgingAsync = ref.watch(surgingKeywordsProvider);

    ({String title, String detail}) buildTrendLoadingStatus() {
      if (newsAsync.isLoading) {
        return (
          title: '뉴스 집계 중',
          detail: '오늘 수집된 기사를 모아 트렌드 분석의 재료를 준비하고 있습니다.',
        );
      }

      if (positiveAsync.isLoading || negativeAsync.isLoading) {
        return (
          title: '감성 분석 중',
          detail: '강세 뉴스와 약세 뉴스를 분류해 시장 온도를 계산하고 있습니다.',
        );
      }

      if (topKeywordsAsync.isLoading) {
        return (
          title: '키워드 계산 중',
          detail: '반복 언급과 중요도를 바탕으로 상위 트렌딩 키워드를 정리하고 있습니다.',
        );
      }

      if (surgingAsync.isLoading) {
        return (
          title: '급상승 키워드 분석 중',
          detail: '짧은 시간 안에 빠르게 늘어난 키워드를 추적하고 있습니다.',
        );
      }

      return (title: '트렌드 분석 계산 중', detail: '실시간 시장 강세/약세와 키워드 흐름을 정리하고 있습니다.');
    }

    final isLoadingTrends =
        positiveAsync.isLoading ||
        negativeAsync.isLoading ||
        newsAsync.isLoading ||
        topKeywordsAsync.isLoading ||
        surgingAsync.isLoading;
    final loadingStatus = buildTrendLoadingStatus();

    return Scaffold(
      backgroundColor: context.colors.bg,
      body: RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: context.colors.surface,
        onRefresh: () async {
          ref.invalidate(allFinanceNewsProvider);
          ref.invalidate(newsListProvider);
          ref.invalidate(topTrendingKeywordsProvider);
          ref.invalidate(surgingKeywordsProvider);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '트렌드 분석',
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '실시간 시장 강세/약세 · 트렌딩 키워드',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: isLoadingTrends
                    ? Padding(
                        key: const ValueKey('trends-loading-banner'),
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: _TrendsLoadingBanner(
                          title: loadingStatus.title,
                          detail: loadingStatus.detail,
                        ),
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('trends-loading-banner-empty'),
                      ),
              ),
            ),
            // ── 시장 강세/약세 게이지 ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: positiveAsync.when(
                  data: (positiveNews) => negativeAsync.when(
                    data: (negativeNews) {
                      final total = positiveNews.length + negativeNews.length;
                      final bullPct = total == 0
                          ? 50
                          : (positiveNews.length / total * 100).round();
                      final bearPct = 100 - bullPct;

                      return Column(
                        children: [
                          _TrendsGaugeCard(
                            bullCount: positiveNews.length,
                            bearCount: negativeNews.length,
                            bullPct: bullPct,
                            bearPct: bearPct,
                            total: total,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _TrendsStatCard(
                                  label: '강세 뉴스',
                                  value: '${positiveNews.length}건',
                                  pct: bullPct,
                                  color: AppColors.green,
                                  icon: Icons.trending_up,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _TrendsStatCard(
                                  label: '약세 뉴스',
                                  value: '${negativeNews.length}건',
                                  pct: bearPct,
                                  color: AppColors.red,
                                  icon: Icons.trending_down,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                    loading: () => const _TrendsShimmer(height: 160),
                    error: (_, __) =>
                        const _TrendsErrorCard('시장 통계를 불러올 수 없습니다.'),
                  ),
                  loading: () => const _TrendsShimmer(height: 160),
                  error: (_, __) =>
                      const _TrendsErrorCard('시장 통계를 불러올 수 없습니다.'),
                ),
              ),
            ),

            // ── 인덱스별 강세/약세 ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: positiveAsync.when(
                  data: (positiveNews) => negativeAsync.when(
                    data: (negativeNews) {
                      final indicesStats = [
                        _IndexStat(
                          'KOSPI',
                          positiveNews
                              .where(
                                (n) =>
                                    n.title.contains('코스피') ||
                                    n.description.contains('코스피'),
                              )
                              .length,
                          negativeNews
                              .where(
                                (n) =>
                                    n.title.contains('코스피') ||
                                    n.description.contains('코스피'),
                              )
                              .length,
                          0.47,
                        ),
                        _IndexStat(
                          'KOSDAQ',
                          positiveNews
                              .where((n) => n.title.contains('코스닥'))
                              .length,
                          negativeNews
                              .where((n) => n.title.contains('코스닥'))
                              .length,
                          -0.32,
                        ),
                        _IndexStat(
                          'NASDAQ',
                          positiveNews
                              .where(
                                (n) =>
                                    n.title.contains('나스닥') ||
                                    n.title.contains('Nasdaq'),
                              )
                              .length,
                          negativeNews
                              .where(
                                (n) =>
                                    n.title.contains('나스닥') ||
                                    n.title.contains('Nasdaq'),
                              )
                              .length,
                          1.12,
                        ),
                        _IndexStat(
                          'S&P500',
                          positiveNews
                              .where(
                                (n) =>
                                    n.title.contains('S&P') ||
                                    n.title.contains('SP500'),
                              )
                              .length,
                          negativeNews
                              .where(
                                (n) =>
                                    n.title.contains('S&P') ||
                                    n.title.contains('SP500'),
                              )
                              .length,
                          0.78,
                        ),
                      ];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _TrendsSectionHeader(
                            label: '인덱스별 강세/약세',
                            showLive: true,
                          ),
                          const SizedBox(height: 10),
                          ...indicesStats.map(
                            (s) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _IndexStatRow(stat: s),
                            ),
                          ),
                        ],
                      );
                    },
                    loading: () => const _TrendsShimmer(height: 160),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  loading: () => const _TrendsShimmer(height: 160),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ),
            ),

            // ── 뉴스 감성 + 카테고리 ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: newsAsync.when(
                  data: (newsList) => newsList.isEmpty
                      ? const SizedBox.shrink()
                      : _NewsSentimentSection(newsList: newsList),
                  loading: () => const _TrendsShimmer(height: 200),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ),
            ),

            // ── 광고 배너 ──
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: NewsFeedBannerAd(),
              ),
            ),

            // ── 급상승 키워드 ──
            SliverToBoxAdapter(
              child: surgingAsync.when(
                data: (keywords) {
                  if (keywords.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: _SurgingKeywordsSection(keywords: keywords),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),

            // ── 트렌딩 키워드 헤더 ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '트렌딩 키워드',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: context.colors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'TOP 10',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: AppColors.accent,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── 트렌딩 키워드 리스트 ──
            topKeywordsAsync.when(
              data: (keywords) {
                if (keywords.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Text(
                          '트렌드 데이터가 없습니다.',
                          style: TextStyle(color: context.colors.textSecondary),
                        ),
                      ),
                    ),
                  );
                }
                final maxMentions = keywords
                    .map((k) => k.mentionCount)
                    .reduce((a, b) => a > b ? a : b);
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _TrendingKeywordItem(
                        rank: index + 1,
                        keyword: keywords[index],
                        maxMentions: maxMentions,
                      ),
                      childCount: keywords.length,
                    ),
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 32),
                  child: _TrendingKeywordListShimmer(),
                ),
              ),
              error: (e, _) => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: _TrendsErrorCard('키워드 데이터를 불러올 수 없습니다.'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 공통 헬퍼
// ─────────────────────────────────────────────

class _TrendsShimmer extends StatelessWidget {
  final double height;
  const _TrendsShimmer({required this.height});

  @override
  Widget build(BuildContext context) {
    final baseColor = context.colors.surfaceLight;
    final highlightColor = context.colors.surface;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class _TrendsLoadingBanner extends StatelessWidget {
  final String title;
  final String detail;

  const _TrendsLoadingBanner({required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: const LinearProgressIndicator(
              minHeight: 5,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendingKeywordListShimmer extends StatelessWidget {
  const _TrendingKeywordListShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        6,
        (index) => Padding(
          padding: EdgeInsets.only(bottom: index == 5 ? 0 : 10),
          child: const _TrendingKeywordListShimmerRow(),
        ),
      ),
    );
  }
}

class _TrendingKeywordListShimmerRow extends StatelessWidget {
  const _TrendingKeywordListShimmerRow();

  @override
  Widget build(BuildContext context) {
    final baseColor = context.colors.surfaceLight;
    final highlightColor = context.colors.surface;

    Widget block({required double width, required double height}) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(8),
        ),
      );
    }

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  block(width: 120, height: 14),
                  const SizedBox(height: 8),
                  block(width: double.infinity, height: 10),
                ],
              ),
            ),
            const SizedBox(width: 12),
            block(width: 44, height: 18),
          ],
        ),
      ),
    );
  }
}

class _TrendsErrorCard extends StatelessWidget {
  final String message;
  const _TrendsErrorCard(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.red, size: 16),
          const SizedBox(width: 8),
          Text(
            message,
            style: const TextStyle(color: AppColors.red, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _TrendsSectionHeader extends StatelessWidget {
  final String label;
  final Color color;
  final bool showLive;

  const _TrendsSectionHeader({
    required this.label,
    this.color = AppColors.accent,
    this.showLive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: 0.0)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
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
        if (showLive) ...[const SizedBox(width: 7), _LiveDot(color: color)],
      ],
    );
  }
}

class _LiveDot extends StatefulWidget {
  final Color color;
  const _LiveDot({required this.color});
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.1 + 0.08 * _anim.value),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.6 + 0.4 * _anim.value),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'LIVE',
              style: TextStyle(
                color: widget.color,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 강세/약세 게이지 카드 (반원형 애니메이션)
// ─────────────────────────────────────────────

class _TrendsGaugeCard extends StatefulWidget {
  final int bullCount;
  final int bearCount;
  final int bullPct;
  final int bearPct;
  final int total;

  const _TrendsGaugeCard({
    required this.bullCount,
    required this.bearCount,
    required this.bullPct,
    required this.bearPct,
    required this.total,
  });

  @override
  State<_TrendsGaugeCard> createState() => _TrendsGaugeCardState();
}

class _TrendsGaugeCardState extends State<_TrendsGaugeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_TrendsGaugeCard old) {
    super.didUpdateWidget(old);
    if (old.bullPct != widget.bullPct) {
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isBull = widget.bullPct >= 50;
    final dominantColor = isBull ? AppColors.green : AppColors.red;
    final dominantLabel = isBull ? '강세 우세' : '약세 우세';
    final dominantPct = isBull ? widget.bullPct : widget.bearPct;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border),
        boxShadow: [
          BoxShadow(
            color: dominantColor.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // 헤더
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [dominantColor, dominantColor.withValues(alpha: 0)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '시장 강세/약세',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: dominantColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '총 ${widget.total}건',
                  style: TextStyle(
                    color: dominantColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // 반원형 게이지 + 중앙 수치
          AnimatedBuilder(
            animation: _anim,
            builder: (context, _) {
              final bullRatio = (widget.bullPct / 100.0) * _anim.value;
              return SizedBox(
                height: 110,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    CustomPaint(
                      size: const Size(200, 110),
                      painter: _SemiCircleGaugePainter(
                        bullRatio: bullRatio,
                        bullColor: AppColors.green,
                        bearColor: AppColors.red,
                        trackColor: context.colors.border,
                        strokeWidth: 18,
                      ),
                    ),
                    Positioned(
                      bottom: 12,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$dominantPct%',
                            style: TextStyle(
                              color: dominantColor,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1,
                            ),
                          ),
                          Text(
                            dominantLabel,
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          // 하단 범례
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _GaugeLegend(
                label: '매수(강세)',
                count: widget.bullCount,
                pct: widget.bullPct,
                color: AppColors.green,
                align: CrossAxisAlignment.start,
              ),
              _GaugeLegend(
                label: '매도(약세)',
                count: widget.bearCount,
                pct: widget.bearPct,
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

// 반원형 게이지 CustomPainter
class _SemiCircleGaugePainter extends CustomPainter {
  final double bullRatio;
  final Color bullColor;
  final Color bearColor;
  final Color trackColor;
  final double strokeWidth;

  _SemiCircleGaugePainter({
    required this.bullRatio,
    required this.bullColor,
    required this.bearColor,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height;
    final radius = size.width / 2 - strokeWidth / 2;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, trackPaint);

    // 강세(왼쪽 → 중앙)
    final bullSweep = math.pi * bullRatio;
    if (bullSweep > 0) {
      final bullPaint = Paint()
        ..shader = SweepGradient(
          colors: [bullColor.withValues(alpha: 0.6), bullColor],
          startAngle: math.pi,
          endAngle: math.pi + bullSweep,
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, math.pi, bullSweep, false, bullPaint);
    }

    // 약세(오른쪽 → 중앙)
    final bearRatio = 1.0 - bullRatio;
    final bearSweep = math.pi * bearRatio;
    if (bearSweep > 0) {
      final bearPaint = Paint()
        ..shader = SweepGradient(
          colors: [bearColor, bearColor.withValues(alpha: 0.6)],
          startAngle: math.pi + bullSweep,
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, math.pi + bullSweep, bearSweep, false, bearPaint);
    }
  }

  @override
  bool shouldRepaint(_SemiCircleGaugePainter old) =>
      old.bullRatio != bullRatio ||
      old.bullColor != bullColor ||
      old.trackColor != trackColor;
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
          mainAxisSize: MainAxisSize.min,
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
// 수치 요약 카드
// ─────────────────────────────────────────────

class _TrendsStatCard extends StatelessWidget {
  final String label;
  final String value;
  final int pct;
  final Color color;
  final IconData icon;

  const _TrendsStatCard({
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
// 인덱스별 강세/약세
// ─────────────────────────────────────────────

class _IndexStat {
  final String name;
  final int bull;
  final int bear;
  final double marketChange;
  const _IndexStat(this.name, this.bull, this.bear, this.marketChange);
}

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
// 뉴스 감성 + 카테고리 섹션
// ─────────────────────────────────────────────

class _NewsSentimentSection extends StatelessWidget {
  final List<News> newsList;

  const _NewsSentimentSection({required this.newsList});

  @override
  Widget build(BuildContext context) {
    final total = newsList.length;
    final positive = newsList.where((n) => n.sentimentScore > 0.1).length;
    final negative = newsList.where((n) => n.sentimentScore < -0.1).length;
    final neutral = total - positive - negative;

    final categoryMap = <String, int>{};
    for (final n in newsList) {
      if (n.category.isNotEmpty) {
        categoryMap[n.category] = (categoryMap[n.category] ?? 0) + 1;
      }
    }
    final topCategories = categoryMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _TrendsSectionHeader(label: '오늘 뉴스 감성 분석'),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '총 $total건',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.colors.border),
          ),
          child: Column(
            children: [
              // 감성 분포 바 (애니메이션)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, progress, _) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 10,
                      child: Row(
                        children: [
                          if (positive > 0)
                            Flexible(
                              flex: (positive * progress).round().clamp(
                                1,
                                total,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.green.withValues(alpha: 0.7),
                                      AppColors.green,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (neutral > 0)
                            Flexible(
                              flex: (neutral * progress).round().clamp(
                                1,
                                total,
                              ),
                              child: Container(color: context.colors.border),
                            ),
                          if (negative > 0)
                            Flexible(
                              flex: (negative * progress).round().clamp(
                                1,
                                total,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.red,
                                      AppColors.red.withValues(alpha: 0.7),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _SentimentBadge(
                    label: '호재',
                    count: positive,
                    pct: total == 0 ? 0 : (positive / total * 100).round(),
                    color: AppColors.green,
                  ),
                  const SizedBox(width: 8),
                  _SentimentBadge(
                    label: '중립',
                    count: neutral,
                    pct: total == 0 ? 0 : (neutral / total * 100).round(),
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  _SentimentBadge(
                    label: '악재',
                    count: negative,
                    pct: total == 0 ? 0 : (negative / total * 100).round(),
                    color: AppColors.red,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (topCategories.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '주요 카테고리',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                ...topCategories.take(4).map((entry) {
                  final ratio = entry.value / total;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.key,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.colors.textPrimary,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${entry.value}건',
                              style: TextStyle(
                                fontSize: 10,
                                color: context.colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: ratio),
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) => ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: value,
                              minHeight: 4,
                              backgroundColor: context.colors.border,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.accent,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SentimentBadge extends StatelessWidget {
  final String label;
  final int count;
  final int pct;
  final Color color;

  const _SentimentBadge({
    required this.label,
    required this.count,
    required this.pct,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$count건',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              '$pct%',
              style: TextStyle(
                fontSize: 10,
                color: color.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 급상승 키워드 섹션
// ─────────────────────────────────────────────

class _SurgingKeywordsSection extends StatelessWidget {
  final List<Keyword> keywords;

  const _SurgingKeywordsSection({required this.keywords});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Text('\u{1F525}', style: TextStyle(fontSize: 16)),
            SizedBox(width: 6),
            _TrendsSectionHeader(
              label: '급상승 키워드',
              color: AppColors.orange,
              showLive: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: keywords.take(8).map((k) {
              final isUp = k.changeRate > 0;
              final chipColor = isUp ? AppColors.red : AppColors.green;
              final changeIcon = isUp
                  ? Icons.arrow_upward
                  : Icons.arrow_downward;
              return Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      chipColor.withValues(alpha: 0.14),
                      chipColor.withValues(alpha: 0.04),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: chipColor.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                  border: Border.all(color: chipColor.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      k.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: chipColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(changeIcon, size: 10, color: chipColor),
                          const SizedBox(width: 2),
                          Text(
                            '${k.changeRate.abs().toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: chipColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// 트렌딩 키워드 아이템
// ─────────────────────────────────────────────

class _TrendingKeywordItem extends StatelessWidget {
  final int rank;
  final Keyword keyword;
  final int maxMentions;

  static const _medals = ['\u{1F947}', '\u{1F948}', '\u{1F949}'];
  static const _rankColors = [
    Color(0xFFFFD700),
    Color(0xFFC0C0C0),
    Color(0xFFCD7F32),
  ];

  const _TrendingKeywordItem({
    required this.rank,
    required this.keyword,
    required this.maxMentions,
  });

  Color _getRiskColor(int level) {
    if (level >= 4) return AppColors.red;
    if (level >= 3) return AppColors.orange;
    return AppColors.green;
  }

  String _getRiskText(int level) {
    if (level >= 4) return '고위험';
    if (level >= 3) return '주의';
    return '안전';
  }

  @override
  Widget build(BuildContext context) {
    final riskColor = _getRiskColor(keyword.riskLevel);
    final isTop3 = rank <= 3;
    final rankColor = isTop3 ? _rankColors[rank - 1] : context.colors.border;
    final ratio = maxMentions > 0 ? keyword.mentionCount / maxMentions : 0.0;
    final isUp = keyword.changeRate > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: isTop3
            ? LinearGradient(
                colors: [
                  rankColor.withValues(alpha: 0.10),
                  rankColor.withValues(alpha: 0.02),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isTop3 ? null : context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isTop3
              ? rankColor.withValues(alpha: 0.45)
              : context.colors.border,
          width: isTop3 ? 1.2 : 1,
        ),
        boxShadow: isTop3
            ? [
                BoxShadow(
                  color: rankColor.withValues(alpha: 0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 36,
                  child: isTop3
                      ? Text(
                          _medals[rank - 1],
                          style: const TextStyle(fontSize: 22),
                          textAlign: TextAlign.center,
                        )
                      : Container(
                          height: 32,
                          decoration: BoxDecoration(
                            color: context.colors.surfaceLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '$rank',
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        keyword.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: context.colors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (keyword.category.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                keyword.category,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            '${keyword.mentionCount}회 언급',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: (isUp ? AppColors.red : AppColors.green)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: (isUp ? AppColors.red : AppColors.green)
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isUp ? Icons.arrow_upward : Icons.arrow_downward,
                            size: 10,
                            color: isUp ? AppColors.red : AppColors.green,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${keyword.changeRate.abs().toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: isUp ? AppColors.red : AppColors.green,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: riskColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _getRiskText(keyword.riskLevel),
                        style: TextStyle(
                          color: riskColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: ratio.toDouble()),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  if (isTop3) {
                    return Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: context.colors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: FractionallySizedBox(
                        widthFactor: value,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                rankColor.withValues(alpha: 0.7),
                                rankColor,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    );
                  }
                  return LinearProgressIndicator(
                    value: value,
                    minHeight: 4,
                    backgroundColor: context.colors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.accent.withValues(alpha: 0.6),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
