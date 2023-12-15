// ignore_for_file: non_constant_identifier_names

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

  final List<TextFragment> textFragments; // note: removed effective text style stuff, need to be explicit

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
    //_print("initState");

    /// Not changed during hypenation
    // TODO didUpdate
    _initHyphenator();
    _initializeFragmentWords();
    _initializeFragmentStyles();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  late final Hyphenator hyphenator;
  void _initHyphenator() {
    assert(globalLoader != null, "AutoHyphenatingText not initialized! Remember to call initHyphenation().");

    hyphenator = Hyphenator(
      resource: widget.loader ?? globalLoader!,
      hyphenateSymbol: _kHyphenateSymbol,
    );
  }

  /// List of Words for the fragment.
  ///
  /// Will NOT be changed during [_hyphenate].
  late List<TextStyle> fragmentStyles;
  void _initializeFragmentStyles() {
    fragmentStyles = widget.textFragments.map((e) => e.style).toList();
    //_print("initialized fragmentStyles");
  }

  /// List of words in this fragment.
  ///
  /// Will NOT be changed during [_hyphenate].
  late List<List<String>> fragmentWords;
  void _initializeFragmentWords() {
    fragmentWords = widget.textFragments.map((e) => e.text.split(_kSpace)).toList();
    //_print("initialized fragmentWords: $fragmentWords");
  }

  /// All words from all fragments combined.
  ///
  /// will be changed in [_hyphenate]
  /// on hyphenation
  late List<String> wordsMerged;
  void _initializeWordsMerged() {
    wordsMerged = [
      for (final list in fragmentWords) //
        ...list,
    ];
    //_print("initialized wordsMerged: $wordsMerged");
  }

  /// Index of the last word in this fragment
  ///
  /// Will be changed during [_hyphenate].
  late List<int> fragmentEnds;
  void _initializeFragmentEndWordIndex() {
    fragmentEnds = [];
    for (final wordsInFragment in fragmentWords) {
      fragmentEnds.add(wordsInFragment.length + (fragmentEnds.lastOrNull ?? -1));
    }
    //_print("initialized fragmentEnds: $fragmentEnds");
  }

  Map<int, GestureRecognizer> wordRecognizers = {};
  GestureRecognizer? _registerRecognizer(int wordIndex, int fragmentIndex) {
    final callback = widget.textFragments[fragmentIndex].onTap;
    if (callback == null) return null;

    final recognizer = TapGestureRecognizer()..onTap = callback;
    wordRecognizers[wordIndex] = recognizer;
    return recognizer;
  }

  void _disposeRecognizers() {
    for (final recognizer in wordRecognizers.values) {
      recognizer.dispose();
    }
    wordRecognizers = {};
  }

  ///
  ///
  ///
  ///
  ///
  ///

  /// Constraints for which the last layout was created
  double previousMaxWidth = 0;

  /// The result of running the layout for [previousConstraints]
  List<TextSpan> previousTextSpans = [];

  //void _print(dynamic msg) => print("ü $msg");

  /// Build TextSpans with better hypenation for [constraints]
  List<TextSpan> _buildForConstraints(BoxConstraints constraints) {
    //_print("===========================================");
    //_print("============================================");
    //_print("=============================================");
    //_print("_buildForConstraints $constraints");

    final maxWidth = constraints.maxWidth;
    if (maxWidth == previousMaxWidth) {
      //_print("same max width: $maxWidth");
      return previousTextSpans;
    }
    //_print("changed max width: ($previousMaxWidth => $maxWidth)");
    previousMaxWidth = maxWidth;

    // (1) build word lists for fragment
    _initializeFragmentEndWordIndex(); // TODO need to push these during the algorithm
    _initializeWordsMerged();
    _disposeRecognizers();

    // (2) run the algorithm with style per word
    // !!! just build the gesture recognizers on the fly here
    // => words added to the fragment
    // => fragment end indexes
    previousTextSpans = _hyphenate(constraints.maxWidth);

    return previousTextSpans;
  }

  List<TextSpan> _hyphenate(double maxWidth) {
    /// Keep track of the fragment we are currently in; only increases
    int currentFragmentIndex = 0;

    /// Keep track of the index of the last word in the current fragment
    int currentEnd = fragmentEnds.first;

    /// The style of the current fragment
    TextStyle currentStyle = fragmentStyles.first;

    /// width for a space in the current style
    double singleSpaceWidth = getTextWidth(_kSpace, currentStyle, widget.textDirection, widget.textScaleFactor);
    void updateIfEnteredNewFragment(int i) {
      if (i > currentEnd) {
        currentFragmentIndex += 1;
        currentStyle = fragmentStyles[currentFragmentIndex];
        currentEnd = fragmentEnds[currentFragmentIndex];
        singleSpaceWidth = getTextWidth(_kSpace, currentStyle, widget.textDirection, widget.textScaleFactor);

        //_print("newFragment(index: $currentFragmentIndex, end: $currentEnd)");
      }
    }

    // =========================================================================
    double currentLineSpaceUsed = 0;
    int lineCounter = 0;

    List<TextSpan> texts = <TextSpan>[];

    void addSpaceAfter() {
      texts.add(
        TextSpan(
          text: _kSpace,
          style: currentStyle,
        ),
      );
      currentLineSpaceUsed += singleSpaceWidth;
    }

    // TODO: original compares against a constant, which is added by the equivalent of addSpaceAfter
    //  should probably do the same here, instead of potentially removing user added space
    void deletePreviouslyAddedSpace() {
      if (texts.last.text == _kSpace) {
        //_print("removing previous space");
        texts.removeLast();
      }
    }

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
      //_print("............................");
      //_print("wordIndex: $wordIndex");
      // Note: the wordIndex may be changed in the loop body
      // Note: wordsMerged.length can change during iterations

      updateIfEnteredNewFragment(wordIndex);

      // Note: even though we may change the wordIndex,
      // we never use another word in this iteration
      final word = wordsMerged[wordIndex];
      final wordWidth = getTextWidth(word, currentStyle, widget.textDirection, widget.textScaleFactor);
      final wordTapRecognizer = _registerRecognizer(wordIndex, currentFragmentIndex);
      final wordSpan = TextSpan(
        text: word,
        style: currentStyle,
        recognizer: wordTapRecognizer,
        mouseCursor: wordTapRecognizer == null ? null : SystemMouseCursors.click,
      );
      //_print("word: $word ($wordWidth)");

      final bool useEllipsis = currentStyle.overflow == TextOverflow.ellipsis;
      final double endBuffer = useEllipsis //
          ? getTextWidth(_kEllipsisDots, currentStyle, widget.textDirection, widget.textScaleFactor)
          : 0;

      final bool fitsOnLine = currentLineSpaceUsed + wordWidth < maxWidth - endBuffer;

      // ....................................................................... WORD FITS IN LINE, go to end-of-word
      // NOTE: we continue or break in every case in this branch
      if (fitsOnLine) {
        //_print("fits on line");
        texts.add(wordSpan);
        currentLineSpaceUsed += wordWidth;

        /// If this was not the very last word, add a space before the next one
        /// we will remove it if the next word does not fit.
        // note: wordsMerged.length can change during iterations
        bool anticipateNextWord = wordIndex != wordsMerged.length - 1;
        if (anticipateNextWord) {
          bool spaceFitsOnLine = currentLineSpaceUsed + singleSpaceWidth < maxWidth;
          if (spaceFitsOnLine) {
            //_print("adding space");
            addSpaceAfter();
            continue;
          } else {
            //_print("space does not fit");

            /// Space does not fit on line
            deletePreviouslyAddedSpace();
            currentLineSpaceUsed = 0;
            lineCounter++;
            if (effectiveMaxLines() != null && lineCounter >= effectiveMaxLines()!) {
              //_print("maxLines");
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
            //_print("adding lineBreak");
            texts.add(const TextSpan(text: _kNewLine));
            continue;
          }
        }
        //_print("Next word not anticipated");
        continue;
      }
      // ....................................................................... WORD DOES NOT FIT IN LINE, TODO ? split if possible
      // NOTE: we continue or break in every case in this branch
      else {
        //_print("does not fit on line");
        bool isSingleCharacter = word.length == 1;

        final List<String> syllables = isSingleCharacter //
            ? [word]
            : hyphenator.hyphenateWordToList(word);

        final int? lastSyllableIndex = isSingleCharacter //
            ? null
            : getLastSyllableIndex(syllables, maxWidth - currentLineSpaceUsed, currentStyle, lineCounter);

        bool isSingleSyllable = lastSyllableIndex == null;
        bool dontHyphenate = isSingleSyllable;

        //_print("syllables: $syllables (hypenate: ${!dontHyphenate})");

        /// note: If we dont hyphenate we will break or continue
        if (dontHyphenate) {
          //_print("dont hyphenate");
          bool isFirstWordInLine = currentLineSpaceUsed == 0;
          if (isFirstWordInLine) {
            //_print("is first word, adding");

            /// The word does not fit onto the line, and can not be hyphonated
            /// Its the first word in the line
            /// => We just put it in the line even though it does not fit                                  TODO probably want ellipsis here instead
            texts.add(wordSpan);
            currentLineSpaceUsed += wordWidth;

            /// We dont do end of loop adjustments                                                         TODO why
            continue;
          } else {
            //_print("has words before it on its line");

            /// The word does not fit onto the line, and can not be hyphonated
            /// Finish up this line and try again on the next one

            /// Remove the trailing space which we added after the previous word from [texts]
            deletePreviouslyAddedSpace();

            /// in case we cant try again on the next line, because of maxLines
            /// add ellpisis and terminate the iteration over words
            bool canNotGoToNextLine = effectiveMaxLines() != null && lineCounter + 1 >= effectiveMaxLines()!;
            if (canNotGoToNextLine) {
              //_print("maxLines");
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
            lineCounter++;
            //_print("moving to next line and retry word: $lineCounter");

            texts.add(const TextSpan(text: _kNewLine));
            continue;
          }
        } else {
          /// The word does not fit onto the line, and WE CAN HYPHONATE
          //_print("hyphenate");

          // TODO !!!!!!!!!!!!!!!!!!!!! need to mainly make adjustments here
          //  we insert into wordsMerged here

          final wordPartBefore = mergeSyllablesFront(
            syllables,
            lastSyllableIndex,
            allowHyphen: allowHyphenation(lineCounter),
          );
          texts.add(
            TextSpan(
              text: wordPartBefore,
              style: currentStyle,
              recognizer: wordSpan.recognizer,
              mouseCursor: wordSpan.mouseCursor,
            ),
          );
          //_print("Added part before hyphen to texts: $wordPartBefore");

          final wordPartAfter = mergeSyllablesBack(syllables, lastSyllableIndex);
          wordsMerged.insert(wordIndex + 1, wordPartAfter);
          //_print("Added part after to the words list, not yet to texts: $wordPartAfter"); // TODO print words list

          for (int i = currentFragmentIndex; i < fragmentWords.length; i++) {
            fragmentEnds[i] += 1;
          }
          currentEnd += 1;
          //_print("Adjusted fragmentEnds: $fragmentEnds");

          currentLineSpaceUsed = 0;
          lineCounter++;
          if (effectiveMaxLines() != null && lineCounter >= effectiveMaxLines()!) {
            //_print("maxLines");
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

          //_print("add linebreak to texts");
          texts.add(const TextSpan(text: _kNewLine));
          continue;
        }
      }
    }
    //_print("looping complete, collected texts: ${texts.length}");

    return texts;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.textFragments.isEmpty) return const SizedBox();

    return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      final texts = _buildForConstraints(constraints);

      //_print("received texts: ${texts.length}");

      final SelectionRegistrar? registrar = SelectionContainer.maybeOf(context);
      Widget richText;

      if (widget.selectable) {
        //_print("selectable");
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
        //_print("not selectable");
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
        //_print("mouse region");
        richText = MouseRegion(
          cursor: SystemMouseCursors.text,
          child: richText,
        );
      }
      //_print("return");
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


/**
 * 
 flutter: ü ===========================================
flutter: ü ============================================
flutter: ü =============================================
flutter: ü _buildForConstraints BoxConstraints(0.0<=w<=463.0, 0.0<=h<=244.0)
flutter: ü changed max width: (459.0 => 463.0)
flutter: ü initialized fragmentEnds: [2, 4, 6]
flutter: ü initialized wordsMerged: [automatische, Silbentrennung, automatische, Silbentrennung, automatische, Silbentrennung]
flutter: ü ............................
flutter: ü wordIndex: 0
flutter: ü word: automatische (88.9970703125)
flutter: ü fits on line
flutter: ü adding space
flutter: ü ............................
flutter: ü wordIndex: 1
flutter: ü word: Silbentrennung (100.10546875)
flutter: ü fits on line
flutter: ü adding space
flutter: ü ............................
flutter: ü wordIndex: 2
flutter: ü word: automatische (88.9970703125)
flutter: ü fits on line
flutter: ü adding space
flutter: ü ............................
flutter: ü wordIndex: 3
flutter: ü newFragment(index: 1, end: 4)
flutter: ü word: Silbentrennung (100.10546875)
flutter: ü fits on line
flutter: ü adding space
flutter: ü ............................
flutter: ü wordIndex: 4
flutter: ü word: automatische (88.9970703125)
flutter: ü does not fit on line
flutter: ü syllables: [auto, ma, ti, sche] (hypenate: true)
flutter: ü hyphenate
flutter: ü Added part before hyphen to texts: automati‐
flutter: ü Added part after to the words list, not yet to texts: sche
flutter: ü Adjusted fragmentEnds: [2, 5, 7]
flutter: ü add linebreak to texts
flutter: ü ............................
flutter: ü wordIndex: 5
flutter: ü newFragment(index: 2, end: 7)
flutter: ü word: sche (31.3974609375)
flutter: ü fits on line
flutter: ü adding space
flutter: ü ............................
flutter: ü wordIndex: 6
flutter: ü word: Silbentrennung (100.10546875)
flutter: ü fits on line
flutter: ü Next word not anticipated
 */