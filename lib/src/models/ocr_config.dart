import 'package:flutter/foundation.dart';

import 'ocr_geometry.dart';

/// Binarization algorithm used to separate text foreground from background.
enum OcrBinarizationMethod {
  /// Automatically selects Otsu for uniform backgrounds and Sauvola adaptive
  /// thresholding when uneven illumination or shadows are detected.
  auto,

  /// Global Otsu thresholding maximizing inter-class luminance variance.
  /// Fastest and cleanest for screenshots and flat digital documents.
  otsu,

  /// Local adaptive Sauvola thresholding computed in O(W*H) via integral
  /// images. Excels on camera photos, receipts, and shadowed paper documents.
  sauvola,

  /// Local adaptive Bradley-Roth integral-image mean thresholding.
  bradley,
}

/// Strategy describing how text blocks and lines are organized in the image.
enum OcrPageSegmentationMode {
  /// Automatically segments multi-column pages, paragraphs, headings, and lines.
  auto,

  /// Treats the entire image as a single coherent block of text lines.
  singleBlock,

  /// Expects a single horizontal line of text (e.g., ID numbers, labels, titles).
  singleLine,

  /// Expects a single word or compact token (e.g., captcha, code badge).
  singleWord,

  /// Extracts scattered short text labels across a sparse canvas or UI screen.
  sparseText,
}

/// Target character set profile restricting or expanding recognition symbols.
enum OcrScript {
  /// Standard printable ASCII characters: `A-Z`, `a-z`, `0-9`, and punctuation.
  ascii,

  /// Latin letters and common symbols (`A-Z`, `a-z`, `0-9`, standard punctuation).
  latin,

  /// Numeric characters and financial/date symbols (`0-9`, `.`, `,`, `-`, `+`,
  /// `$`, `%`, `/`, `:`).
  digits,

  /// Letters and digits only (`A-Z`, `a-z`, `0-9`).
  alphanumeric,

  /// Extended Latin including accented European/Indonesian characters when
  /// calibrated with platform fonts.
  extendedLatin,
}

/// Configuration for the computer-vision preprocessing stage prior to OCR.
@immutable
class OcrPreprocessConfig {
  /// Creates an [OcrPreprocessConfig] with sensible defaults for documents
  /// and digital screenshots.
  const OcrPreprocessConfig({
    this.binarization = OcrBinarizationMethod.auto,
    this.autoDeskew = true,
    this.maxDeskewAngle = 15.0,
    this.autoInvertDarkMode = true,
    this.contrastStretch = true,
    this.denoise = false,
    this.despeckle = true,
    this.sauvolaWindowSize = 25,
    this.sauvolaK = 0.28,
    this.bradleyWindowSize = 25,
    this.bradleyThresholdPercent = 12.0,
    this.upscaleSmallImages = true,
    this.minTargetHeight = 48,
    this.maxImageDimension = 2400,
  }) : assert(maxDeskewAngle >= 0 && maxDeskewAngle <= 45),
       assert(sauvolaWindowSize >= 5),
       assert(bradleyWindowSize >= 5),
       assert(maxImageDimension >= 64);

  /// Binarization algorithm for separating ink pixels from background.
  final OcrBinarizationMethod binarization;

  /// Automatically detects and corrects document tilt up to [maxDeskewAngle].
  final bool autoDeskew;

  /// Maximum skew angle in degrees tested during automatic deskewing.
  final double maxDeskewAngle;

  /// Automatically detects dark-mode (light text on dark background) images
  /// and inverts them before segmentation.
  final bool autoInvertDarkMode;

  /// Stretches the luminance histogram between the 2nd and 98th percentiles to
  /// improve faint or low-contrast scans.
  final bool contrastStretch;

  /// Applies a 3x3 median filter before binarization to eliminate impulse noise.
  final bool denoise;

  /// Removes isolated 1-pixel dust speckles from the binary foreground map.
  final bool despeckle;

  /// Neighborhood window diameter (in pixels) for Sauvola local thresholding.
  final int sauvolaWindowSize;

  /// Sensitivity constant `k` in Sauvola's formula (typically `0.2` to `0.5`).
  final double sauvolaK;

  /// Neighborhood window diameter (in pixels) for Bradley-Roth thresholding.
  final int bradleyWindowSize;

  /// Percentage below local mean required to classify a pixel as ink in
  /// Bradley-Roth thresholding.
  final double bradleyThresholdPercent;

  /// Automatically upscales very small input images with bilinear interpolation
  /// for improved stroke separation.
  final bool upscaleSmallImages;

  /// Minimum height threshold below which [upscaleSmallImages] triggers.
  final int minTargetHeight;

  /// Largest allowed image width or height before downscaling for speed.
  final int maxImageDimension;

  /// Returns a copy with selectively overridden preprocessing fields.
  OcrPreprocessConfig copyWith({
    OcrBinarizationMethod? binarization,
    bool? autoDeskew,
    double? maxDeskewAngle,
    bool? autoInvertDarkMode,
    bool? contrastStretch,
    bool? denoise,
    bool? despeckle,
    int? sauvolaWindowSize,
    double? sauvolaK,
    int? bradleyWindowSize,
    double? bradleyThresholdPercent,
    bool? upscaleSmallImages,
    int? minTargetHeight,
    int? maxImageDimension,
  }) {
    return OcrPreprocessConfig(
      binarization: binarization ?? this.binarization,
      autoDeskew: autoDeskew ?? this.autoDeskew,
      maxDeskewAngle: maxDeskewAngle ?? this.maxDeskewAngle,
      autoInvertDarkMode: autoInvertDarkMode ?? this.autoInvertDarkMode,
      contrastStretch: contrastStretch ?? this.contrastStretch,
      denoise: denoise ?? this.denoise,
      despeckle: despeckle ?? this.despeckle,
      sauvolaWindowSize: sauvolaWindowSize ?? this.sauvolaWindowSize,
      sauvolaK: sauvolaK ?? this.sauvolaK,
      bradleyWindowSize: bradleyWindowSize ?? this.bradleyWindowSize,
      bradleyThresholdPercent:
          bradleyThresholdPercent ?? this.bradleyThresholdPercent,
      upscaleSmallImages: upscaleSmallImages ?? this.upscaleSmallImages,
      minTargetHeight: minTargetHeight ?? this.minTargetHeight,
      maxImageDimension: maxImageDimension ?? this.maxImageDimension,
    );
  }
}

/// Top-level configuration controlling every stage of OCR recognition.
@immutable
class OcrConfig {
  /// Creates an [OcrConfig] with balanced defaults for general-purpose OCR.
  const OcrConfig({
    this.script = OcrScript.ascii,
    this.characterWhitelist,
    this.characterBlacklist,
    this.preprocess = const OcrPreprocessConfig(),
    this.segmentationMode = OcrPageSegmentationMode.auto,
    this.enablePostProcessing = true,
    this.extractEntities = true,
    this.enableFontCalibration = true,
    this.calibrationFontFamilies = const <String>[],
    this.minConfidence = 0.0,
    this.maxAlternatives = 3,
    this.regionOfInterest,
  }) : assert(minConfidence >= 0.0 && minConfidence <= 1.0),
       assert(maxAlternatives >= 1 && maxAlternatives <= 10);

  /// Preset tuned for printed documents, contracts, letters, and PDFs.
  factory OcrConfig.document() => const OcrConfig(
    script: OcrScript.ascii,
    preprocess: OcrPreprocessConfig(
      binarization: OcrBinarizationMethod.auto,
      autoDeskew: true,
      contrastStretch: true,
      despeckle: true,
    ),
    segmentationMode: OcrPageSegmentationMode.auto,
    enablePostProcessing: true,
    extractEntities: true,
  );

  /// Preset tuned for receipts, invoices, and photographed paper with uneven
  /// lighting or shadows.
  factory OcrConfig.receipt() => const OcrConfig(
    script: OcrScript.ascii,
    preprocess: OcrPreprocessConfig(
      binarization: OcrBinarizationMethod.sauvola,
      autoDeskew: true,
      contrastStretch: true,
      denoise: true,
      despeckle: true,
      sauvolaWindowSize: 29,
      sauvolaK: 0.25,
    ),
    segmentationMode: OcrPageSegmentationMode.auto,
    enablePostProcessing: true,
    extractEntities: true,
  );

  /// Preset tuned for crisp digital UI screenshots (both light and dark mode).
  factory OcrConfig.screenshot() => const OcrConfig(
    script: OcrScript.ascii,
    preprocess: OcrPreprocessConfig(
      binarization: OcrBinarizationMethod.otsu,
      autoDeskew: false,
      autoInvertDarkMode: true,
      contrastStretch: false,
      despeckle: false,
    ),
    segmentationMode: OcrPageSegmentationMode.auto,
    enablePostProcessing: true,
    extractEntities: true,
  );

  /// Preset restricted to numeric strings, amounts, dates, and serial numbers.
  factory OcrConfig.digitsOnly() => const OcrConfig(
    script: OcrScript.digits,
    preprocess: OcrPreprocessConfig(
      binarization: OcrBinarizationMethod.auto,
      autoDeskew: true,
    ),
    segmentationMode: OcrPageSegmentationMode.singleBlock,
    enablePostProcessing: true,
    extractEntities: true,
  );

  /// Low-latency preset ideal for real-time camera preview streams.
  factory OcrConfig.fast() => const OcrConfig(
    script: OcrScript.ascii,
    preprocess: OcrPreprocessConfig(
      binarization: OcrBinarizationMethod.otsu,
      autoDeskew: false,
      contrastStretch: false,
      despeckle: false,
      maxImageDimension: 1200,
    ),
    segmentationMode: OcrPageSegmentationMode.auto,
    enablePostProcessing: true,
    extractEntities: false,
    maxAlternatives: 2,
  );

  /// Active target script profile.
  final OcrScript script;

  /// Optional explicit set of allowed characters. When non-null and non-empty,
  /// only characters in this string will be considered during classification.
  final String? characterWhitelist;

  /// Optional characters to exclude from classification candidates.
  final String? characterBlacklist;

  /// Image preprocessing parameters.
  final OcrPreprocessConfig preprocess;

  /// Page layout segmentation mode.
  final OcrPageSegmentationMode segmentationMode;

  /// Enables context-aware disambiguation (e.g., resolving `0`/`O` and `1`/`l`
  /// using neighbor context and top-K alternatives).
  final bool enablePostProcessing;

  /// Automatically runs structured entity extraction (emails, URLs, phones,
  /// amounts, dates, invoice IDs, and key-value pairs).
  final bool extractEntities;

  /// Enables automatic runtime font calibration using Flutter's text shaper
  /// when running inside a Flutter engine with system fonts available.
  final bool enableFontCalibration;

  /// Additional Flutter font family names to rasterize into the recognizer
  /// bank when [enableFontCalibration] is enabled.
  final List<String> calibrationFontFamilies;

  /// Minimum confidence threshold `[0.0, 1.0]` used when filtering results.
  final double minConfidence;

  /// Maximum number of top candidate characters stored per [OcrCharacter].
  final int maxAlternatives;

  /// Optional pixel region of interest to crop before running OCR.
  /// Resulting coordinates are automatically mapped back to the full image.
  final OcrRect? regionOfInterest;

  /// Returns the effective set of allowed characters derived from [script],
  /// [characterWhitelist], and [characterBlacklist], or `null` if unrestricted.
  Set<String>? resolveAllowedCharacters() {
    Set<String>? allowed;
    if (characterWhitelist != null && characterWhitelist!.isNotEmpty) {
      allowed = characterWhitelist!.split('').toSet();
    } else {
      switch (script) {
        case OcrScript.ascii:
        case OcrScript.latin:
        case OcrScript.extendedLatin:
          allowed = null;
        case OcrScript.digits:
          allowed = '0123456789.,-+\$%/: '.split('').toSet();
        case OcrScript.alphanumeric:
          allowed =
              'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
                  .split('')
                  .toSet();
      }
    }
    if (characterBlacklist != null && characterBlacklist!.isNotEmpty) {
      final banned = characterBlacklist!.split('').toSet();
      if (allowed != null) {
        allowed = allowed.difference(banned);
      }
    }
    return allowed;
  }

  /// Returns a copy with selectively overridden configuration fields.
  OcrConfig copyWith({
    OcrScript? script,
    String? characterWhitelist,
    String? characterBlacklist,
    OcrPreprocessConfig? preprocess,
    OcrPageSegmentationMode? segmentationMode,
    bool? enablePostProcessing,
    bool? extractEntities,
    bool? enableFontCalibration,
    List<String>? calibrationFontFamilies,
    double? minConfidence,
    int? maxAlternatives,
    OcrRect? regionOfInterest,
  }) {
    return OcrConfig(
      script: script ?? this.script,
      characterWhitelist: characterWhitelist ?? this.characterWhitelist,
      characterBlacklist: characterBlacklist ?? this.characterBlacklist,
      preprocess: preprocess ?? this.preprocess,
      segmentationMode: segmentationMode ?? this.segmentationMode,
      enablePostProcessing: enablePostProcessing ?? this.enablePostProcessing,
      extractEntities: extractEntities ?? this.extractEntities,
      enableFontCalibration:
          enableFontCalibration ?? this.enableFontCalibration,
      calibrationFontFamilies:
          calibrationFontFamilies ?? this.calibrationFontFamilies,
      minConfidence: minConfidence ?? this.minConfidence,
      maxAlternatives: maxAlternatives ?? this.maxAlternatives,
      regionOfInterest: regionOfInterest ?? this.regionOfInterest,
    );
  }
}
