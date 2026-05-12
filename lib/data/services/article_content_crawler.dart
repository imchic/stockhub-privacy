import 'dart:async';
import 'dart:convert';

import 'package:charset/charset.dart' as charset;
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../../utils/text_sanitizer.dart';

/// 기사 본문 정보
class ArticleContent {
  final String title;
  final String content;
  final List<String> imageUrls;
  final String? author;
  final DateTime? publishedAt;
  final bool success;
  final String? errorMessage;

  ArticleContent({
    required this.title,
    required this.content,
    required this.imageUrls,
    this.author,
    this.publishedAt,
    this.success = true,
    this.errorMessage,
  });

  factory ArticleContent.error(String message) {
    debugPrint('❌ ArticleContent 에러: $message');
    return ArticleContent(
      title: '',
      content: message,
      imageUrls: [],
      success: false,
      errorMessage: message,
    );
  }
}

/// 뉴스 기사 본문 크롤러
/// - 주요 뉴스사 웹사이트에서 기사 본문 추출
/// - Article, article-body, news-text 등 일반적인 클래스 타겟
class ArticleContentCrawler {
  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 15);

  // 일반적인 데스크톱 User-Agent (모바일보다 허용이 더 관대함)
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  ArticleContentCrawler({http.Client? client})
    : _client = client ?? http.Client();

  /// URL에서 기사 본문 크롤링
  Future<ArticleContent> crawlArticle(String url) async {
    try {
      final uri = Uri.parse(url);
      if (!uri.isAbsolute) {
        return ArticleContent.error('[1] 유효하지 않은 URL: $url');
      }

      debugPrint('🕷️ 기사 크롤링 시작: $url');

      final response = await _client
          .get(
            uri,
            headers: {
              'User-Agent': _userAgent,
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
              'Accept-Language': 'ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7',
              'Accept-Encoding': 'gzip, deflate, br',
              'Cache-Control': 'max-age=0',
              'Connection': 'keep-alive',
              'Upgrade-Insecure-Requests': '1',
              'Sec-Fetch-Dest': 'document',
              'Sec-Fetch-Mode': 'navigate',
              'Sec-Fetch-Site': 'none',
              'Sec-Fetch-User': '?1',
              'Referer': 'https://www.naver.com/',
              'DNT': '1',
            },
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint('⚠️ HTTP 에러: ${response.statusCode}');
        return ArticleContent.error('[2] 페이지 로드 실패 (${response.statusCode})');
      }

      final body = _decodeResponse(response);
      if (body.isEmpty) {
        debugPrint('⚠️ 빈 응답본문');
        return ArticleContent.error('[3] 페이지 인코딩 불가');
      }

      debugPrint('✅ HTML 파싱 ${body.length} bytes');
      final doc = html_parser.parse(body);
      final structuredArticle = _extractStructuredArticle(doc);

      // 뉴스사별 전용 파서 시도
      final host = uri.host.replaceFirst('www.', '');

      // SBS Biz: article_hub → amp/article (JS SPA, AMP 버전 사용)
      if (host.contains('biz.sbs.co.kr')) {
        String ampUrl = url;
        final articleHubMatch = RegExp(r'article_hub/([\d]+)').firstMatch(url);
        final articleMatch = RegExp(r'/article/([\d]+)').firstMatch(url);
        if (articleHubMatch != null) {
          ampUrl =
              'https://biz.sbs.co.kr/amp/article/${articleHubMatch.group(1)}';
        } else if (articleMatch != null) {
          ampUrl = 'https://biz.sbs.co.kr/amp/article/${articleMatch.group(1)}';
        }
        if (ampUrl != url) {
          debugPrint('🔀 SBS Biz → AMP: $ampUrl');
          return crawlArticle(ampUrl);
        }
        return _mergeStructuredFallback(
          _parseSBSBiz(doc, url),
          structuredArticle,
        );
      }

      // 주요 뉴스사별 파서
      final parsed = switch (host) {
        final value when value.contains('chosun.com') => _parseChosun(doc, url),
        final value when value.contains('donga.com') => _parseDonga(doc, url),
        final value when value.contains('mk.co.kr') => _parseMaeilKyungje(
          doc,
          url,
        ),
        final value when value.contains('naeil.com') => _parseNaeil(doc, url),
        final value when value.contains('magazine.hankyung.com') =>
          _parseHankyungMagazine(doc, url),
        final value when value.contains('hankyung.com') => _parseHankyung(
          doc,
          url,
        ),
        final value when value.contains('sedaily.com') => _parseSeoulEconomic(
          doc,
          url,
        ),
        final value when value.contains('etnews.com') => _parseETNews(doc, url),
        final value when value.contains('etoday.co.kr') => _parseEtoday(
          doc,
          url,
        ),
        final value when value.contains('tokenpost.kr') => _parseTokenPost(
          doc,
          url,
        ),
        _ => _parseGeneric(doc, url),
      };
      return _mergeStructuredFallback(parsed, structuredArticle);
    } on TimeoutException {
      debugPrint('❌ 타임아웃 (15초)');
      return ArticleContent.error('[4] 요청 시간 초과 (15초)');
    } catch (e) {
      debugPrint('❌ 크롤링 실패: $e');
      return ArticleContent.error('[5] 크롤링 중 오류: $e');
    }
  }

  ArticleContent _parseChosun(html.Document doc, String url) {
    try {
      // 조선일보: article#cxwrap-newstext-article
      final contentEl =
          doc.querySelector('article#cxwrap-newstext-article') ??
          doc.querySelector('div.article-body') ??
          doc.querySelector('div#articleText');

      if (contentEl == null) {
        return _parseGeneric(doc, url);
      }

      final title = _extractTitle(doc);
      final content = _extractParagraphs(contentEl);
      final images = _extractImages(doc, contentEl);

      if (content.isEmpty) {
        return _parseGeneric(doc, url);
      }

      debugPrint('📰 [조선일보] $title');
      return ArticleContent(
        title: sanitizeHtmlText(title),
        content: sanitizeHtmlText(content),
        imageUrls: images,
      );
    } catch (e) {
      debugPrint('⚠️ 조선일보 파서 실패: $e');
      return _parseGeneric(doc, url);
    }
  }

  ArticleContent _parseDonga(html.Document doc, String url) {
    try {
      // 동아일보: article, section.article-body
      final contentEl =
          doc.querySelector('article') ??
          doc.querySelector('section.article-body') ??
          doc.querySelector('div#article-body-contents');

      if (contentEl == null) {
        return _parseGeneric(doc, url);
      }

      final title = _extractTitle(doc);
      final content = _extractParagraphs(contentEl);
      final images = _extractImages(doc, contentEl);

      if (content.isEmpty) {
        return _parseGeneric(doc, url);
      }

      debugPrint('📰 [동아일보] $title');
      return ArticleContent(
        title: sanitizeHtmlText(title),
        content: sanitizeHtmlText(content),
        imageUrls: images,
      );
    } catch (e) {
      debugPrint('⚠️ 동아일보 파서 실패: $e');
      return _parseGeneric(doc, url);
    }
  }

  ArticleContent _parseMaeilKyungje(html.Document doc, String url) {
    try {
      // 매일경제: div.news-article, div#article
      final contentEl =
          doc.querySelector('div.news-article') ??
          doc.querySelector('div#article') ??
          doc.querySelector('div.article-text');

      if (contentEl == null) {
        return _parseGeneric(doc, url);
      }

      final title = _extractTitle(doc);
      final content = _extractParagraphs(contentEl);
      final images = _extractImages(doc, contentEl);

      if (content.isEmpty) {
        return _parseGeneric(doc, url);
      }

      debugPrint('📰 [매일경제] $title');
      return ArticleContent(
        title: sanitizeHtmlText(title),
        content: sanitizeHtmlText(content),
        imageUrls: images,
      );
    } catch (e) {
      debugPrint('⚠️ 매일경제 파서 실패: $e');
      return _parseGeneric(doc, url);
    }
  }

  ArticleContent _parseNaeil(html.Document doc, String url) {
    try {
      final contentEl =
          doc.querySelector('div.article-view') ??
          doc.querySelector('div.article_txt') ??
          doc.querySelector('div.view_con');

      if (contentEl == null) {
        return _parseGeneric(doc, url);
      }

      final title = _extractTitle(doc);
      final content = _extractRichParagraphs(contentEl);
      final images = _extractImages(doc, contentEl);

      if (content.isEmpty) {
        return _parseGeneric(doc, url);
      }

      debugPrint('📰 [내일신문] $title');
      return ArticleContent(
        title: sanitizeHtmlText(title),
        content: sanitizeHtmlText(content),
        imageUrls: images,
      );
    } catch (e) {
      debugPrint('⚠️ 내일신문 파서 실패: $e');
      return _parseGeneric(doc, url);
    }
  }

  ArticleContent _parseHankyung(html.Document doc, String url) {
    try {
      // 한국경제: div.article-body, section.article-text
      final contentEl =
          doc.querySelector('div.article-body') ??
          doc.querySelector('section.article-text') ??
          doc.querySelector('div#newsContents');

      if (contentEl == null) {
        return _parseGeneric(doc, url);
      }

      final title = _extractTitle(doc);
      final content = _extractParagraphs(contentEl);
      final images = _extractImages(doc, contentEl);

      if (content.isEmpty) {
        return _parseGeneric(doc, url);
      }

      debugPrint('📰 [한국경제] $title');
      return ArticleContent(
        title: sanitizeHtmlText(title),
        content: sanitizeHtmlText(content),
        imageUrls: images,
      );
    } catch (e) {
      debugPrint('⚠️ 한국경제 파서 실패: $e');
      return _parseGeneric(doc, url);
    }
  }

  ArticleContent _parseHankyungMagazine(html.Document doc, String url) {
    try {
      final contentEl =
          doc.querySelector('div#magazineView[itemprop="articleBody"]') ??
          doc.querySelector('div#magazineView') ??
          doc.querySelector('article.view div.article-body');

      if (contentEl == null) {
        return _parseGeneric(doc, url);
      }

      final sanitizedContainer = contentEl.clone(true);
      for (final selector in const [
        'div.util-audio-area',
        'div#audioBody',
        'div.related-area',
        'div.ad-area',
        'div.ad-recommend',
        'div.ranking-news',
        'p.article-copy',
        'script',
        'style',
        'iframe',
      ]) {
        for (final el in sanitizedContainer.querySelectorAll(selector)) {
          el.remove();
        }
      }

      final title =
          doc.querySelector('article.view h1.news-tit')?.text.trim() ??
          _extractTitle(doc);
      final content = _extractMagazineParagraphs(sanitizedContainer);
      final images = _extractImages(doc, sanitizedContainer);

      if (content.isEmpty) {
        return _parseGeneric(doc, url);
      }

      debugPrint('📰 [한경BUSINESS] $title');
      return ArticleContent(
        title: sanitizeHtmlText(title),
        content: sanitizeHtmlText(content),
        imageUrls: images,
      );
    } catch (e) {
      debugPrint('⚠️ 한경BUSINESS 파서 실패: $e');
      return _parseGeneric(doc, url);
    }
  }

  ArticleContent _parseSeoulEconomic(html.Document doc, String url) {
    try {
      // 서울경제: div.article-body, div#articlebody
      final contentEl =
          doc.querySelector('div.article-body') ??
          doc.querySelector('div#articlebody') ??
          doc.querySelector('div.article-text');

      if (contentEl == null) {
        return _parseGeneric(doc, url);
      }

      final title = _extractTitle(doc);
      final content = _extractParagraphs(contentEl);
      final images = _extractImages(doc, contentEl);

      if (content.isEmpty) {
        return _parseGeneric(doc, url);
      }

      debugPrint('📰 [서울경제] $title');
      return ArticleContent(
        title: sanitizeHtmlText(title),
        content: sanitizeHtmlText(content),
        imageUrls: images,
      );
    } catch (e) {
      debugPrint('⚠️ 서울경제 파서 실패: $e');
      return _parseGeneric(doc, url);
    }
  }

  ArticleContent _parseETNews(html.Document doc, String url) {
    try {
      // 전자신문: article, div.article-text
      final contentEl =
          doc.querySelector('article') ??
          doc.querySelector('div.article-text') ??
          doc.querySelector('div#article-view');

      if (contentEl == null) {
        return _parseGeneric(doc, url);
      }

      final title = _extractTitle(doc);
      final content = _extractParagraphs(contentEl);
      final images = _extractImages(doc, contentEl);

      if (content.isEmpty) {
        return _parseGeneric(doc, url);
      }

      debugPrint('📰 [전자신문] $title');
      return ArticleContent(
        title: sanitizeHtmlText(title),
        content: sanitizeHtmlText(content),
        imageUrls: images,
      );
    } catch (e) {
      debugPrint('⚠️ 전자신문 파서 실패: $e');
      return _parseGeneric(doc, url);
    }
  }

  ArticleContent _parseEtoday(html.Document doc, String url) {
    try {
      // 이투데이: div.articleView
      final contentEl =
          doc.querySelector('div.articleView') ??
          doc.querySelector('div#article_body') ??
          doc.querySelector('div.cont_view');

      if (contentEl == null) {
        return _parseGeneric(doc, url);
      }

      final title = _extractTitle(doc);
      final content = _extractParagraphs(contentEl);
      final images = _extractImages(doc, contentEl);

      if (content.isEmpty) {
        return _parseGeneric(doc, url);
      }

      debugPrint('📰 [이투데이] $title');
      return ArticleContent(
        title: sanitizeHtmlText(title),
        content: sanitizeHtmlText(content),
        imageUrls: images,
      );
    } catch (e) {
      debugPrint('⚠️ 이투데이 파서 실패: $e');
      return _parseGeneric(doc, url);
    }
  }

  ArticleContent _parseTokenPost(html.Document doc, String url) {
    try {
      final contentEl =
          doc.querySelector('div.article_content[itemprop="articleBody"]') ??
          doc.querySelector('div.article_content') ??
          doc.querySelector('div.view_text');

      if (contentEl == null) {
        return _parseGeneric(doc, url);
      }

      final title = _extractTitle(doc);
      final content = _extractRichParagraphs(contentEl);
      final images = _extractImages(doc, contentEl);

      if (content.isEmpty) {
        return _parseGeneric(doc, url);
      }

      debugPrint('📰 [토큰포스트] $title');
      return ArticleContent(
        title: sanitizeHtmlText(title),
        content: sanitizeHtmlText(content),
        imageUrls: images,
      );
    } catch (e) {
      debugPrint('⚠️ 토큰포스트 파서 실패: $e');
      return _parseGeneric(doc, url);
    }
  }

  ArticleContent _parseSBSBiz(html.Document doc, String url) {
    try {
      // SBS Biz AMP: div.acem_text
      final contentEl =
          doc.querySelector('div.acem_text') ??
          doc.querySelector('main.article_content_w') ??
          doc.querySelector('div.article_content_end_middle');

      if (contentEl == null) {
        return _parseGeneric(doc, url);
      }

      final title = _extractTitle(doc);
      final content = _extractParagraphs(contentEl);
      final images = _extractImages(doc, contentEl);

      if (content.isEmpty) {
        return _parseGeneric(doc, url);
      }

      debugPrint('📰 [SBS Biz] $title');
      return ArticleContent(
        title: sanitizeHtmlText(title),
        content: sanitizeHtmlText(content),
        imageUrls: images,
      );
    } catch (e) {
      debugPrint('⚠️ SBS Biz 파서 실패: $e');
      return _parseGeneric(doc, url);
    }
  }

  // ── 일반 파서 ────────────────────────────────────────────

  ArticleContent _parseGeneric(html.Document doc, String url) {
    try {
      final title = _extractTitle(doc);

      // 본문 컨테이너 찾기 (우선순위 확장)
      final contentEl =
          // schema.org 마크업
          doc.querySelector('[itemprop="articleBody"]') ??
          // 한국 지역신문 CMS (Newsmate 계열)
          doc.querySelector('div#article-view-content-div') ??
          doc.querySelector('div.article-view-content') ??
          // 일반 article 태그
          doc.querySelector('article') ??
          // 공통 클래스/ID
          doc.querySelector('div.article-body') ??
          doc.querySelector('div.article-content') ??
          doc.querySelector('div.news-text') ??
          doc.querySelector('div#articleText') ??
          doc.querySelector('div#article-view') ??
          doc.querySelector('div.article_txt') ??
          doc.querySelector('div.article_body') ??
          doc.querySelector('div#article_body') ??
          doc.querySelector('div.view_con') ??
          doc.querySelector('div.view-content') ??
          doc.querySelector('div#view_content') ??
          doc.querySelector('div.article') ??
          doc.querySelector('div.content') ??
          doc.querySelector('div#content') ??
          doc.querySelector('div[class*="article"]') ??
          doc.querySelector('div[class*="content"]') ??
          doc.querySelector('div[class*="body"]') ??
          doc.querySelector('main');

      if (contentEl == null) {
        debugPrint('⚠️ 기사 컨테이너를 찾을 수 없음 → API description fallback 사용');
        return ArticleContent.error('기사 본문을 찾을 수 없습니다');
      }

      final containerInfo =
          '${contentEl.localName}'
          '${contentEl.id.isNotEmpty ? "#${contentEl.id}" : ""}'
          '${contentEl.className.isNotEmpty ? ".${contentEl.className.split(' ').first}" : ""}';
      debugPrint('🔍 컨테이너: $containerInfo');

      final content = _extractParagraphs(contentEl);
      final images = _extractImages(doc, contentEl);

      if (content.isEmpty) {
        debugPrint(
          '⚠️ 기사 본문이 비어있습니다 ($containerInfo) → API description fallback 사용',
        );
        return ArticleContent.error('기사 본문이 비어있습니다');
      }

      debugPrint('📰 [일반] $title');
      return ArticleContent(
        title: sanitizeHtmlText(title),
        content: sanitizeHtmlText(content),
        imageUrls: images,
      );
    } catch (e) {
      debugPrint('❌ 일반 파서 실패: $e');
      return ArticleContent.error('기사 파싱 실패');
    }
  }

  ArticleContent? _extractStructuredArticle(html.Document doc) {
    ArticleContent? best;

    for (final script in doc.querySelectorAll(
      'script[type="application/ld+json"]',
    )) {
      final rawJson = script.text.trim();
      if (rawJson.isEmpty) continue;

      try {
        final decoded = jsonDecode(rawJson);
        for (final node in _collectStructuredNodes(decoded)) {
          if (!_isStructuredArticleNode(node)) continue;

          final content = sanitizeHtmlText(_extractStructuredBody(node));
          if (content.length < 80) continue;

          final title = sanitizeHtmlText(
            _extractStructuredString(node['headline']) ??
                _extractStructuredString(node['name']) ??
                '기사 본문',
          );
          final images = _extractStructuredImages(node);
          final author = _extractStructuredAuthor(node['author']);
          final publishedAt = _extractStructuredDate(node['datePublished']);
          final candidate = ArticleContent(
            title: title,
            content: content,
            imageUrls: images,
            author: author,
            publishedAt: publishedAt,
          );

          if (best == null || candidate.content.length > best.content.length) {
            best = candidate;
          }
        }
      } catch (_) {
        continue;
      }
    }

    if (best != null) {
      debugPrint('🧩 JSON-LD 본문 후보 확보: ${best.content.length}자');
    }
    return best;
  }

  Iterable<Map<String, dynamic>> _collectStructuredNodes(dynamic node) sync* {
    if (node is Map<String, dynamic>) {
      yield node;
      for (final value in node.values) {
        yield* _collectStructuredNodes(value);
      }
      return;
    }

    if (node is List) {
      for (final item in node) {
        yield* _collectStructuredNodes(item);
      }
    }
  }

  bool _isStructuredArticleNode(Map<String, dynamic> node) {
    final rawType = node['@type'];
    final types = <String>{};
    if (rawType is String) {
      types.add(rawType);
    } else if (rawType is List) {
      types.addAll(rawType.whereType<String>());
    }

    const articleTypes = {
      'Article',
      'NewsArticle',
      'ReportageNewsArticle',
      'AnalysisNewsArticle',
      'BlogPosting',
    };

    return types.any(articleTypes.contains) || node['articleBody'] != null;
  }

  ArticleContent _mergeStructuredFallback(
    ArticleContent parsed,
    ArticleContent? structured,
  ) {
    if (structured == null) {
      return parsed;
    }

    final shouldUseStructured =
        !parsed.success || parsed.content.trim().length < 120;

    if (shouldUseStructured) {
      debugPrint('🧩 JSON-LD 본문 fallback 사용');
      return structured;
    }

    return ArticleContent(
      title: parsed.title.isNotEmpty ? parsed.title : structured.title,
      content: parsed.content,
      imageUrls: parsed.imageUrls.isNotEmpty
          ? parsed.imageUrls
          : structured.imageUrls,
      author: parsed.author ?? structured.author,
      publishedAt: parsed.publishedAt ?? structured.publishedAt,
      success: parsed.success,
      errorMessage: parsed.errorMessage,
    );
  }

  String _extractStructuredBody(Map<String, dynamic> node) {
    return _extractStructuredString(node['articleBody']) ??
        _extractStructuredString(node['description']) ??
        '';
  }

  String? _extractStructuredString(dynamic value) {
    if (value is String) return value;
    if (value is List) {
      final joined = value
          .map(_extractStructuredString)
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .join('\n\n');
      return joined.isEmpty ? null : joined;
    }
    if (value is Map<String, dynamic>) {
      return _extractStructuredString(
        value['@value'] ?? value['text'] ?? value['name'],
      );
    }
    return null;
  }

  List<String> _extractStructuredImages(Map<String, dynamic> node) {
    final images = <String>{};

    void addImage(dynamic value) {
      if (value is String && value.isNotEmpty) {
        images.add(value);
      } else if (value is List) {
        for (final item in value) {
          addImage(item);
        }
      } else if (value is Map<String, dynamic>) {
        addImage(value['url'] ?? value['contentUrl']);
      }
    }

    addImage(node['image']);
    return images.take(3).toList();
  }

  String? _extractStructuredAuthor(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    if (value is List) {
      final authors = value
          .map(_extractStructuredAuthor)
          .whereType<String>()
          .where((item) => item.isNotEmpty)
          .toList();
      return authors.isEmpty ? null : authors.join(', ');
    }
    if (value is Map<String, dynamic>) {
      return _extractStructuredString(value['name']);
    }
    return null;
  }

  DateTime? _extractStructuredDate(dynamic value) {
    final raw = _extractStructuredString(value);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  // ── 헬퍼 메서드 ──────────────────────────────────────

  String _extractTitle(html.Document doc) {
    // 우선순위: og:title > h1 > title 태그
    final ogTitle = doc
        .querySelector('meta[property="og:title"]')
        ?.attributes['content'];
    if (ogTitle != null && ogTitle.isNotEmpty) return ogTitle;

    final h1 = doc.querySelector('h1')?.text.trim();
    if (h1 != null && h1.isNotEmpty) return h1;

    final titleTag = doc.querySelector('title')?.text.trim();
    return sanitizeHtmlText(titleTag ?? '기사 본문');
  }

  static final _noiseTextPattern = RegExp(
    r'바로가기|구독|로그인|회원가입|공유하기|댓글|광고|Copyright|All rights reserved|무단.?전재|이메일|채널번호|편성표|공지사항',
    caseSensitive: false,
  );

  bool _isNoiseText(String text) => _noiseTextPattern.hasMatch(text);

  static final _noisePattern = RegExp(
    r'menu|gnb|lnb|nav|header|footer|sidebar|aside|related|recommend|'
    r'comment|share|social|ad[-_]|banner|ranking|hot-|popular|'
    r'tag-list|btn_|바로가기|공지사항',
    caseSensitive: false,
  );

  /// 메뉴/네비/광고 등 노이즈 부모 컨테이너 안에 있는지 확인
  bool _isInsideNoiseContainer(html.Element el) {
    html.Node? node = el.parent;
    while (node != null) {
      if (node is html.Element) {
        final tag = node.localName ?? '';
        if (tag == 'nav' ||
            tag == 'header' ||
            tag == 'footer' ||
            tag == 'aside') {
          return true;
        }
        final cls = node.attributes['class'] ?? '';
        final id = node.attributes['id'] ?? '';
        if (_noisePattern.hasMatch(cls) || _noisePattern.hasMatch(id)) {
          return true;
        }
        if (tag == 'body') break;
      }
      node = node.parent;
    }
    return false;
  }

  String _extractParagraphs(html.Element container) {
    final paragraphs = <String>[];
    final seen = <String>{};

    void addIfNew(String text) {
      final normalized = sanitizeHtmlText(text);
      if (normalized.isNotEmpty && seen.add(normalized)) {
        paragraphs.add(normalized);
      }
    }

    // 1. p 태그 우선 추출
    for (final el in container.querySelectorAll('p')) {
      if (_isInsideNoiseContainer(el)) continue;
      final classes = el.attributes['class'] ?? '';
      if (classes.contains('ad') ||
          classes.contains('comment') ||
          classes.contains('relate') ||
          classes.contains('tag') ||
          classes.contains('author') ||
          classes.contains('byline')) {
        continue;
      }

      final text = el.text.trim();
      if (text.length > 10 && !_isNoiseText(text)) addIfNew(text);
    }

    // 2. p 태그 부족하면 div 텍스트 추출 (블록 자식이 없는 div만)
    if (paragraphs.length < 3) {
      const blockTags = {
        'div',
        'p',
        'ul',
        'ol',
        'table',
        'section',
        'article',
        'header',
        'footer',
        'nav',
        'aside',
        'figure',
        'blockquote',
        'h1',
        'h2',
        'h3',
        'h4',
        'h5',
        'h6',
        'pre',
        'form',
      };
      for (final el in container.querySelectorAll('div')) {
        if (_isInsideNoiseContainer(el)) continue;
        // 블록 자식이 있는 div는 스킵 (컨테이너 역할)
        final hasBlockChild = el.children.any(
          (c) => blockTags.contains(c.localName),
        );
        if (hasBlockChild) continue;

        final text = el.text.trim();
        if (text.length > 30 && !_isNoiseText(text)) addIfNew(text);
      }
    }

    // 3. 정말 부족하면 span 태그도 추출
    if (paragraphs.length < 2) {
      for (final el in container.querySelectorAll('span')) {
        if (_isInsideNoiseContainer(el)) continue;
        final text = el.text.trim();
        if (text.length > 30 && !_isNoiseText(text)) addIfNew(text);
      }
    }

    // 4. 마지막 수단: 컨테이너 전체 텍스트를 줄 단위로 분리
    if (paragraphs.isEmpty) {
      final rawText = container.text.trim();
      final lines = rawText
          .split(RegExp(r'[\n\r]+'))
          .map((s) => s.trim())
          .where((s) => s.length > 20 && !_isNoiseText(s))
          .toList();
      for (final line in lines) {
        addIfNew(line);
      }
    }

    return sanitizeHtmlText(
      paragraphs.join('\n\n').replaceAll(RegExp(r'\n{3,}'), '\n\n'),
    );
  }

  String _extractMagazineParagraphs(html.Element container) {
    final paragraphs = <String>[];
    final seen = <String>{};

    void addIfNew(String text) {
      final normalized = sanitizeHtmlText(text);
      if (normalized.isNotEmpty &&
          !_isNoiseText(normalized) &&
          seen.add(normalized)) {
        paragraphs.add(normalized);
      }
    }

    final rawHtml = container.innerHtml
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</div\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</figure\s*>', caseSensitive: false), '\n');

    final plainText = html_parser.parseFragment(rawHtml).text ?? '';
    final lines = plainText
        .split(RegExp(r'[\n\r]+'))
        .map((s) => s.trim())
        .where((s) => s.length > 20)
        .toList();

    for (final line in lines) {
      addIfNew(line);
    }

    if (paragraphs.isEmpty) {
      return _extractParagraphs(container);
    }

    return paragraphs.join('\n\n');
  }

  String _extractRichParagraphs(html.Element container) {
    final paragraphs = <String>[];
    final seen = <String>{};

    void addIfNew(String text) {
      final normalized = sanitizeHtmlText(text);
      if (normalized.isNotEmpty &&
          !_isNoiseText(normalized) &&
          seen.add(normalized)) {
        paragraphs.add(normalized);
      }
    }

    final rawHtml = container.innerHtml
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</div\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</figure\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</h[1-6]\s*>', caseSensitive: false), '\n');

    final plainText = html_parser.parseFragment(rawHtml).text ?? '';
    final lines = plainText
        .split(RegExp(r'\n{1,}|\r+'))
        .map((item) => item.trim())
        .where((item) => item.length > 20)
        .toList();

    for (final line in lines) {
      addIfNew(line);
    }

    if (paragraphs.isEmpty) {
      return _extractParagraphs(container);
    }

    return paragraphs.join('\n\n');
  }

  List<String> _extractImages(html.Document doc, html.Element contentEl) {
    final images = <String, String>{};

    // 1. og:image 우선
    final ogImage = doc
        .querySelector('meta[property="og:image"]')
        ?.attributes['content'];
    if (ogImage != null && ogImage.isNotEmpty) {
      images['og'] = ogImage;
    }

    // 2. 기사 본문 내 첫 이미지
    for (final img in contentEl.querySelectorAll('img')) {
      final src = img.attributes['src'] ?? '';
      if (src.isNotEmpty &&
          !src.contains('transparent') &&
          !src.contains('1x1')) {
        images[src] = src;
        if (images.length >= 3) break;
      }
    }

    // 3. picture > img
    for (final pic in contentEl.querySelectorAll('picture img')) {
      final src = pic.attributes['src'] ?? '';
      if (src.isNotEmpty && !src.contains('transparent')) {
        images[src] = src;
        if (images.length >= 3) break;
      }
    }

    return images.values
        .where(
          (url) =>
              url.isNotEmpty && (url.startsWith('http') || url.startsWith('/')),
        )
        .toList();
  }

  String _decodeResponse(http.Response response) {
    try {
      final charsetName = _detectCharset(response);
      final bytes = response.bodyBytes;

      if (charsetName == 'euc-kr') {
        debugPrint('🔤 EUC-KR 디코딩 적용');
        return charset.eucKr.decode(bytes);
      }

      if (charsetName == 'latin1') {
        return latin1.decode(bytes, allowInvalid: true);
      }

      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      debugPrint('⚠️ 인코딩 실패: $e');
      return '';
    }
  }

  String _detectCharset(http.Response response) {
    final headerCharset = _extractCharsetName(
      response.headers['content-type'] ?? '',
    );
    if (headerCharset != null) {
      return headerCharset;
    }

    final preview = latin1.decode(
      response.bodyBytes.take(4096).toList(),
      allowInvalid: true,
    );
    final metaCharset = _extractCharsetName(preview);
    return metaCharset ?? 'utf-8';
  }

  String? _extractCharsetName(String value) {
    final lower = value.toLowerCase();
    final match = RegExp(
      "charset\\s*=\\s*['\\\"]?([a-z0-9_-]+)",
    ).firstMatch(lower);
    final charsetName = match?.group(1);
    if (charsetName == null) return null;

    if (charsetName.contains('euc-kr') ||
        charsetName.contains('ks_c_5601') ||
        charsetName.contains('cp949') ||
        charsetName.contains('windows-949')) {
      return 'euc-kr';
    }
    if (charsetName.contains('8859-1') || charsetName.contains('latin1')) {
      return 'latin1';
    }
    return charsetName;
  }
}
