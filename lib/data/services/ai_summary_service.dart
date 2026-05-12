import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/constants.dart';
import '../models/finance_news.dart';
import '../models/market_index.dart';

/// Google Gemini를 사용한 AI 한줄 시장 요약 서비스
class AiSummaryService {
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent';
  static const List<Map<String, String>> _bullishCoinFallbackPool = [
    {'name': 'BTC', 'sector': '디지털금', 'reason': '기관 수급과 ETF 선호 수혜'},
    {'name': 'ETH', 'sector': '플랫폼', 'reason': '스테이킹·현물 수급 기대 반영'},
    {'name': 'SOL', 'sector': '고베타 메인넷', 'reason': '위험자산 선호 확대에 민감'},
    {'name': 'XRP', 'sector': '결제', 'reason': '제도권 결제 테마 유입 기대'},
    {'name': 'BNB', 'sector': '거래소 생태계', 'reason': '거래대금 회복 수혜 기대'},
    {'name': 'DOGE', 'sector': '밈코인', 'reason': '투기 심리 확대 시 탄력 큼'},
    {'name': 'AVAX', 'sector': '레이어1', 'reason': '온체인 회복 기대 반영'},
    {'name': 'LINK', 'sector': '오라클', 'reason': '토큰화·온체인 인프라 수혜'},
    {'name': 'SUI', 'sector': '신규 메인넷', 'reason': '고베타 순환매 유입 기대'},
    {'name': 'ADA', 'sector': '레이어1', 'reason': '메이저 알트 순환매 후보'},
  ];
  static const List<Map<String, String>> _bearishCoinFallbackPool = [
    {'name': 'DOGE', 'sector': '밈코인', 'reason': '위험회피 시 변동성 압력 큼'},
    {'name': 'SUI', 'sector': '신규 메인넷', 'reason': '고베타 자산 차익실현 우려'},
    {'name': 'AVAX', 'sector': '레이어1', 'reason': '유동성 축소에 민감한 편'},
    {'name': 'SOL', 'sector': '고베타 메인넷', 'reason': '변동성 확대 시 조정폭 확대'},
    {'name': 'ADA', 'sector': '레이어1', 'reason': '알트 약세 구간 상대 부진 우려'},
    {'name': 'XRP', 'sector': '결제', 'reason': '규제 불확실성 재부각 가능성'},
    {'name': 'ETH', 'sector': '플랫폼', 'reason': '리스크오프 시 알트 전반 압력'},
    {'name': 'LINK', 'sector': '오라클', 'reason': '온체인 기대 약화 시 부담'},
    {'name': 'BNB', 'sector': '거래소 생태계', 'reason': '거래대금 둔화 시 약세 가능'},
    {'name': 'BTC', 'sector': '디지털금', 'reason': '달러 강세 구간 상단 부담'},
  ];

  /// 시장 지수 데이터 + 뉴스 헤드라인 → 한 줄 한국어 요약 반환
  Future<String> generateMarketSummary({
    required List<MarketIndex> indices,
    List<FinanceNews> newsItems = const [],
    List<String> headlines = const [],
    List<String> kospiStocks = const [], // KRX 코스피 실제 상장 종목
    List<String> kosdaqStocks = const [], // KRX 코스닥 실제 상장 종목
  }) async {
    const key = AppConstants.geminiApiKey;
    if (key.isEmpty) throw Exception('Gemini API 키가 설정되지 않았습니다');

    final normalizedNewsItems = newsItems
        .where((item) => item.title.trim().isNotEmpty)
        .take(24)
        .toList();
    final normalizedHeadlines = headlines
        .map((headline) => headline.trim())
        .where((headline) => headline.isNotEmpty)
        .take(20)
        .toList();

    final newsText = normalizedNewsItems.isNotEmpty
        ? _buildStructuredNewsText(normalizedNewsItems)
        : normalizedHeadlines.isNotEmpty
        ? normalizedHeadlines
              .asMap()
              .entries
              .map((entry) => '${entry.key + 1}. ${entry.value}')
              .join('\n')
        : '뉴스 없음';
    final indexText = indices.isNotEmpty
        ? '시장 지수: ${indices.map((i) => '${i.name} ${i.formattedChange}').join(', ')}'
        : '';

    final kospiCandidates = _buildKrkCandidates(
      newsItems: normalizedNewsItems,
      stocks: kospiStocks,
      market: 'kospi',
    );
    final kosdaqCandidates = _buildKrkCandidates(
      newsItems: normalizedNewsItems,
      stocks: kosdaqStocks,
      market: 'kosdaq',
    );
    final directMentionedKospi = _findDirectMentionedStocks(
      newsItems: normalizedNewsItems,
      stocks: kospiStocks,
    );
    final directMentionedKosdaq = _findDirectMentionedStocks(
      newsItems: normalizedNewsItems,
      stocks: kosdaqStocks,
    );
    final kospiListText = kospiCandidates.isNotEmpty
        ? '코스피 추천 후보군(가능하면 아래 후보군 안에서만 추천):\n${kospiCandidates.join(', ')}\n'
        : '코스피 후보군이 비어 있음 → 코스피 항목은 직접 뉴스에 언급된 종목이 없으면 "없음" 으로 출력할 것\n';
    final kosdaqListText = kosdaqCandidates.isNotEmpty
        ? '코스닥 추천 후보군(가능하면 아래 후보군 안에서만 추천):\n${kosdaqCandidates.join(', ')}\n'
        : '코스닥 후보군이 비어 있음 → 코스닥 항목은 직접 뉴스에 언급된 종목이 없으면 "없음" 으로 출력할 것\n';
    const nasdaqGuideText =
        '나스닥 추천은 뉴스 제목에 직접 드러난 기업·산업·이벤트를 우선 근거로 삼되, 특정 종목명이 없어도 제목에 드러난 산업/거시 이벤트로 수혜 가능성이 높은 대표 종목까지는 연결할 수 있다. 다만 연결 근거가 약하면 "나스닥: 없음" 으로 출력할 것\n';
    const coinGuideText =
        '코인 추천은 비트코인, 이더리움 같은 직접 언급이 있으면 최우선 반영하고, 직접 종목 언급이 없더라도 위험자산 선호, 달러 약세, 금리 기대, ETF/제도권 수급, 채굴/전력/블록체인 인프라 같은 제목 키워드가 있으면 대표 코인으로 연결할 수 있다. 가능하면 강세추천/약세주의 각각 6개를 채우고, 최소 4개 이상은 제시할 것. 근거가 매우 약할 때만 "코인: 없음" 으로 출력할 것\n';

    final prompt =
        '역할:\n'
        '당신은 한국 및 글로벌 금융시장을 분석하는 탑티어 헤지펀드 애널리스트다.\n'
        '뉴스 기반으로 단기 트레이딩 관점에서 실제 수익 기회를 찾는 것이 목표다.\n\n'
        '분석 기준:\n'
        '- 아래에 제공된 뉴스 제목 자체를 가장 중요한 1차 근거로 사용할 것\n'
        '- 제목에 직접 드러난 이벤트, 기업명, 산업 키워드에만 의존해 판단할 것\n'
        '- 뉴스 → 수혜/피해 산업 도출\n'
        '- 산업 → 실제 수혜 가능 종목 연결\n'
        '- 반드시 "왜 오를지" 근거 중심\n\n'
        '--- 출력 형식 (반드시 그대로 따를 것) ---\n'
        '하이라이트: 핵심 포인트 한 줄\n'
        '하이라이트: 핵심 포인트 한 줄\n'
        '하이라이트: 핵심 포인트 한 줄\n'
        '분석제목: 첫 번째 분석 소제목\n'
        '분석내용: 소제목에 대한 상세 분석 1~2줄\n'
        '분석제목: 두 번째 분석 소제목\n'
        '분석내용: 소제목에 대한 상세 분석 1~2줄\n'
        '강세섹터: 섹터A, 섹터B, 섹터C\n'
        '약세섹터: 섹터D, 섹터E\n'
        '강세추천 코스피: 종목명[섹터명](핵심 이유), ... 최대 6개\n'
        '강세추천 코스닥: 종목명[섹터명](핵심 이유), ... 최대 6개\n'
        '강세추천 나스닥: 종목명 티커[섹터명](핵심 이유), ... 최대 6개\n'
        '강세추천 코인: 티커[섹터명](핵심 이유), ... 최대 6개\n'
        '약세주의 코스피: 종목명[섹터명](핵심 이유), ... 최대 6개\n'
        '약세주의 코스닥: 종목명[섹터명](핵심 이유), ... 최대 6개\n'
        '약세주의 나스닥: 종목명 티커[섹터명](핵심 이유), ... 최대 6개\n'
        '약세주의 코인: 티커[섹터명](핵심 이유), ... 최대 6개\n'
        '---\n\n'
        '규칙:\n'
        '[하이라이트]\n'
        '- 정확히 3줄\n'
        '- 각 줄: 이 뉴스에서 가장 중요한 핵심 사실 1개\n'
        '- 핵심 키워드는 **굵게** 표시\n'
        '- 20~40자 이내\n\n'
        '[분석]\n'
        '- 분석제목+분석내용 세트 정확히 2개\n'
        '- 소제목: 10자 이내, 관점/테마 중심\n'
        '- 내용: 뉴스 → 시장 영향 흐름 서술\n\n'
        '[섹터]\n'
        '- 뉴스에서 직접 연결되는 섹터만 선택\n'
        '- 강세/약세 각각 2~4개\n\n'
        '[추천 종목]\n'
        '- 강세추천과 약세주의를 반드시 분리해 출력할 것\n'
        '- 각 시장별 가능하면 6개 내외, 최소 4개\n'
        '- 반드시 종목명[섹터명](핵심 이유) 형식을 사용할 것\n'
        '- 섹터명은 강세/약세 섹터에 적은 표현과 최대한 일치시킬 것\n'
        '- 이유는 15~30자\n'
        '- 뉴스 제목 → 산업 → 종목 흐름이 명확해야 함\n'
        '- 기사 제목에 없는 막연한 테마 확장 금지. 단, 나스닥/코인은 제목에 드러난 섹터/이벤트에서 대표 종목으로 한 단계 연결하는 것은 허용\n\n'
        '[약세주의 종목 규칙]\n'
        '- 약세주의는 하락 압력이 큰 업종/기업 또는 회피가 필요한 종목을 적을 것\n'
        '- 약세섹터가 1개 이상 잡혔다면 약세주의 종목도 최소 1개 이상 반드시 제시할 것\n'
        '- 거시 악재 뉴스(관세, 규제, 금리상승, 달러강세, 유가급등, 경기둔화, 지정학 리스크)가 있으면 관련 대표 종목이나 대표 코인을 약세주의로 연결할 것\n'
        '- 직접 악재 종목 언급이 없더라도 악재를 가장 민감하게 받는 고밸류/고변동 대표 종목으로 연결 가능\n'
        '- 강세추천 종목을 약세주의에 중복 기재하지 말 것\n'
        '- 전체 뉴스에 약세 근거가 거의 없을 때만 "없음" 을 사용할 수 있음\n\n'
        '[나스닥 제한]\n'
        '- 나스닥은 티커만 쓰지 말고 반드시 종목명과 티커를 함께 표기\n'
        '- 뉴스 제목에 직접 언급된 종목이 있으면 우선 추천\n'
        '- 직접 종목 언급이 없더라도 제목에 드러난 산업/이벤트와 매우 강하게 연결되는 대표 종목은 추천 가능\n'
        '- 예: AI capex/반도체 → NVIDIA, AMD / 클라우드·기업 AI → Microsoft, Amazon / 전기차·자율주행 → Tesla\n'
        '- 약세주의는 고금리, 관세, 공급망 불안, 밸류에이션 부담, 소비 둔화에 취약한 대표 성장주/반도체/소비재 종목으로 연결 가능\n'
        '- 가능하면 서로 다른 2개 이상 세부 테마로 분산 추천\n'
        '- 특정 종목 1개로만 반복 추천하는 쏠림 금지\n\n'
        '[코인 제한]\n'
        '- 코인은 티커 또는 대표 코인명으로 표기 가능\n'
        '- 직접 코인 언급이 없더라도 제목에 위험자산 선호, 유동성 확대, 금리 인하 기대, ETF/제도권 수급, 블록체인 인프라가 드러나면 BTC, ETH, SOL, XRP, BNB, DOGE, AVAX, LINK 등 대표 코인으로 연결 가능\n'
        '- 반대로 규제 강화, 해킹, 위험회피, 달러 강세, 유동성 축소가 강하면 약세주의 코인으로 연결 가능\n'
        '- 강세추천 코인은 가능하면 6개를 채우고, 최소 4개 미만으로 줄이지 말 것\n'
        '- 약세주의 코인도 가능하면 6개를 채우고, 최소 4개 미만으로 줄이지 말 것\n'
        '- 같은 자산군만 반복하지 말고 메이저, 플랫폼, 결제, 고베타 알트를 섞어 분산 추천할 것\n'
        '- 약세주의 코인은 변동성 확대 구간에서 BTC, ETH, SOL 등 시가총액 상위 코인 중 뉴스 맥락과 가장 맞는 자산으로 연결 가능\n'
        '- 기사와 연결이 약하면 "없음" 으로 출력\n\n'
        '[KRX 제한]\n'
        '- 코스피/코스닥 종목은 후보군 우선으로 선택할 것\n'
        '- 후보군 밖 종목은 뉴스에 직접 종목명이 드러난 경우에만 예외적으로 허용\n'
        '- 코스피 리스트에 있는 종목은 절대 코스닥 항목에 포함하지 말 것\n'
        '- 코스닥 리스트에 있는 종목은 절대 코스피 항목에 포함하지 말 것\n'
        '- 뉴스와 연결 근거가 약하면 KRX 종목은 "없음" 으로 출력할 것\n\n'
        '[금지사항]\n'
        '- 뉴스와 무관한 추천 금지\n'
        '- 형식 변경 금지\n\n'
        '뉴스:\n$newsText\n'
        '${indexText.isNotEmpty ? '$indexText\n' : ''}'
        '$kospiListText'
        '$kosdaqListText'
        '$nasdaqGuideText'
        '$coinGuideText'
        '출력:';

    final resp = await http.post(
      Uri.parse('$_endpoint?key=$key'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'generationConfig': {
          'maxOutputTokens': 1100, // 추천 종목을 시장별 6개 내외까지 허용
          'temperature': 0.4, // 더 일관된 응답을 위해 온도 감소
          'topP': 0.8, // 출력 다양성 제한
        },
      }),
    );

    if (resp.statusCode != 200) {
      throw Exception('Gemini API 오류 ${resp.statusCode}: ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final rawText =
        data['candidates'][0]['content']['parts'][0]['text'] as String;

    // AI 응답 포맷 정리 + KRX 목록 기반 시장 교차 검증
    return _formatAndValidate(
      rawText.trim(),
      kospiStocks,
      kosdaqStocks,
      kospiCandidates: kospiCandidates,
      kosdaqCandidates: kosdaqCandidates,
      directMentionedKospi: directMentionedKospi,
      directMentionedKosdaq: directMentionedKosdaq,
    );
  }

  String _buildStructuredNewsText(List<FinanceNews> items) {
    return items
        .asMap()
        .entries
        .map((entry) {
          final index = entry.key + 1;
          final item = entry.value;
          final sentimentLabel = item.sentimentScore >= 0.25
              ? '긍정'
              : item.sentimentScore <= -0.25
              ? '부정'
              : '중립';
          final keywords = item.keywords.take(4).join(', ');
          final desc = item.description.trim().isEmpty
              ? '-'
              : item.description.trim();
          return '$index. 제목: ${item.title}\n'
              '   요약: $desc\n'
              '   감성: $sentimentLabel / 중요도: ${item.importanceLevel} / 카테고리: ${item.category}\n'
              '   키워드: ${keywords.isEmpty ? '-' : keywords}';
        })
        .join('\n');
  }

  List<String> _buildKrkCandidates({
    required List<FinanceNews> newsItems,
    required List<String> stocks,
    required String market,
  }) {
    if (stocks.isEmpty) return const [];

    final scores = <String, double>{};
    final themeMap = market == 'kospi'
        ? _kospiThemeCandidates
        : _kosdaqThemeCandidates;

    void addScore(String stock, double score) {
      if (!stocks.contains(stock)) return;
      scores.update(stock, (value) => value + score, ifAbsent: () => score);
    }

    final directMatches = _findDirectMentionedStocks(
      newsItems: newsItems,
      stocks: stocks,
    );
    for (final stock in directMatches) {
      addScore(stock, 10);
    }

    for (final item in newsItems) {
      final sourceText =
          '${item.title} ${item.description} ${item.keywords.join(' ')}'
              .toLowerCase();
      final sentimentWeight = item.sentimentScore.abs() >= 0.25 ? 1.3 : 1.0;
      final importanceWeight = 1 + (item.importanceLevel * 0.18);

      for (final entry in themeMap.entries) {
        final matchCount = entry.key.where(sourceText.contains).length;
        if (matchCount == 0) continue;
        final score = matchCount * sentimentWeight * importanceWeight;
        for (final candidate in entry.value) {
          addScore(candidate, score);
        }
      }
    }

    final fallback =
        (market == 'kospi'
                ? _kospiFallbackCandidates
                : _kosdaqFallbackCandidates)
            .where(stocks.contains);
    for (final stock in fallback) {
      addScore(stock, 0.25);
    }

    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ranked.map((entry) => entry.key).take(32).toList();
  }

  List<String> _findDirectMentionedStocks({
    required List<FinanceNews> newsItems,
    required List<String> stocks,
  }) {
    if (stocks.isEmpty) return const [];

    final sourceTexts = newsItems
        .map(
          (item) =>
              '${item.title} ${item.description} ${item.keywords.join(' ')}',
        )
        .join(' ')
        .toLowerCase();

    final sortedStocks = [...stocks]
      ..sort((a, b) => b.length.compareTo(a.length));
    final matches = <String>[];

    for (final stock in sortedStocks) {
      if (stock.length < 2) continue;
      if (sourceTexts.contains(stock.toLowerCase())) {
        matches.add(stock);
      }
    }

    return matches;
  }

  static const Map<List<String>, List<String>> _kospiThemeCandidates = {
    ['반도체', 'ai', 'hbm', '메모리']: ['삼성전자', 'SK하이닉스'],
    ['2차전지', '배터리', '전기차']: ['LG에너지솔루션', '삼성SDI', '포스코퓨처엠'],
    ['방산', '전쟁', '국방']: ['한화에어로스페이스', '현대로템'],
    ['원전', '전력', '전기']: ['두산에너빌리티', '한국전력'],
    ['자동차', '자율주행', '완성차']: ['현대차', '기아'],
    ['조선', '해운', 'lng']: ['HD현대중공업', '한화오션'],
    ['바이오', '제약', '헬스케어']: ['삼성바이오로직스', '셀트리온'],
    ['인터넷', '플랫폼', '광고']: ['NAVER', '카카오'],
  };

  static const Map<List<String>, List<String>> _kosdaqThemeCandidates = {
    ['2차전지', '배터리', '전기차']: ['에코프로비엠', '에코프로'],
    ['바이오', '제약', '헬스케어']: ['알테오젠', 'HLB'],
    ['반도체', 'hbm', '장비']: ['HPSP', '리노공업'],
    ['로봇', '자동화']: ['레인보우로보틱스'],
    ['엔터', '콘텐츠']: ['JYP Ent.'],
  };

  static const List<String> _kospiFallbackCandidates = [
    '삼성전자',
    'SK하이닉스',
    '현대차',
    '기아',
    'LG에너지솔루션',
    '삼성바이오로직스',
    '한화에어로스페이스',
    '두산에너빌리티',
    'NAVER',
    '카카오',
  ];

  static const List<String> _kosdaqFallbackCandidates = [
    '에코프로비엠',
    '에코프로',
    '알테오젠',
    'HLB',
    '레인보우로보틱스',
    'HPSP',
    '리노공업',
    'JYP Ent.',
  ];

  /// AI 응답 텍스트를 포맷팅 + KRX 목록으로 코스피/코스닥 교차 검증
  /// 코스피 리스트 종목이 코스닥에, 코스닥 리스트 종목이 코스피에 잘못 배치된 경우 제거
  String _formatAndValidate(
    String text,
    List<String> kospiStocks,
    List<String> kosdaqStocks, {
    List<String> kospiCandidates = const [],
    List<String> kosdaqCandidates = const [],
    List<String> directMentionedKospi = const [],
    List<String> directMentionedKosdaq = const [],
  }) {
    final cleanText = text
        .replaceAll(RegExp(r'\n+'), '\n')
        .replaceAll(RegExp(r'^\s+|\s+$', multiLine: true), '')
        .trim();

    final lines = cleanText
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();

    final highlightPattern = RegExp(r'^하이라이트\s*:');
    final analysisTitlePattern = RegExp(r'^분석제목\s*:');
    final analysisContentPattern = RegExp(r'^분석내용\s*:');

    final highlights = <String>[];
    final analysisTitles = <String>[];
    final analysisContents = <String>[];
    String? bullSector, bearSector;
    final Map<String, String> pickMap = {};

    for (final l in lines) {
      final t = l.trim();
      if (highlightPattern.hasMatch(t)) {
        highlights.add(t.replaceFirst(highlightPattern, '').trim());
      } else if (analysisTitlePattern.hasMatch(t)) {
        analysisTitles.add(t.replaceFirst(analysisTitlePattern, '').trim());
      } else if (analysisContentPattern.hasMatch(t)) {
        analysisContents.add(t.replaceFirst(analysisContentPattern, '').trim());
      } else {
        final sM = RegExp(r'^(강세섹터|약세섹터)\s*:\s*(.+)').firstMatch(t);
        if (sM != null) {
          if (sM.group(1) == '강세섹터') {
            bullSector = sM.group(2)!.trim();
          } else {
            bearSector = sM.group(2)!.trim();
          }
          continue;
        }
        final pM = RegExp(
          r'^(강세추천|약세주의)\s+(코스피|코스닥|나스닥|코인)\s*:\s*(.+)',
        ).firstMatch(t);
        if (pM != null) {
          pickMap['${pM.group(1)!} ${pM.group(2)!}'] = pM.group(3)!.trim();
        }
      }
    }

    // fallback
    while (highlights.length < 3) {
      highlights.add('-');
    }
    while (analysisTitles.length < 2) {
      analysisTitles.add('-');
    }
    while (analysisContents.length < 2) {
      analysisContents.add('-');
    }

    final result = StringBuffer();
    for (final h in highlights.take(3)) {
      result.writeln('하이라이트: $h');
    }
    for (var i = 0; i < 2; i++) {
      result.writeln('분석제목: ${analysisTitles[i]}');
      result.writeln('분석내용: ${analysisContents[i]}');
    }
    result.writeln('강세섹터: ${bullSector ?? '-'}');
    result.writeln('약세섹터: ${bearSector ?? '-'}');
    // KRX 목록이 있으면 잘못 배치된 종목 교차 제거
    final validated = _rebalancePicks(
      pickMap,
      kospiStocks,
      kosdaqStocks,
      kospiCandidates: kospiCandidates,
      kosdaqCandidates: kosdaqCandidates,
      directMentionedKospi: directMentionedKospi,
      directMentionedKosdaq: directMentionedKosdaq,
    );
    final bullishCoinPicks = _ensureCoinPickCount(
      pickMap['강세추천 코인'] ?? '-',
      bullish: true,
      contextText: cleanText,
    );
    final bearishCoinPicks = _ensureCoinPickCount(
      pickMap['약세주의 코인'] ?? '-',
      bullish: false,
      contextText: cleanText,
    );

    result.writeln('강세추천 코스피: ${validated['강세추천 코스피'] ?? '-'}');
    result.writeln('강세추천 코스닥: ${validated['강세추천 코스닥'] ?? '-'}');
    result.writeln('강세추천 나스닥: ${validated['강세추천 나스닥'] ?? '-'}');
    result.writeln('강세추천 코인: $bullishCoinPicks');
    result.writeln('약세주의 코스피: ${validated['약세주의 코스피'] ?? '-'}');
    result.writeln('약세주의 코스닥: ${validated['약세주의 코스닥'] ?? '-'}');
    result.writeln('약세주의 나스닥: ${validated['약세주의 나스닥'] ?? '-'}');
    result.write('약세주의 코인: $bearishCoinPicks');

    return result.toString();
  }

  /// KRX 상장 목록 기반으로 코스피/코스닥 추천 종목 교차 오배치 제거
  /// - 코스닥 상장 종목이 코스피 추천에 등장 → 코스피에서 제거
  /// - 코스피 상장 종목이 코스닥 추천에 등장 → 코스닥에서 제거
  Map<String, String> _rebalancePicks(
    Map<String, String> pickMap,
    List<String> kospiStocks,
    List<String> kosdaqStocks, {
    List<String> kospiCandidates = const [],
    List<String> kosdaqCandidates = const [],
    List<String> directMentionedKospi = const [],
    List<String> directMentionedKosdaq = const [],
  }) {
    final kospiSet = kospiStocks.toSet();
    final kosdaqSet = kosdaqStocks.toSet();
    final kospiCandidateSet = kospiCandidates.toSet();
    final kosdaqCandidateSet = kosdaqCandidates.toSet();
    final directMentionedKospiSet = directMentionedKospi.toSet();
    final directMentionedKosdaqSet = directMentionedKosdaq.toSet();
    // 이름(이유) 형식에서 종목명만 추출
    final itemPattern = RegExp(r'^(.+?)(?:\[[^\]]+\])?\(');

    String filterOut(
      String items,
      Set<String> excludeSet, {
      Set<String>? allowedSet,
      Set<String>? allowExtraSet,
    }) {
      if (items == '-' || items.isEmpty) return items;
      final rawItems = items.split(RegExp(r',\s*(?=[^)]*(?:\(|$))'));
      final kept = rawItems.where((t) {
        final name = (itemPattern.firstMatch(t.trim())?.group(1) ?? t).trim();
        if (name == '-' || name == '없음') return false;
        if (excludeSet.contains(name)) return false;
        if (allowedSet != null &&
            allowedSet.isNotEmpty &&
            !allowedSet.contains(name)) {
          if (allowExtraSet == null || !allowExtraSet.contains(name)) {
            return false;
          }
        }
        return true;
      }).toList();
      return kept.isEmpty ? '-' : kept.join(', ');
    }

    return {
      ...pickMap,
      '강세추천 코스피': kospiStocks.isEmpty
          ? (pickMap['강세추천 코스피'] ?? '-')
          : filterOut(
              pickMap['강세추천 코스피'] ?? '-',
              kosdaqSet,
              allowedSet: kospiCandidateSet,
              allowExtraSet: directMentionedKospiSet,
            ),
      '강세추천 코스닥': kosdaqStocks.isEmpty
          ? (pickMap['강세추천 코스닥'] ?? '-')
          : filterOut(
              pickMap['강세추천 코스닥'] ?? '-',
              kospiSet,
              allowedSet: kosdaqCandidateSet,
              allowExtraSet: directMentionedKosdaqSet,
            ),
      '강세추천 나스닥': pickMap['강세추천 나스닥'] ?? '-',
      '약세주의 코스피': kospiStocks.isEmpty
          ? (pickMap['약세주의 코스피'] ?? '-')
          : filterOut(
              pickMap['약세주의 코스피'] ?? '-',
              kosdaqSet,
              allowedSet: kospiCandidateSet,
              allowExtraSet: directMentionedKospiSet,
            ),
      '약세주의 코스닥': kosdaqStocks.isEmpty
          ? (pickMap['약세주의 코스닥'] ?? '-')
          : filterOut(
              pickMap['약세주의 코스닥'] ?? '-',
              kospiSet,
              allowedSet: kosdaqCandidateSet,
              allowExtraSet: directMentionedKosdaqSet,
            ),
      '약세주의 나스닥': pickMap['약세주의 나스닥'] ?? '-',
    };
  }

  String _ensureCoinPickCount(
    String items, {
    required bool bullish,
    required String contextText,
  }) {
    final normalizedItems = items.trim();
    final itemPattern = RegExp(r'^(.+?)(?:\[[^\]]+\])?\((.+?)\)$');
    final existingTokens =
        normalizedItems == '-' ||
            normalizedItems.isEmpty ||
            normalizedItems == '없음'
        ? <String>[]
        : normalizedItems
              .split(RegExp(r',\s*(?=[^)]*(?:\(|$))'))
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList();
    final existingNames = existingTokens
        .map((item) => (itemPattern.firstMatch(item)?.group(1) ?? item).trim())
        .toSet();

    if (existingTokens.length >= 6) {
      return existingTokens.take(6).join(', ');
    }

    final pool = _selectCoinFallbackPool(
      bullish: bullish,
      contextText: contextText,
    );
    final merged = <String>[...existingTokens];

    for (final candidate in pool) {
      final name = candidate['name']!;
      if (existingNames.contains(name)) continue;
      merged.add(
        '${candidate['name']}[${candidate['sector']}](${candidate['reason']})',
      );
      existingNames.add(name);
      if (merged.length >= 6) break;
    }

    return merged.isEmpty ? '-' : merged.take(6).join(', ');
  }

  List<Map<String, String>> _selectCoinFallbackPool({
    required bool bullish,
    required String contextText,
  }) {
    final normalized = contextText.toLowerCase();
    final pool = bullish
        ? List<Map<String, String>>.from(_bullishCoinFallbackPool)
        : List<Map<String, String>>.from(_bearishCoinFallbackPool);

    bool prioritize(Iterable<String> keywords) {
      return keywords.any((keyword) => normalized.contains(keyword));
    }

    void moveToFront(List<String> names) {
      pool.sort((a, b) {
        final aIndex = names.indexOf(a['name']!);
        final bIndex = names.indexOf(b['name']!);
        final aRank = aIndex == -1 ? 999 : aIndex;
        final bRank = bIndex == -1 ? 999 : bIndex;
        return aRank.compareTo(bRank);
      });
    }

    if (prioritize(['etf', '기관', '제도권', 'risk on', '위험자산', '유동성'])) {
      moveToFront(['BTC', 'ETH', 'SOL', 'XRP', 'BNB', 'LINK']);
    } else if (prioritize(['규제', '해킹', '달러 강세', '위험회피', '관세'])) {
      moveToFront(['DOGE', 'SUI', 'AVAX', 'SOL', 'ADA', 'XRP']);
    } else if (prioritize(['결제', '송금', '은행', '리플'])) {
      moveToFront(['XRP', 'XLM', 'BTC', 'ETH', 'LINK', 'BNB']);
    } else if (prioritize(['ai', '반도체', '데이터센터', '전력', '인프라'])) {
      moveToFront(['ETH', 'SOL', 'LINK', 'AVAX', 'SUI', 'BTC']);
    }

    return pool;
  }
}
