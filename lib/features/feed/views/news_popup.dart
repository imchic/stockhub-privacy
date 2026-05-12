import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../config/index.dart';
import '../../../data/models/index.dart';
import '../../../providers/index.dart';
import '../../../utils/ad_service.dart';

/// URL만 있는 뉴스 알림을 간략 팝업으로 표시합니다. (WebView 대체)
void showUrlNewsSheet(
  BuildContext context, {
  required String title,
  String? keyword,
  String? url,
}) {
  final parentContext = context;

  showModalBottomSheet(
    context: context,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) {
      final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;
      return SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.of(context).surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + bottomSafe),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.of(context).border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (keyword != null && keyword.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '# $keyword',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Text(
                title,
                style: TextStyle(
                  color: AppColors.of(context).textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              if (url != null && url.isNotEmpty) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final tempNews = News(
                        id: url,
                        title: title,
                        description: '',
                        content: '',
                        source: '',
                        imageUrl: '',
                        newsUrl: url,
                        publishedAt: DateTime.now(),
                        createdAt: DateTime.now(),
                        keywords: [],
                        regions: [],
                        sentimentScore: 0.0,
                        importanceLevel: 3,
                        category: '',
                      );
                      Navigator.pop(context);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!parentContext.mounted) return;
                        unawaited(
                          openNewsWithAdV2(parentContext, news: tempNews),
                        );
                      });
                    },
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('전체 보기'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      SharePlus.instance.share(
                        ShareParams(text: '$title\n\n$url'),
                      );
                    },
                    icon: const Icon(Icons.share_outlined, size: 16),
                    label: const Text('원문 공유'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                      foregroundColor: AppColors.accent,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// API에서 받아온 뉴스 데이터를 바텀 시트 팝업으로 표시합니다.
void showNewsDetailSheet(
  BuildContext context,
  News news, {
  bool showBookmark = true,
  String? contextLabel,
}) {
  final parentContext = context;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NewsDetailSheet(
      parentContext: parentContext,
      news: news,
      showBookmark: showBookmark,
      contextLabel: contextLabel,
    ),
  );
}

class _NewsDetailSheet extends ConsumerStatefulWidget {
  final BuildContext parentContext;
  final News news;
  final bool showBookmark;
  final String? contextLabel;

  const _NewsDetailSheet({
    required this.parentContext,
    required this.news,
    this.showBookmark = true,
    this.contextLabel,
  });

  @override
  ConsumerState<_NewsDetailSheet> createState() => _NewsDetailSheetState();
}

class _NewsDetailSheetState extends ConsumerState<_NewsDetailSheet> {
  bool _toastVisible = false;
  bool _toastWasSaved = false;

  void _showToast(bool saved) {
    setState(() {
      _toastVisible = true;
      _toastWasSaved = saved;
    });
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _toastVisible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final news = widget.news;
    final contextLabel = widget.contextLabel?.trim();
    final isBookmarked = ref.watch(
      bookmarkedNewsProvider.selectAsync(
        (list) => list.any((n) => n.id == news.id),
      ),
    );

    final sentimentColor = _sentimentColor(context, news.sentimentScore);
    final sentimentLabel = _sentimentLabel(news.sentimentScore);

    final maxHeight = MediaQuery.sizeOf(context).height * 0.90;
    final bottomPadding = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, bottomPadding + 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (contextLabel != null && contextLabel.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppColors.accent.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.filter_alt_rounded,
                                size: 12,
                                color: AppColors.accent,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                contextLabel,
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      // 소스 + 시간 + 감정 뱃지
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: context.colors.surfaceLight,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (news.newsUrl.isNotEmpty) ...[
                                  Builder(
                                    builder: (context) {
                                      final host = () {
                                        try {
                                          return Uri.parse(
                                            news.newsUrl,
                                          ).host.replaceFirst('www.', '');
                                        } catch (_) {
                                          return '';
                                        }
                                      }();
                                      if (host.isEmpty) {
                                        return const SizedBox.shrink();
                                      }
                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
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
                                      );
                                    },
                                  ),
                                ],
                                Text(
                                  news.source,
                                  style: TextStyle(
                                    color: context.colors.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            news.getTimeAgo(),
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: sentimentColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              sentimentLabel,
                              style: TextStyle(
                                color: sentimentColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // 제목
                      Text(
                        news.title,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 요약 설명
                      if (news.description.isNotEmpty) ...[
                        Text(
                          news.description,
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 13,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      Divider(color: context.colors.border, height: 1),
                      const SizedBox(height: 20),

                      // ── 증시 영향 분석 ──────────────────────────
                      Text(
                        '증시 영향 분석',
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),

                      _buildScoreRow(
                        context,
                        label: '증시 관련성',
                        score: news.stockRelevanceScore,
                        color: AppColors.accent,
                      ),
                      const SizedBox(height: 10),

                      _buildScoreRow(
                        context,
                        label: '감정 점수',
                        score: (news.sentimentScore + 1) / 2,
                        color: sentimentColor,
                        leadingLabel: '악재',
                        trailingLabel: '호재',
                      ),
                      const SizedBox(height: 20),

                      // ── 관련 키워드 ──────────────────────────────
                      if (news.keywords.isNotEmpty) ...[
                        Text(
                          '관련 키워드',
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: news.keywords
                              .map((kw) => _buildTag(context, kw))
                              .toList(),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── 관련 지역 ────────────────────────────────
                      if (news.regions.isNotEmpty) ...[
                        Text(
                          '관련 지역',
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: news.regions
                              .map(
                                (r) => _buildTag(
                                  context,
                                  AppConstants.regionToKorean(r),
                                  color: AppColors.orange,
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 28),
                      ],

                      // ── 액션 버튼 ────────────────────────────────
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 인라인 토스트
                          AnimatedOpacity(
                            opacity: _toastVisible ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 250),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: _toastWasSaved
                                    ? AppColors.accent
                                    : context.colors.textSecondary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _toastWasSaved
                                        ? Icons.bookmark_added
                                        : Icons.bookmark_remove,
                                    color: Colors.white,
                                    size: 15,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _toastWasSaved ? '저장되었습니다' : '저장이 해제되었습니다',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              // 북마크 버튼
                              if (widget.showBookmark)
                                FutureBuilder<bool>(
                                  future: isBookmarked,
                                  builder: (context, snapshot) {
                                    final bookmarked =
                                        snapshot.data ?? news.isBookmarked;
                                    return GestureDetector(
                                      onTap: () async {
                                        final wasBookmarked = bookmarked;
                                        final repository = await ref.read(
                                          newsRepositoryProvider.future,
                                        );
                                        await repository.toggleBookmark(news);
                                        ref.invalidate(bookmarkedNewsProvider);
                                        _showToast(!wasBookmarked);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 14,
                                        ),
                                        decoration: BoxDecoration(
                                          color: bookmarked
                                              ? AppColors.accent
                                              : context.colors.surfaceLight,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: bookmarked
                                                ? AppColors.accent
                                                : context.colors.border,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              bookmarked
                                                  ? Icons.bookmark
                                                  : Icons.bookmark_border,
                                              color: bookmarked
                                                  ? Colors.white
                                                  : context
                                                        .colors
                                                        .textSecondary,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              bookmarked ? '저장됨' : '저장',
                                              style: TextStyle(
                                                color: bookmarked
                                                    ? Colors.white
                                                    : context
                                                          .colors
                                                          .textSecondary,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              if (widget.showBookmark)
                                const SizedBox(width: 10),

                              // 전체 보기 버튼
                              if (news.newsUrl.isNotEmpty)
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            if (!widget.parentContext.mounted) {
                                              return;
                                            }
                                            unawaited(
                                              openNewsWithAdV2(
                                                widget.parentContext,
                                                news: news,
                                              ),
                                            );
                                          });
                                    },
                                    icon: const Icon(
                                      Icons.open_in_new,
                                      size: 16,
                                    ),
                                    label: const Text('전체 보기'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.accent,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),

                              // 공유 버튼
                              if (news.newsUrl.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    final shareText =
                                        '${news.title}\n\n${news.newsUrl}';
                                    SharePlus.instance.share(
                                      ShareParams(text: shareText),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: context.colors.surfaceLight,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: context.colors.border,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.share_outlined,
                                      color: context.colors.textSecondary,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
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

  Widget _buildScoreRow(
    BuildContext context, {
    required String label,
    required double score,
    required Color color,
    String leadingLabel = '낮음',
    String trailingLabel = '높음',
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${(score * 100).round()}%',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: score.clamp(0.0, 1.0),
            backgroundColor: context.colors.border,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              leadingLabel,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 9,
              ),
            ),
            Text(
              trailingLabel,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTag(BuildContext context, String label, {Color? color}) {
    final tagColor = color ?? AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tagColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tagColor.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tagColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _sentimentColor(BuildContext context, double score) {
    if (score > 0.1) return AppColors.green;
    if (score < -0.1) return AppColors.red;
    return context.colors.textSecondary;
  }

  String _sentimentLabel(double score) {
    if (score > 0.5) return '강한 호재';
    if (score > 0.1) return '호재';
    if (score < -0.5) return '강한 악재';
    if (score < -0.1) return '악재';
    return '중립';
  }
}
