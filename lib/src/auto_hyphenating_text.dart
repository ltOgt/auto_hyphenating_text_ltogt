import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hyphenator_impure/hyphenator.dart';

/// This object is used to tell us acceptable hyphenation positions
/// It is the default loader used unless a custom one is provided
ResourceLoader? globalLoader;

/// Inits the default global hyphenation loader. If this is omitted a custom hyphenation loader must be provided.
Future<void> initHyphenation([DefaultResourceLoaderLanguage language = DefaultResourceLoaderLanguage.enUs]) async {
  globalLoader = await DefaultResourceLoader.load(language);
}

typedef StyledText = ({String text, TextStyle style});

/// A replacement for the default text object which supports hyphenation.
class AutoHyphenatingText extends StatelessWidget {
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

  final List<StyledText> textFragments; // TODO removed effective text style stuff, need to be explicit

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

  String mergeSyllablesFront(List<String> syllables, int indicesToMergeInclusive, {required bool allowHyphen}) {
    StringBuffer buffer = StringBuffer();

    for (int i = 0; i <= indicesToMergeInclusive; i++) {
      buffer.write(syllables[i]);
    }

    // Only write the hyphen if the character is not punctuation
    String returnString = buffer.toString();
    if (allowHyphen && !RegExp("\\p{P}", unicode: true).hasMatch(returnString[returnString.length - 1])) {
      return "$returnString$hyphenationCharacter";
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

  int? effectiveMaxLines() => overflow == TextOverflow.ellipsis && maxLines == null ? 1 : maxLines;

  bool allowHyphenation(int lines) => overflow != TextOverflow.ellipsis || lines + 1 != effectiveMaxLines();

  @override
  Widget build(BuildContext context) {
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
              textDirection, textScaleFactor) >
          availableSpace) {
        return null;
      }

      int lowerBound = 0;
      int upperBound = syllables.length;

      while (lowerBound != upperBound - 1) {
        int testIndex = ((lowerBound + upperBound) * 0.5).floor();

        if (getTextWidth(mergeSyllablesFront(syllables, testIndex, allowHyphen: allowHyphenation(lines)),
                effectiveTextStyle, textDirection, textScaleFactor) >
            availableSpace) {
          upperBound = testIndex;
        } else {
          lowerBound = testIndex;
        }
      }

      return lowerBound;
    }

    return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      List<List<String>> fragmentWords = textFragments.map((e) => e.text.split(" ")).toList();
      List<int> fragmentEnds = [];
      for (final list in fragmentWords) {
        fragmentEnds.add(list.length + (fragmentEnds.lastOrNull ?? 0));
      }
      List<TextStyle> fragmentStyles = textFragments.map((e) => e.style).toList();
      int currentFragmentIndex = 0; // count up when reached this framentEnd

      int currentEnd = fragmentEnds.first;
      TextStyle currentStyle = fragmentStyles.first; // TODO check empty
      void updateOnNextFragment(int i) {
        if (i > currentEnd) {
          currentFragmentIndex += 1;
          currentStyle = fragmentStyles[currentFragmentIndex];
          currentEnd = fragmentEnds[currentFragmentIndex];
        }
      }

      List<String> wordsMerged = [
        for (final list in fragmentWords) //
          ...list,
      ];
      List<TextSpan> texts = <TextSpan>[];

      assert(globalLoader != null, "AutoHyphenatingText not initialized! Remember to call initHyphenation().");
      final Hyphenator hyphenator = Hyphenator(
        resource: loader ?? globalLoader!,
        hyphenateSymbol: '_',
      );

      double singleSpaceWidth = getTextWidth(" ", currentStyle, textDirection, textScaleFactor);
      double currentLineSpaceUsed = 0;
      int lines = 0;

      double endBuffer = currentStyle.overflow == TextOverflow.ellipsis
          ? getTextWidth("…", currentStyle, textDirection, textScaleFactor)
          : 0;

      final wordCount = wordsMerged.length;
      final lastWordIndex = wordCount - 1;
      for (int i = 0; i < wordCount; i++) {
        double wordWidth = getTextWidth(wordsMerged[i], currentStyle, textDirection, textScaleFactor);

        if (currentLineSpaceUsed + wordWidth < constraints.maxWidth - endBuffer) {
          texts.add(
            TextSpan(
              text: wordsMerged[i],
              style: currentStyle,
            ),
          );
          currentLineSpaceUsed += wordWidth;
        } else {
          final List<String> syllables =
              wordsMerged[i].length == 1 ? <String>[wordsMerged[i]] : hyphenator.hyphenateWordToList(wordsMerged[i]);
          final int? syllableToUse = wordsMerged[i].length == 1
              ? null
              : getLastSyllableIndex(syllables, constraints.maxWidth - currentLineSpaceUsed, currentStyle, lines);

          if (syllableToUse == null ||
              (shouldHyphenate != null && !shouldHyphenate!(constraints.maxWidth, currentLineSpaceUsed, wordWidth))) {
            if (currentLineSpaceUsed == 0) {
              texts.add(
                TextSpan(
                  text: wordsMerged[i],
                  style: currentStyle,
                ),
              );
              currentLineSpaceUsed += wordWidth;
            } else {
              i--;
              if (texts.last.text == " ") {
                texts.removeLast();
              }
              currentLineSpaceUsed = 0;
              lines++;
              if (effectiveMaxLines() != null && lines >= effectiveMaxLines()!) {
                if (overflow == TextOverflow.ellipsis) {
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
              if (overflow == TextOverflow.ellipsis) {
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
              if (overflow == TextOverflow.ellipsis) {
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

      if (selectable) {
        richText = SelectableText.rich(
          TextSpan(locale: locale, children: texts),
          textDirection: textDirection,
          strutStyle: strutStyle,
          textScaleFactor: textScaleFactor ?? MediaQuery.of(context).textScaleFactor,
          textWidthBasis: textWidthBasis ?? TextWidthBasis.parent,
          textAlign: textAlign ?? TextAlign.start,
          maxLines: maxLines,
        );
      } else {
        richText = RichText(
          textDirection: textDirection,
          strutStyle: strutStyle,
          locale: locale,
          softWrap: softWrap ?? true,
          overflow: overflow ?? TextOverflow.clip,
          textScaleFactor: textScaleFactor ?? MediaQuery.of(context).textScaleFactor,
          textWidthBasis: textWidthBasis ?? TextWidthBasis.parent,
          selectionColor: selectionColor,
          textAlign: textAlign ?? TextAlign.start,
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
        textDirection: textDirection,
        label: semanticsLabel,
        child: ExcludeSemantics(
          child: richText,
        ),
      );
    });
  }
}
