import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart' show MaterialApp, SelectionArea;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app.dart';
import '../data/terms_record.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../shell/home_shell.dart' show kWideWidth;
import '../widgets/buttons.dart';
import '../widgets/pressable.dart';
import '../widgets/scaffold.dart';

/// One section of the terms: its heading and its text. In the text, a
/// blank line starts a new paragraph and a line starting with "• " is one
/// point of a list.
typedef TermsSection = ({String title, String body});

/// The sections of the terms, in order. TERMS.md at the root of the source
/// code holds the same words; a test keeps the two the same.
List<TermsSection> termsSections(AppLocalizations l10n) => [
  (title: l10n.termsDoc1Title, body: l10n.termsDoc1Body),
  (title: l10n.termsDoc2Title, body: l10n.termsDoc2Body),
  (title: l10n.termsDoc3Title, body: l10n.termsDoc3Body),
  (title: l10n.termsDoc4Title, body: l10n.termsDoc4Body),
  (title: l10n.termsDoc5Title, body: l10n.termsDoc5Body),
  (title: l10n.termsDoc6Title, body: l10n.termsDoc6Body),
  (title: l10n.termsDoc7Title, body: l10n.termsDoc7Body),
  (title: l10n.termsDoc8Title, body: l10n.termsDoc8Body),
  (title: l10n.termsDoc9Title, body: l10n.termsDoc9Body),
  (title: l10n.termsDoc10Title, body: l10n.termsDoc10Body),
  (title: l10n.termsDoc11Title, body: l10n.termsDoc11Body),
  (title: l10n.termsDoc12Title, body: l10n.termsDoc12Body),
  (title: l10n.termsDoc13Title, body: l10n.termsDoc13Body),
  (title: l10n.termsDoc14Title, body: l10n.termsDoc14Body),
  (title: l10n.termsDoc15Title, body: l10n.termsDoc15Body),
  (title: l10n.termsDoc16Title, body: l10n.termsDoc16Body),
  (title: l10n.termsDoc17Title, body: l10n.termsDoc17Body),
];

/// Closes the app, for someone who declined the terms: Android is asked to
/// close it, as Back on its first screen would; a PC app ends. Nothing has
/// been opened by then, so there is nothing to put away first.
Future<void> quitApp() async {
  if (Platform.isAndroid) {
    await SystemNavigator.pop();
    return;
  }
  exit(0);
}

/// What the app shows instead of itself until the current terms are
/// accepted. It is its own little app: nothing of DNet's is opened behind
/// it, so declining leaves nothing running.
class TermsGateApp extends StatelessWidget {
  const TermsGateApp({
    super.key,
    required this.onAccept,
    required this.onQuit,
    this.changed = false,
  });

  final VoidCallback onAccept;
  final VoidCallback onQuit;

  /// True when an older version of the terms was accepted before.
  final bool changed;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => context.l10n.appName,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: appTheme,
      color: AppColors.bg,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Color(0x00000000),
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: AppColors.bg,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: ColoredBox(
          color: AppColors.bg,
          child: DefaultTextStyle(style: AppText.base, child: child!),
        ),
      ),
      home: TermsGate(onAccept: onAccept, onQuit: onQuit, changed: changed),
    );
  }
}

/// The terms to accept, or, once declined, a screen that says the app stays
/// closed and offers to read them again or quit. There is no way past it
/// but Accept.
class TermsGate extends StatefulWidget {
  const TermsGate({
    super.key,
    required this.onAccept,
    required this.onQuit,
    this.changed = false,
  });

  final VoidCallback onAccept;
  final VoidCallback onQuit;
  final bool changed;

  @override
  State<TermsGate> createState() => _TermsGateState();
}

class _TermsGateState extends State<TermsGate> {
  bool _declined = false;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: Duration(milliseconds: still ? 0 : 260),
      switchInCurve: Curves.easeOutCubic,
      child: _declined
          ? _Declined(
              key: const ValueKey('declined'),
              onReadAgain: () => setState(() => _declined = false),
              onQuit: widget.onQuit,
            )
          : AppScreen(
              key: const ValueKey('terms'),
              body: TermsView(
                changed: widget.changed,
                onAccept: widget.onAccept,
                onDecline: () => setState(() => _declined = true),
              ),
            ),
    );
  }
}

/// The terms, read again from About. Nothing to accept here.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      header: AppTopBar(title: context.l10n.termsOfUse, divider: true),
      body: TermsView(accepted: AcceptedTerms.maybeOf(context)),
    );
  }
}

/// The whole terms, laid out for the window: one column on a narrow one;
/// on a wide one, a side panel with the summary and the controls, and the
/// list of contents beside the text where there is room.
///
/// With [onAccept] it asks for acceptance, which takes reading to the end,
/// ticking the box and pressing Accept. Without it, it is read-only.
class TermsView extends StatefulWidget {
  const TermsView({
    super.key,
    this.onAccept,
    this.onDecline,
    this.changed = false,
    this.accepted,
  });

  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final bool changed;

  /// The terms accepted before, shown read-only.
  final TermsAcceptance? accepted;

  bool get readOnly => onAccept == null;

  @override
  State<TermsView> createState() => _TermsViewState();
}

class _TermsViewState extends State<TermsView> {
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'Terms');
  final _sectionKeys = List.generate(17, (_) => GlobalKey());

  /// How far down the text has been read, from 0 to 1.
  final _read = ValueNotifier<double>(0);

  /// The section at the top of the view now.
  final _current = ValueNotifier<int>(0);

  /// Once the end has been reached, it stays reached.
  bool _reachedEnd = false;
  bool _ticked = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A window tall enough to show everything has nothing to scroll.
      _onScroll();
      // The keys that move through the text work at once, before anything
      // has been clicked. Asked for outright: the screen around it takes
      // the keyboard for itself as it opens.
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    _read.dispose();
    _current.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (!position.hasContentDimensions) return;
    final max = position.maxScrollExtent;
    _read.value = max <= 0 ? 1 : (position.pixels / max).clamp(0, 1);
    _current.value = _sectionAtTop();
    if (!_reachedEnd && (max <= 0 || position.pixels >= max - 32)) {
      setState(() => _reachedEnd = true);
    }
  }

  int _sectionAtTop() {
    var found = 0;
    for (final (index, key) in _sectionKeys.indexed) {
      final box = key.currentContext?.findRenderObject();
      if (box == null || !box.attached) continue;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) continue;
      final top = viewport.getOffsetToReveal(box, 0).offset;
      if (top > _scroll.offset + 96) break;
      found = index;
    }
    return found;
  }

  Duration get _motion => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 320);

  void _goTo(int section) {
    final target = _sectionKeys[section].currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: _motion,
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollBy(double delta) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final to = (position.pixels + delta).clamp(0.0, position.maxScrollExtent);
    if (_motion == Duration.zero) {
      _scroll.jumpTo(to);
    } else {
      _scroll.animateTo(
        to,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    }
  }

  double get _page =>
      _scroll.hasClients ? _scroll.position.viewportDimension * 0.85 : 400;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      // The text can be read with the keyboard alone.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _scrollBy(64),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _scrollBy(-64),
        const SingleActivator(LogicalKeyboardKey.pageDown): () =>
            _scrollBy(_page),
        const SingleActivator(LogicalKeyboardKey.pageUp): () =>
            _scrollBy(-_page),
        const SingleActivator(LogicalKeyboardKey.end): () =>
            _scrollBy(double.infinity),
        const SingleActivator(LogicalKeyboardKey.home): () =>
            _scrollBy(double.negativeInfinity),
      },
      child: Focus(
        focusNode: _focus,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= kWideWidth;
            if (!wide) return _narrow(context);
            return widget.readOnly
                ? _document(context, width: constraints.maxWidth)
                : _wide(context, constraints.maxWidth);
          },
        ),
      ),
    );
  }

  /// A phone, or a narrow window: the text, then the controls pinned
  /// below it.
  Widget _narrow(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _document(context, width: 0)),
        if (!widget.readOnly)
          DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: _controls(context, sideBySide: true),
            ),
          ),
      ],
    );
  }

  /// A wide window: a side panel with the summary and the controls, and
  /// the text beside it.
  Widget _wide(BuildContext context, double width) {
    final l10n = context.l10n;
    final panel = (width * 0.3).clamp(340.0, 440.0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: panel,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(right: BorderSide(color: AppColors.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(32, 36, 32, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Logo(size: 56),
                      const SizedBox(height: 18),
                      Semantics(
                        header: true,
                        child: Text(
                          l10n.termsOfUse,
                          style: AppText.screenTitle,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.termsDocVersion(termsVersion, termsChanged),
                        style: AppText.detail,
                      ),
                      const SizedBox(height: 16),
                      _GateNote(changed: widget.changed),
                      const SizedBox(height: 22),
                      const _InShort(background: AppColors.raised),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                child: _controls(context, sideBySide: false),
              ),
            ],
          ),
        ),
        Expanded(child: _document(context, width: width - panel)),
      ],
    );
  }

  /// The scrolling text, with the contents beside it where it is wide
  /// enough. [width] is 0 on a narrow window.
  Widget _document(BuildContext context, {required double width}) {
    final withContents = width >= 1060;
    final narrow = width == 0;
    final text = SelectionArea(
      child: _TermsText(
        keys: _sectionKeys,
        narrow: narrow,
        gate: !widget.readOnly,
        changed: widget.changed,
        accepted: widget.accepted,
      ),
    );
    final scroll = SingleChildScrollView(
      controller: _scroll,
      padding: narrow
          ? const EdgeInsets.fromLTRB(20, 20, 20, 32)
          : const EdgeInsets.fromLTRB(48, 40, 48, 56),
      child: narrow
          ? text
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: text,
              ),
            ),
    );
    if (!withContents) return scroll;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: scroll),
        SizedBox(
          width: 300,
          child: _Contents(current: _current, onTap: _goTo),
        ),
      ],
    );
  }

  /// How far the text has been read, the box to tick, and the two buttons.
  Widget _controls(BuildContext context, {required bool sideBySide}) {
    final l10n = context.l10n;
    final accept = AnimatedOpacity(
      opacity: _ticked ? 1 : 0.45,
      duration: const Duration(milliseconds: 150),
      child: AppButton(
        label: l10n.termsAccept,
        kind: AppButtonKind.primary,
        onTap: _ticked ? widget.onAccept : null,
      ),
    );
    final decline = AppButton(
      label: l10n.termsDecline,
      onTap: widget.onDecline,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReadProgress(read: _read, reachedEnd: _reachedEnd),
        const SizedBox(height: 8),
        _AgreeBox(
          enabled: _reachedEnd,
          ticked: _ticked,
          onChanged: (value) => setState(() => _ticked = value),
        ),
        const SizedBox(height: 10),
        if (sideBySide)
          Row(
            children: [
              Expanded(child: decline),
              const SizedBox(width: 10),
              Expanded(child: accept),
            ],
          )
        else ...[
          accept,
          const SizedBox(height: 10),
          decline,
        ],
      ],
    );
  }
}

/// The terms themselves: title, summary where it is not beside them,
/// introduction, the numbered sections and the closing words.
class _TermsText extends StatelessWidget {
  const _TermsText({
    required this.keys,
    required this.narrow,
    required this.gate,
    required this.changed,
    required this.accepted,
  });

  final List<GlobalKey> keys;
  final bool narrow;
  final bool gate;
  final bool changed;
  final TermsAcceptance? accepted;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sections = termsSections(l10n);
    // On a wide window the gate's side panel carries the summary.
    final summaryHere = narrow || !gate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (narrow && gate) ...[
          const Align(alignment: Alignment.centerLeft, child: _Logo(size: 48)),
          const SizedBox(height: 14),
        ],
        Semantics(
          header: true,
          child: Text(
            l10n.termsDocTitle,
            style: AppText.base.copyWith(
              fontSize: narrow ? 24 : 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.termsDocVersion(termsVersion, termsChanged),
          style: AppText.detail14,
        ),
        if (accepted case final accepted?) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const AppIcon(AppIcons.check, size: 18, color: AppColors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.termsAcceptedOn(accepted.version, accepted.acceptedAt),
                  style: AppText.detail14.copyWith(color: AppColors.green),
                ),
              ),
            ],
          ),
        ],
        if (narrow && gate) ...[
          const SizedBox(height: 14),
          _GateNote(changed: changed),
        ],
        if (summaryHere) ...[
          const SizedBox(height: 18),
          const _InShort(background: AppColors.surface),
        ],
        const SizedBox(height: 22),
        _Body(l10n.termsDocIntro),
        for (final (index, section) in sections.indexed)
          KeyedSubtree(
            key: keys[index],
            child: Padding(
              padding: const EdgeInsets.only(top: 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      '${index + 1}. ${section.title}',
                      style: AppText.base.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _Body(section.body),
                ],
              ),
            ),
          ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Text(
            l10n.termsDocClosing,
            style: AppText.base.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// A block of terms text: paragraphs, and lists whose points start "• ".
class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  static final _style = AppText.base.copyWith(
    fontSize: 15,
    height: 1.55,
    color: AppColors.text,
  );

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final block in text.split('\n\n')) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 12));
      final lines = block.split('\n');
      for (final (index, line) in lines.indexed) {
        if (index > 0) children.add(const SizedBox(height: 6));
        if (line.startsWith('• ')) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 9, right: 12),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(child: Text(line.substring(2), style: _style)),
                ],
              ),
            ),
          );
        } else {
          children.add(Text(line, style: _style));
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// Why the terms are being shown: a first start, or terms that changed.
class _GateNote extends StatelessWidget {
  const _GateNote({required this.changed});

  final bool changed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: AppIcon(
            changed ? AppIcons.warning : AppIcons.info,
            size: 18,
            color: changed ? AppColors.amber : AppColors.accent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            changed ? l10n.termsGateChanged : l10n.termsGateIntro,
            style: AppText.detail14,
          ),
        ),
      ],
    );
  }
}

/// The main points in a few lines, to help reading. It says it is not the
/// terms.
class _InShort extends StatelessWidget {
  const _InShort({required this.background});

  final Color background;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final points = [
      (AppIcons.warning, l10n.termsShortAsIs),
      (AppIcons.antenna, l10n.termsShortLawful),
      (AppIcons.lifebuoy, l10n.termsShortEmergency),
      (AppIcons.info, l10n.termsShortEarly),
      (AppIcons.lock, l10n.termsShortNoServers),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(l10n.termsInShort, style: AppText.strong),
          ),
          const SizedBox(height: 10),
          for (final (icon, text) in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppIcon(icon, size: 18, color: AppColors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      style: AppText.detail14.copyWith(color: AppColors.text),
                    ),
                  ),
                ],
              ),
            ),
          Text(l10n.termsInShortNote, style: AppText.footnote),
        ],
      ),
    );
  }
}

/// The sections, to jump to. The one being read is marked.
class _Contents extends StatelessWidget {
  const _Contents({required this.current, required this.onTap});

  final ValueListenable<int> current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sections = termsSections(l10n);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 40, 24, 24),
      child: ValueListenableBuilder<int>(
        valueListenable: current,
        builder: (context, now, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 8),
              child: Text(l10n.termsContents, style: AppText.sectionLabel),
            ),
            for (final (index, section) in sections.indexed)
              Pressable(
                onTap: () => onTap(index),
                selected: index == now,
                focusRadius: BorderRadius.circular(AppRadius.channelRow),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  constraints: const BoxConstraints(minHeight: 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: index == now
                        ? AppColors.accentSoft
                        : const Color(0x00000000),
                    borderRadius: BorderRadius.circular(AppRadius.channelRow),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 26,
                        child: Text(
                          '${index + 1}',
                          style: AppText.mono(
                            12,
                            color: index == now
                                ? AppColors.accent
                                : AppColors.text3,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          section.title,
                          style: AppText.base.copyWith(
                            fontSize: 14,
                            color: index == now
                                ? AppColors.text
                                : AppColors.text2,
                            fontWeight: index == now
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A thin bar for how far the text has been read, and what is left to do.
class _ReadProgress extends StatelessWidget {
  const _ReadProgress({required this.read, required this.reachedEnd});

  final ValueListenable<double> read;
  final bool reachedEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<double>(
      valueListenable: read,
      builder: (context, done, _) {
        final shown = reachedEnd ? 1.0 : done;
        return Semantics(
          liveRegion: reachedEnd,
          label: reachedEnd ? l10n.termsReachedEnd : l10n.termsReadToEnd,
          value: l10n.termsReadProgress((shown * 100).round()),
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (reachedEnd) ...[
                    const AppIcon(
                      AppIcons.check,
                      size: 16,
                      color: AppColors.green,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      reachedEnd ? l10n.termsReachedEnd : l10n.termsReadToEnd,
                      style: AppText.detail.copyWith(
                        color: reachedEnd ? AppColors.green : AppColors.text2,
                      ),
                    ),
                  ),
                  Text(
                    l10n.termsReadProgress((shown * 100).round()),
                    style: AppText.mono(12, color: AppColors.text3),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 4,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: AppColors.raised),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: shown,
                        child: ColoredBox(
                          color: reachedEnd
                              ? AppColors.green
                              : AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "I have read and agree": a box that can be ticked only once the text
/// has been read to the end.
class _AgreeBox extends StatelessWidget {
  const _AgreeBox({
    required this.enabled,
    required this.ticked,
    required this.onChanged,
  });

  final bool enabled;
  final bool ticked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return MergeSemantics(
      child: Semantics(
        checked: ticked,
        enabled: enabled,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Pressable(
            onTap: enabled ? () => onChanged(!ticked) : null,
            focusRadius: BorderRadius.circular(AppRadius.smallButton),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: ticked
                            ? AppColors.accent
                            : const Color(0x00000000),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: ticked ? AppColors.accent : AppColors.text2,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: ticked
                          ? const AppIcon(
                              AppIcons.check,
                              size: 16,
                              color: AppColors.accentInk,
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.termsAgreeBox,
                        style: AppText.base.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// After Decline: the app stays closed. The terms can be read again, or
/// the app quit.
class _Declined extends StatelessWidget {
  const _Declined({super.key, required this.onReadAgain, required this.onQuit});

  final VoidCallback onReadAgain;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppScreen(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: AppColors.raised,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const AppIcon(
                      AppIcons.lock,
                      size: 32,
                      color: AppColors.text2,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Semantics(
                  header: true,
                  child: Text(
                    l10n.termsDeclinedTitle,
                    textAlign: TextAlign.center,
                    style: AppText.screenTitle,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.termsDeclinedBody,
                  textAlign: TextAlign.center,
                  style: AppText.base.copyWith(color: AppColors.text2),
                ),
                const SizedBox(height: 26),
                AppButton(
                  label: l10n.termsReadAgain,
                  kind: AppButtonKind.primary,
                  onTap: onReadAgain,
                ),
                const SizedBox(height: 10),
                AppButton(label: l10n.termsQuit, onTap: onQuit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The DNet logo on its rounded tile.
class _Logo extends StatelessWidget {
  const _Logo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.3),
        child: Image.asset(
          'assets/brand/logo.png',
          width: size,
          height: size,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
