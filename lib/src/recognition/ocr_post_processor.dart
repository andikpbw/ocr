import '../models/ocr_entity.dart';
import '../models/ocr_geometry.dart';
import '../models/ocr_result.dart';

/// Context-aware linguistic & numeric post-processor and structured semantic
/// entity extractor.
class OcrPostProcessor {
  const OcrPostProcessor._();

  static const Map<String, String> _letterToDigit = <String, String>{
    'O': '0',
    'o': '0',
    'D': '0',
    'Q': '0',
    'I': '1',
    'l': '1',
    '|': '1',
    '!': '1',
    'Z': '2',
    'z': '2',
    'S': '5',
    's': '5',
    'b': '6',
    'G': '6',
    'B': '8',
    'g': '9',
    'q': '9',
  };

  static const Map<String, String> _digitToUpper = <String, String>{
    '0': 'O',
    '1': 'I',
    '2': 'Z',
    '5': 'S',
    '6': 'G',
    '8': 'B',
  };

  static const Map<String, String> _digitToLower = <String, String>{
    '0': 'o',
    '1': 'l',
    '2': 'z',
    '5': 's',
    '6': 'b',
    '8': 'b',
  };

  /// Disambiguates visually confusable characters (`0`/`O`/`o`, `1`/`l`/`I`/`|`,
  /// `5`/`S`, `8`/`B`) inside a recognized word using neighbor context while
  /// strictly verifying that any swapped symbol exists among the classifier's
  /// top-K candidate alternatives.
  static List<OcrCharacter> refineWordCharacters(
    List<OcrCharacter> chars, {
    String? previousWordText,
  }) {
    if (chars.length <= 1) return chars;

    // Split compound hyphenated/slashed tokens (e.g. `#INV-2026-0842`,
    // `ORD/9941`) into independent segments so alphabetic prefixes (`INV`) are
    // never coerced into digits by trailing numeric segments (`2026-0842`).
    final hasDelimiter = chars.any(
      (OcrCharacter c) => c.text == '-' || c.text == '/',
    );
    if (hasDelimiter) {
      final combined = <OcrCharacter>[];
      var segStart = 0;
      for (var i = 0; i <= chars.length; i++) {
        final atDelim =
            i == chars.length || chars[i].text == '-' || chars[i].text == '/';
        if (!atDelim) continue;
        if (i > segStart) {
          combined.addAll(
            _refineSegment(
              chars.sublist(segStart, i),
              previousWordText: segStart == 0 ? previousWordText : null,
            ),
          );
        }
        if (i < chars.length) {
          combined.add(chars[i]);
        }
        segStart = i + 1;
      }
      return combined;
    }

    return _refineSegment(chars, previousWordText: previousWordText);
  }

  static List<OcrCharacter> _refineSegment(
    List<OcrCharacter> chars, {
    String? previousWordText,
  }) {
    if (chars.length <= 1) return chars;

    // Count unambiguous digits and letters to infer word class.
    var strongDigits = 0;
    var strongUpper = 0;
    var strongLower = 0;
    var hasCurrencyOrMath = false;

    for (final c in chars) {
      final ch = c.text;
      if (_isStrongDigit(ch)) strongDigits++;
      if (_isStrongUpper(ch)) strongUpper++;
      if (_isStrongLower(ch)) strongLower++;
      if (ch == r'$' || ch == '%' || ch == '€' || ch == '£' || ch == '¥') {
        hasCurrencyOrMath = true;
      }
    }

    final totalLetters = strongUpper + strongLower;
    final isNumericWord =
        (strongDigits > 0 && totalLetters == 0) ||
        (hasCurrencyOrMath && strongDigits >= totalLetters) ||
        (strongDigits >= 2 && strongDigits >= totalLetters * 2);
    final isAlphabeticWord = totalLetters > 0 && strongDigits == 0;
    final isAllUpperWord =
        isAlphabeticWord && strongUpper >= 2 && strongLower == 0;

    final out = List<OcrCharacter>.from(chars);

    for (var i = 0; i < out.length; i++) {
      final curr = out[i];
      final ch = curr.text;

      // Case 1: Numeric token (amounts, dates, phone numbers, counts).
      if (isNumericWord) {
        final mapped = _letterToDigit[ch];
        if (mapped != null) {
          final swapped = _swapIfSupported(curr, mapped, maxDelta: 0.22);
          if (swapped != null) {
            out[i] = swapped;
            continue;
          }
        }
      }

      // Case 2: Alphabetic word — fix stray digits (`0`->`O`/`o`, `1`->`l`/`I`)
      // and ambiguous vertical stems (`I` vs `l` vs `|`).
      if (isAlphabeticWord) {
        final prevIsLower = i > 0 && _isLower(out[i - 1].text);
        final nextIsLower = i + 1 < out.length && _isLower(out[i + 1].text);
        final prevIsUpper = i > 0 && _isUpper(out[i - 1].text);
        final nextIsUpper = i + 1 < out.length && _isUpper(out[i + 1].text);

        if (_isDigit(ch)) {
          final preferUpper =
              isAllUpperWord ||
              (i == 0 && nextIsUpper) ||
              (prevIsUpper && nextIsUpper);
          final target = preferUpper ? _digitToUpper[ch] : _digitToLower[ch];
          if (target != null) {
            final swapped = _swapIfSupported(curr, target, maxDelta: 0.22);
            if (swapped != null) {
              out[i] = swapped;
              continue;
            }
          }
        }

        // Resolve `|` -> `l` or `I` inside alphabetic words.
        if (ch == '|') {
          final target = (isAllUpperWord || (i == 0 && nextIsUpper))
              ? 'I'
              : 'l';
          final swapped = _swapIfSupported(curr, target, maxDelta: 0.26);
          if (swapped != null) {
            out[i] = swapped;
            continue;
          }
        }

        // Resolve uppercase `I` sitting strictly inside lowercase letters (`HeIIo` -> `Hello`),
        // or at word start mid-sentence after an all-lowercase word (`the Iazy` -> `the lazy`).
        final midSentenceAfterLower =
            i == 0 &&
            nextIsLower &&
            previousWordText != null &&
            previousWordText.isNotEmpty &&
            _isLower(previousWordText[previousWordText.length - 1]);
        if (ch == 'I' &&
            !isAllUpperWord &&
            (prevIsLower || (i > 0 && nextIsLower) || midSentenceAfterLower)) {
          final swapped = _swapIfSupported(
            curr,
            'l',
            maxDelta: midSentenceAfterLower ? 0.08 : 0.18,
          );
          if (swapped != null) {
            out[i] = swapped;
            continue;
          }
        }

        // Resolve lowercase `l` inside ALL-CAPS words (`FLLTTER` / `TOTA1` / `INV`).
        if (ch == 'l' && isAllUpperWord) {
          final swapped = _swapIfSupported(curr, 'I', maxDelta: 0.18);
          if (swapped != null) {
            out[i] = swapped;
            continue;
          }
        }
      } else {
        // Mixed alphanumeric (e.g. `INV-2026-0842`, `v1.0`, `ID01`): resolve
        // localized runs of digits separated by `-` or `/`.
        final prevIsDigit = i > 0 && _isDigit(out[i - 1].text);
        final nextIsDigit = i + 1 < out.length && _isDigit(out[i + 1].text);
        if (prevIsDigit && nextIsDigit) {
          final mapped = _letterToDigit[ch];
          if (mapped != null) {
            final swapped = _swapIfSupported(curr, mapped, maxDelta: 0.18);
            if (swapped != null) {
              out[i] = swapped;
            }
          }
        }
      }
    }

    return out;
  }

  static OcrCharacter? _swapIfSupported(
    OcrCharacter current,
    String targetChar, {
    required double maxDelta,
  }) {
    if (current.text == targetChar) return null;
    for (final alt in current.alternatives) {
      if (alt.character == targetChar &&
          alt.confidence >= current.confidence - maxDelta) {
        return current.copyWith(text: targetChar, confidence: alt.confidence);
      }
    }
    return null;
  }

  static bool _isDigit(String c) =>
      c.length == 1 && c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  static bool _isUpper(String c) =>
      c.length == 1 && c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 90;

  static bool _isLower(String c) =>
      c.length == 1 && c.codeUnitAt(0) >= 97 && c.codeUnitAt(0) <= 122;

  static bool _isStrongDigit(String c) =>
      c == '2' ||
      c == '3' ||
      c == '4' ||
      c == '6' ||
      c == '7' ||
      c == '8' ||
      c == '9';

  static bool _isStrongUpper(String c) =>
      _isUpper(c) && c != 'O' && c != 'I' && c != 'S' && c != 'B' && c != 'Z';

  static bool _isStrongLower(String c) =>
      _isLower(c) && c != 'o' && c != 'l' && c != 's' && c != 'z';
}

/// Extracts structured semantic entities (emails, URLs, phone numbers, dates,
/// currency amounts, percentages, invoice IDs, card numbers, hashtags, and
/// key-value fields) from recognized text and links them to source bounding
/// boxes.
class OcrEntityExtractor {
  const OcrEntityExtractor._();

  static final RegExp _emailRegex = RegExp(
    r'\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b',
  );

  static final RegExp _urlRegex = RegExp(
    r'\b(?:https?://|www\.)[^\s<>()]+',
    caseSensitive: false,
  );

  static final RegExp _invoiceRegex = RegExp(
    r'\b(?:INV|ORD|REF|PO|DOC|SKU|TXN|REC)(?:[-#/]|\s*#)\s*[A-Z0-9]*(?:\d[A-Z0-9\-]*){2,}\b'
    r'|\b(?:INV|ORD|REF|PO|DOC|SKU|TXN|REC)\d[A-Z0-9\-]{2,}\b',
    caseSensitive: false,
  );

  static final RegExp _dateRegex = RegExp(
    r'\b(?:\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}[-/]\d{2,4}|'
    r'(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{2,4}|'
    r'\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{2,4})\b',
    caseSensitive: false,
  );

  static final RegExp _amountRegex = RegExp(
    r'(?:(?:\$|€|£|¥|Rp\.?|IDR|USD|EUR|GBP|SGD)\s?\d{1,3}(?:[.,]\d{3})*(?:[.,]\d{1,2})?|'
    r'\b\d{1,3}(?:,\d{3})*\.\d{2}\s?(?:USD|EUR|GBP|IDR|SGD)\b)',
  );

  static final RegExp _percentRegex = RegExp(r'\b\d+(?:\.\d+)?%');

  static final RegExp _cardRegex = RegExp(
    r'(?<![A-Za-z0-9*])(?:\d{4}|\*{4})[\s\-](?:\d{4}|\*{4})[\s\-](?:\d{4}|\*{4})[\s\-]\d{4}\b',
  );

  static final RegExp _phoneRegex = RegExp(
    r'(?:(?:\+\d{1,3}[\s\-]?)|(?:\(\d{2,4}\)[\s\-]?))\d{2,4}[\s\-]?\d{3,4}(?:[\s\-]?\d{3,4})?\b',
  );

  static final RegExp _hashtagRegex = RegExp(
    r'#[A-Za-z][A-Za-z0-9_]{1,}(?![A-Za-z0-9_\-])',
  );

  static final RegExp _keyValueLineRegex = RegExp(
    r'^([A-Za-z][A-Za-z0-9 #/._-]{1,28}):\s+(.+)$',
  );

  /// Extracts deduplicated structured [OcrEntity] items from [fullText] and
  /// associates bounding boxes from [words] where available.
  static List<OcrEntity> extract({
    required String fullText,
    required List<OcrWord> words,
    required List<OcrLine> lines,
  }) {
    if (fullText.trim().isEmpty) return const <OcrEntity>[];
    final entities = <OcrEntity>[];
    final seenKeys = <String>{};

    void addMatches(
      RegExp pattern,
      OcrEntityType type, {
      String Function(Match m)? valueSelector,
    }) {
      for (final m in pattern.allMatches(fullText)) {
        final raw = m.group(0)!.trim();
        if (raw.isEmpty) continue;
        final val = (valueSelector != null ? valueSelector(m) : raw).trim();
        final dedupKey = '${type.name}:$val:${m.start}';
        if (!seenKeys.add(dedupKey)) continue;
        final matchInfo = _locateWords(val, words);
        entities.add(
          OcrEntity(
            type: type,
            value: val,
            rawText: raw,
            confidence: matchInfo.confidence,
            boundingBox: matchInfo.boundingBox,
            startIndex: m.start,
            endIndex: m.end,
          ),
        );
      }
    }

    addMatches(_emailRegex, OcrEntityType.email);
    addMatches(_urlRegex, OcrEntityType.url);
    addMatches(_invoiceRegex, OcrEntityType.invoiceNumber);
    addMatches(_dateRegex, OcrEntityType.date);
    addMatches(_amountRegex, OcrEntityType.amount);
    addMatches(_percentRegex, OcrEntityType.percentage);
    addMatches(_cardRegex, OcrEntityType.cardNumber);
    addMatches(_phoneRegex, OcrEntityType.phone);
    addMatches(_hashtagRegex, OcrEntityType.hashtag);

    // Line-level Key: Value structured fields.
    var cursor = 0;
    for (final line in lines) {
      final lineText = line.text.trim();
      final lineStart = fullText.indexOf(lineText, cursor);
      final m = _keyValueLineRegex.firstMatch(lineText);
      if (m != null) {
        final key = m.group(1)!.trim();
        final value = m.group(2)!.trim();
        // Avoid treating URL schemes (`https:`) as key-value fields.
        if (key.toLowerCase() != 'http' &&
            key.toLowerCase() != 'https' &&
            value.isNotEmpty) {
          final dedupKey = 'kv:$key:$value';
          if (seenKeys.add(dedupKey)) {
            entities.add(
              OcrEntity(
                type: OcrEntityType.keyValue,
                label: key,
                value: value,
                rawText: lineText,
                confidence: line.confidence,
                boundingBox: line.boundingBox,
                startIndex: lineStart >= 0 ? lineStart : 0,
                endIndex: lineStart >= 0 ? lineStart + lineText.length : 0,
              ),
            );
          }
        }
      }
      if (lineStart >= 0) cursor = lineStart + lineText.length;
    }

    return entities;
  }

  static _LocatedEntity _locateWords(String text, List<OcrWord> words) {
    if (words.isEmpty) return const _LocatedEntity(null, 0.85);
    final tokens = text
        .split(RegExp(r'\s+'))
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) return const _LocatedEntity(null, 0.85);

    OcrRect? unionBox;
    var confSum = 0.0;
    var matched = 0;

    for (final token in tokens) {
      final lower = token.toLowerCase();
      for (final word in words) {
        if (word.text.toLowerCase().contains(lower) ||
            lower.contains(word.text.toLowerCase())) {
          unionBox = unionBox == null
              ? word.boundingBox
              : unionBox.union(word.boundingBox);
          confSum += word.confidence;
          matched++;
          break;
        }
      }
    }

    return _LocatedEntity(unionBox, matched > 0 ? confSum / matched : 0.85);
  }
}

class _LocatedEntity {
  const _LocatedEntity(this.boundingBox, this.confidence);
  final OcrRect? boundingBox;
  final double confidence;
}
