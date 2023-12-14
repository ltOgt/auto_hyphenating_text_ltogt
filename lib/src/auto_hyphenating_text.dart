import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hyphenator_impure/hyphenator.dart';

const _kSpace = " ";
const _kHyphen = '‐';
const _kNewLine = "\n";
const _kEllipsisDots = "…";
const _kHyphenateSymbol = '_';

/// This object is used to tell us acceptable hyphenation positions
/// It is the default loader used unless a custom one is provided
ResourceLoader? globalLoader;

/// Inits the default global hyphenation loader. If this is omitted a custom hyphenation loader must be provided.
Future<void> initHyphenation([DefaultResourceLoaderLanguage language = DefaultResourceLoaderLanguage.enUs]) async {
  globalLoader = await DefaultResourceLoader.load(language);
}

typedef TextFragment = ({String text, TextStyle style, VoidCallback? onTap});

/// A replacement for the default text object which supports hyphenation.
class AutoHyphenatingText extends StatefulWidget {
  const AutoHyphenatingText(
    this.textFragments, {
    this.loader,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaleFactor,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.selectionColor,
    this.hyphenationCharacter = _kHyphen,
    this.selectable = false,
    super.key,
  });

  final List<TextFragment> textFragments; // TODO removed effective text style stuff, need to be explicit

  /// An object that allows for computing acceptable hyphenation locations.
  final ResourceLoader? loader;

  final String hyphenationCharacter;

  final TextAlign? textAlign;
  final StrutStyle? strutStyle;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final double? textScaleFactor;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final Color? selectionColor;
  final bool selectable;

  @override
  State<AutoHyphenatingText> createState() => _AutoHyphenatingTextState();
}

class _AutoHyphenatingTextState extends State<AutoHyphenatingText> {
  @override
  void initState() {
    super.initState();
    initHyphenation();
  }

  late final Hyphenator hyphenator;
  void initHypehnator() {
    assert(globalLoader != null, "AutoHyphenatingText not initialized! Remember to call initHyphenation().");

    hyphenator = Hyphenator(
      resource: widget.loader ?? globalLoader!, // TODO onChange
      hyphenateSymbol: _kHyphenateSymbol,
    );
  }

  /// List of Words for the fragment.
  ///
  /// [initFragments] builds without constraints, unhypehnated

  late List<TextStyle> fragmentStyles;
  late List<String> wordsMerged;
  late Map<int, GestureRecognizer> wordRecognizers;
  void initFragments() {
    // --------
    fragmentWords = widget.textFragments.map((e) => e.text.split(_kSpace)).toList();
    fragmentEnds = [];
    for (final list in fragmentWords) {
      fragmentEnds.add(list.length + (fragmentEnds.lastOrNull ?? 0));
    }
    // -------

    fragmentStyles = widget.textFragments.map((e) => e.style).toList();
    wordsMerged = [
      for (final list in fragmentWords) //
        ...list,
    ];

    wordRecognizers = {};
    for (int i = 0; i < widget.textFragments.length; i++) {
      final callback = widget.textFragments[i].onTap;
      if (callback == null) continue;

      final start = (i == 0) ? 0 : fragmentEnds[i - 1];
      final count = fragmentWords[i].length;
      for (int i = start; i < start + count; i++) {
        wordRecognizers[i] = TapGestureRecognizer()..onTap = callback;
      }
    }
  }

  void disposeFragments() {
    for (final recognizer in wordRecognizers.values) {
      recognizer.dispose();
    }
  }

  /// List of words in this fragment.
  ///
  /// Will be changed during hyphenation.
  late List<List<String>> fragmentWords;
  void initializeWords() {
    fragmentWords = widget.textFragments.map((e) => e.text.split(_kSpace)).toList();
  }

  /// Index of the last word in this fragment
  ///
  /// Will be changed during hyphenation.
  late List<int> fragmentEnds;
  void initializeFragmentEndWordIndex() {
    fragmentEnds = [];
    for (final list in fragmentWords) {
      fragmentEnds.add(list.length + (fragmentEnds.lastOrNull ?? 0));
    }
  }

  /// Constraints for which the last layout was created
  BoxConstraints previousConstraints = const BoxConstraints(); // TODO can probably just do maxWidth

  /// The result of running the layout for [previousConstraints]
  List<TextSpan> previousTextSpans = [];

  /// Build TextSpans with better hypenation for [constraints]
  List<TextSpan> _buildForConstraints(BoxConstraints constraints) {
    if (constraints == previousConstraints) {
      return previousTextSpans;
    }
    previousConstraints = constraints;

    // (1) build word lists for fragment
    initializeWords(); // TODO changing this during the algorithm
    initializeFragmentEndWordIndex(); // TODO need to push these during the algorithm

    // (2) run the algorithm with style per word
    // !!! just build the gesture recognizers on the fly here
    // => words added to the fragment
    // => fragment end indexes
    return _adjustWordsAndEndsWithHyphenation_andBuildTextSpans(constraints.maxWidth);

    // =========================================================================
    // =========================================================================
  }

  List<TextSpan> _adjustWordsAndEndsWithHyphenation_andBuildTextSpans(double maxWidth) {
    /// Keep track of the fragment we are currently in; only increases
    int currentFragmentIndex = 0;

    /// Keep track of the index of the last word in the current fragment
    int currentEnd = fragmentEnds.first;

    /// The style of the current fragment
    TextStyle currentStyle = fragmentStyles.first;

    /// width for a space in the current style
    double singleSpaceWidth = getTextWidth(_kSpace, currentStyle, widget.textDirection, widget.textScaleFactor);
    void updateOnNextFragment(int i) {
      if (i > currentEnd) {
        currentFragmentIndex += 1;
        currentStyle = fragmentStyles[currentFragmentIndex];
        currentEnd = fragmentEnds[currentFragmentIndex];
        singleSpaceWidth = getTextWidth(_kSpace, currentStyle, widget.textDirection, widget.textScaleFactor);
      }
    }

    // =========================================================================

    List<TextSpan> texts = <TextSpan>[];

    double currentLineSpaceUsed = 0;
    int lines = 0;

    ///
    ///
    ///
    ///
    ///
    ///
    /// For each word, of all fragments combined (<- fragments can be on same line)
    ///
    /// adjust the base [fragmentWords] and [fragmentEnds]
    for (int wordIndex = 0; wordIndex < wordsMerged.length; wordIndex++) {
      // Note: the wordIndex may be changed in the loop body
      // Note: wordsMerged.length can change during iterations

      // Note: even though we may change the wordIndex,
      // we never use another word in this iteration
      final word = wordsMerged[wordIndex];
      final wordWidth = getTextWidth(word, currentStyle, widget.textDirection, widget.textScaleFactor);
      final wordSpan = TextSpan(
        text: word,
        style: currentStyle,
      );

      final bool useEllipsis = currentStyle.overflow == TextOverflow.ellipsis;
      final double endBuffer = useEllipsis //
          ? getTextWidth(_kEllipsisDots, currentStyle, widget.textDirection, widget.textScaleFactor)
          : 0;

      final bool fitsOnLine = currentLineSpaceUsed + wordWidth < maxWidth - endBuffer;

      // ....................................................................... WORD FITS IN LINE, go to end-of-word
      if (fitsOnLine) {
        texts.add(wordSpan);
        currentLineSpaceUsed += wordWidth;

        // note: wordsMerged.length can change during iterations
        bool isNotVeryLastWord = wordIndex != wordsMerged.length - 1;
        if (isNotVeryLastWord) {
          updateOnNextFragment(wordIndex);

          if (currentLineSpaceUsed + singleSpaceWidth < maxWidth) {
            texts.add(
              TextSpan(
                text: _kSpace,
                style: currentStyle,
              ),
            );
            currentLineSpaceUsed += singleSpaceWidth;
            continue;
          } else {
            if (texts.last.text == _kSpace) {
              texts.removeLast();
            }
            currentLineSpaceUsed = 0;
            lines++;
            if (effectiveMaxLines() != null && lines >= effectiveMaxLines()!) {
              if (widget.overflow == TextOverflow.ellipsis) {
                texts.add(
                  TextSpan(
                    text: _kEllipsisDots,
                    style: currentStyle,
                  ),
                );
              }
              break;
            }
            texts.add(const TextSpan(text: _kNewLine));
            continue;
          }
        }
        continue;
      }
      // ....................................................................... WORD DOES NOT FIT IN LINE, TODO ? split if possible
      // NOTE: we continue or break in every case in this branch
      else {
        bool isSingleCharacter = word.length == 1;

        final List<String> syllables = isSingleCharacter //
            ? [word]
            : hyphenator.hyphenateWordToList(word);

        final int? lastSyllableIndex = isSingleCharacter //
            ? null
            : getLastSyllableIndex(syllables, maxWidth - currentLineSpaceUsed, currentStyle, lines);

        bool isSingleSyllable = lastSyllableIndex == null;
        bool dontHyphenate = isSingleSyllable;

        /// note: If we dont hyphenate we will break or continue
        if (dontHyphenate) {
          bool isFirstWordInLine = currentLineSpaceUsed == 0;
          if (isFirstWordInLine) {
            /// The word does not fit onto the line, and can not be hyphonated
            /// Its the first word in the line
            /// => We just put it in the line even though it does not fit                                  TODO probably want ellipsis here instead
            texts.add(wordSpan);
            currentLineSpaceUsed += wordWidth;

            /// We dont do end of loop adjustments                                                         TODO why
            continue;
          } else {
            /// The word does not fit onto the line, and can not be hyphonated
            /// Finish up this line and try again on the next one

            /// Remove the trailing space which we added after the previous word from [texts]
            if (texts.last.text == _kSpace) {
              texts.removeLast();
            }

            /// in case we cant try again on the next line, because of maxLines
            /// add ellpisis and terminate the iteration over words
            bool canGoToNextLine = effectiveMaxLines() != null && lines + 1 >= effectiveMaxLines()!;
            if (canGoToNextLine) {
              if (widget.overflow == TextOverflow.ellipsis) {
                texts.add(
                  TextSpan(
                    text: _kEllipsisDots,
                    style: currentStyle,
                  ),
                );
              }
              break;
            }

            /// Otherwise decrement wordIndex to try again
            /// on the nex line
            wordIndex--;
            currentLineSpaceUsed = 0;
            lines++;

            texts.add(const TextSpan(text: _kNewLine));
            continue;
          }
        } else {
          texts.add(
            TextSpan(
              text: mergeSyllablesFront(
                syllables,
                lastSyllableIndex,
                allowHyphen: allowHyphenation(lines),
              ),
              style: currentStyle,
            ),
          );
          wordsMerged.insert(wordIndex + 1, mergeSyllablesBack(syllables, lastSyllableIndex));
          currentLineSpaceUsed = 0;
          lines++;
          if (effectiveMaxLines() != null && lines >= effectiveMaxLines()!) {
            if (widget.overflow == TextOverflow.ellipsis) {
              texts.add(
                TextSpan(
                  text: _kEllipsisDots,
                  style: currentStyle,
                ),
              );
            }
            break;
          }
          texts.add(const TextSpan(text: _kNewLine));
          continue;
        }
      }
    }

    return texts;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.textFragments.isEmpty) return const SizedBox();

    return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      final texts = _buildForConstraints(constraints);

      final SelectionRegistrar? registrar = SelectionContainer.maybeOf(context);
      Widget richText;

      if (widget.selectable) {
        richText = SelectableText.rich(
          TextSpan(locale: widget.locale, children: texts),
          textDirection: widget.textDirection,
          strutStyle: widget.strutStyle,
          textScaleFactor: widget.textScaleFactor ?? MediaQuery.of(context).textScaleFactor,
          textWidthBasis: widget.textWidthBasis ?? TextWidthBasis.parent,
          textAlign: widget.textAlign ?? TextAlign.start,
          maxLines: widget.maxLines,
        );
      } else {
        richText = RichText(
          textDirection: widget.textDirection,
          strutStyle: widget.strutStyle,
          locale: widget.locale,
          softWrap: widget.softWrap ?? true,
          overflow: widget.overflow ?? TextOverflow.clip,
          textScaleFactor: widget.textScaleFactor ?? MediaQuery.of(context).textScaleFactor,
          textWidthBasis: widget.textWidthBasis ?? TextWidthBasis.parent,
          selectionColor: widget.selectionColor,
          textAlign: widget.textAlign ?? TextAlign.start,
          selectionRegistrar: registrar,
          text: TextSpan(
            children: texts,
          ),
        );
      }
      if (registrar != null) {
        richText = MouseRegion(
          cursor: SystemMouseCursors.text,
          child: richText,
        );
      }
      return Semantics(
        textDirection: widget.textDirection,
        label: widget.semanticsLabel,
        child: ExcludeSemantics(
          child: richText,
        ),
      );
    });
  }

  String mergeSyllablesFront(List<String> syllables, int indicesToMergeInclusive, {required bool allowHyphen}) {
    StringBuffer buffer = StringBuffer();

    for (int i = 0; i <= indicesToMergeInclusive; i++) {
      buffer.write(syllables[i]);
    }

    // Only write the hyphen if the character is not punctuation
    String returnString = buffer.toString();
    if (allowHyphen && !RegExp("\\p{P}", unicode: true).hasMatch(returnString[returnString.length - 1])) {
      return "$returnString${widget.hyphenationCharacter}";
    }

    return returnString;
  }

  String mergeSyllablesBack(List<String> syllables, int indicesToMergeInclusive) {
    StringBuffer buffer = StringBuffer();

    for (int i = indicesToMergeInclusive + 1; i < syllables.length; i++) {
      buffer.write(syllables[i]);
    }

    return buffer.toString();
  }

  int? effectiveMaxLines() => widget.overflow == TextOverflow.ellipsis && widget.maxLines == null ? 1 : widget.maxLines;

  bool allowHyphenation(int lines) => widget.overflow != TextOverflow.ellipsis || lines + 1 != effectiveMaxLines();

  double getTextWidth(String text, TextStyle? style, TextDirection? direction, double? scaleFactor) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textScaleFactor: scaleFactor ?? MediaQuery.of(context).textScaleFactor,
      maxLines: 1,
      textDirection: direction ?? Directionality.of(context),
    )..layout();
    return textPainter.size.width;
  }

  int? getLastSyllableIndex(List<String> syllables, double availableSpace, TextStyle? effectiveTextStyle, int lines) {
    if (getTextWidth(mergeSyllablesFront(syllables, 0, allowHyphen: allowHyphenation(lines)), effectiveTextStyle,
            widget.textDirection, widget.textScaleFactor) >
        availableSpace) {
      return null;
    }

    int lowerBound = 0;
    int upperBound = syllables.length;

    while (lowerBound != upperBound - 1) {
      int testIndex = ((lowerBound + upperBound) * 0.5).floor();

      if (getTextWidth(mergeSyllablesFront(syllables, testIndex, allowHyphen: allowHyphenation(lines)),
              effectiveTextStyle, widget.textDirection, widget.textScaleFactor) >
          availableSpace) {
        upperBound = testIndex;
      } else {
        lowerBound = testIndex;
      }
    }

    return lowerBound;
  }
}
