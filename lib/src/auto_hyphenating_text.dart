import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:hyphenator_impure/hyphenator.dart';

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
    this.shouldHyphenate,
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
    this.hyphenationCharacter = '‐',
    this.selectable = false,
    super.key,
  });

  final List<TextFragment> textFragments; // TODO removed effective text style stuff, need to be explicit

  /// An object that allows for computing acceptable hyphenation locations.
  final ResourceLoader? loader;

  /// A function to tell us if we should apply hyphenation. If not given we will always hyphenate if possible.
  final bool Function(double totalLineWidth, double lineWidthAlreadyUsed, double currentWordWidth)? shouldHyphenate;

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
  late List<List<String>> fragmentWords;
  late List<int> fragmentEnds;
  late List<TextStyle> fragmentStyles;
  late List<String> wordsMerged;
  late Map<int, GestureRecognizer> wordRecognizers;
  late int wordCount;
  late int lastWordIndex;
  void initFragments() {
    fragmentWords = widget.textFragments.map((e) => e.text.split(" ")).toList();
    fragmentEnds = [];
    for (final list in fragmentWords) {
      fragmentEnds.add(list.length + (fragmentEnds.lastOrNull ?? 0));
    }
    fragmentStyles = widget.textFragments.map((e) => e.style).toList();
    wordsMerged = [
      for (final list in fragmentWords) //
        ...list,
    ];
    wordCount = wordsMerged.length;
    lastWordIndex = wordCount - 1;

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

  @override
  void initState() {
    super.initState();
    initFragments();
  }

  @override
  void didUpdateWidget(covariant AutoHyphenatingText oldWidget) {
    super.didUpdateWidget(oldWidget);

    // TODO ? listEquals
    if (oldWidget.textFragments != widget.textFragments) {
      initFragments();
    }
  }

  @override
  void dispose() {
    disposeFragments();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.textFragments.isEmpty) return const SizedBox();

    return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      int currentFragmentIndex = 0;
      int currentEnd = fragmentEnds.first;
      TextStyle currentStyle = fragmentStyles.first;
      double singleSpaceWidth = getTextWidth(" ", currentStyle, widget.textDirection, widget.textScaleFactor);
      void updateOnNextFragment(int i) {
        if (i > currentEnd) {
          currentFragmentIndex += 1;
          currentStyle = fragmentStyles[currentFragmentIndex];
          currentEnd = fragmentEnds[currentFragmentIndex];
          singleSpaceWidth = getTextWidth(" ", currentStyle, widget.textDirection, widget.textScaleFactor);
        }
      }

      List<TextSpan> texts = <TextSpan>[];

      assert(globalLoader != null, "AutoHyphenatingText not initialized! Remember to call initHyphenation().");
      final Hyphenator hyphenator = Hyphenator(
        resource: widget.loader ?? globalLoader!,
        hyphenateSymbol: '_',
      );

      double currentLineSpaceUsed = 0;
      int lines = 0;

      double endBuffer = currentStyle.overflow == TextOverflow.ellipsis
          ? getTextWidth("…", currentStyle, widget.textDirection, widget.textScaleFactor)
          : 0;

      for (int i = 0; i < wordCount; i++) {
        final wordRecognizer = wordRecognizers[i];
        final word = wordsMerged[i];
        double wordWidth = getTextWidth(word, currentStyle, widget.textDirection, widget.textScaleFactor);
        late final wordSpan = TextSpan(
          text: word,
          style: currentStyle,
          recognizer: wordRecognizer,
          mouseCursor: wordRecognizer == null ? null : SystemMouseCursors.click,
        );

        if (currentLineSpaceUsed + wordWidth < constraints.maxWidth - endBuffer) {
          texts.add(wordSpan);
          currentLineSpaceUsed += wordWidth;
        } else {
          final List<String> syllables = word.length == 1 ? <String>[word] : hyphenator.hyphenateWordToList(word);
          final int? syllableToUse = word.length == 1
              ? null
              : getLastSyllableIndex(syllables, constraints.maxWidth - currentLineSpaceUsed, currentStyle, lines);

          if (syllableToUse == null ||
              (widget.shouldHyphenate != null &&
                  !widget.shouldHyphenate!(constraints.maxWidth, currentLineSpaceUsed, wordWidth))) {
            if (currentLineSpaceUsed == 0) {
              texts.add(wordSpan);
              currentLineSpaceUsed += wordWidth;
            } else {
              i--;
              if (texts.last.text == " ") {
                texts.removeLast();
              }
              currentLineSpaceUsed = 0;
              lines++;
              if (effectiveMaxLines() != null && lines >= effectiveMaxLines()!) {
                if (widget.overflow == TextOverflow.ellipsis) {
                  texts.add(
                    TextSpan(
                      text: "…",
                      style: currentStyle,
                    ),
                  );
                }
                break;
              }
              texts.add(const TextSpan(text: "\n"));
            }
            continue;
          } else {
            texts.add(
              TextSpan(
                text: mergeSyllablesFront(
                  syllables,
                  syllableToUse,
                  allowHyphen: allowHyphenation(lines),
                ),
                style: currentStyle,
              ),
            );
            wordsMerged.insert(i + 1, mergeSyllablesBack(syllables, syllableToUse));
            currentLineSpaceUsed = 0;
            lines++;
            if (effectiveMaxLines() != null && lines >= effectiveMaxLines()!) {
              if (widget.overflow == TextOverflow.ellipsis) {
                texts.add(
                  TextSpan(
                    text: "…",
                    style: currentStyle,
                  ),
                );
              }
              break;
            }
            texts.add(const TextSpan(text: "\n"));
            continue;
          }
        }

        if (i != lastWordIndex) {
          updateOnNextFragment(i);

          if (currentLineSpaceUsed + singleSpaceWidth < constraints.maxWidth) {
            texts.add(
              TextSpan(
                text: " ",
                style: currentStyle,
              ),
            );
            currentLineSpaceUsed += singleSpaceWidth;
          } else {
            if (texts.last.text == " ") {
              texts.removeLast();
            }
            currentLineSpaceUsed = 0;
            lines++;
            if (effectiveMaxLines() != null && lines >= effectiveMaxLines()!) {
              if (widget.overflow == TextOverflow.ellipsis) {
                texts.add(
                  TextSpan(
                    text: "…",
                    style: currentStyle,
                  ),
                );
              }
              break;
            }
            texts.add(const TextSpan(text: "\n"));
          }
        }
      }

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
