import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/names.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../shell/home_shell.dart';
import '../version.dart';
import '../widgets/buttons.dart';
import '../widgets/pressable.dart';
import '../widgets/scaffold.dart';
import '../widgets/text_box.dart';

/// 01 Welcome, the first screen: what DNet is, and making an identity,
/// which takes nothing but a name, a quick check that a person is here,
/// and a few seconds of work for the stamp.
///
/// On a phone it is one column, as designed. On a wide window it fills
/// the window in two panes: DNet and what it does on the left, making the
/// identity on the right.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final _name = TextEditingController(
    text: AppScope.read(context).suggestName(),
  );
  final _random = Random();

  /// Plays once as the screen first shows: each part rises into place a
  /// little after the one before it.
  late final _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  /// Get started opens only after the quick check is passed. The terms
  /// were accepted before this screen could be shown at all.
  bool _checked = false;

  bool get _ready => _checked;

  /// How far making the key has got, from 0 to 1, once Get started was
  /// pressed. Null before.
  double? _making;

  /// Makes the key and the work that stamps it, showing how far along it
  /// is, and only then the identity. Other devices let a stranger ask to
  /// chat only with that stamp, which is what makes identities cost
  /// something to make in bulk.
  Future<void> _start() async {
    if (_making != null || !_ready) return;
    final state = AppScope.read(context);
    final name = _name.text;
    setState(() => _making = 0);
    await state.prepareIdentity(
      progress: (done) {
        if (mounted) setState(() => _making = done);
      },
    );
    // The user may have left this screen while the key was being made;
    // the work is kept, and the identity is made all the same.
    state.createIdentity(name);
  }

  @override
  void initState() {
    super.initState();
    _name;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entrance.isAnimating || _entrance.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _entrance.value = 1;
    } else {
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final window = MediaQuery.sizeOf(context);
    return AppScreen(
      body: window.width >= kWideWidth
          ? _wide(context, window)
          : _narrow(context, short: window.height < 700),
    );
  }

  /// Fades and lifts [child] into place as the screen opens. [order] says
  /// when, from 0 for the first part.
  Widget _rise(int order, Widget child) =>
      _Rise(animation: _entrance, order: order, child: child);

  /// A phone, or a narrow window: one column, as designed.
  Widget _narrow(BuildContext context, {required bool short}) {
    final l10n = context.l10n;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _columnWidth),
        child: FillScroll(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(24, short ? 24 : 56, 24, 0),
              child: _rise(0, const _Brand(large: false)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 0),
              child: Column(
                children: [
                  for (final (index, point) in _points(context).take(3).indexed)
                    Padding(
                      padding: EdgeInsets.only(top: index == 0 ? 0 : 18),
                      child: _rise(1 + index, point),
                    ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
              child: _rise(4, _form(context, l10n)),
            ),
          ],
        ),
      ),
    );
  }

  /// A wide window: two panes that fill it.
  Widget _wide(BuildContext context, Size window) {
    final l10n = context.l10n;
    final right = (window.width * 0.42).clamp(440.0, 640.0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _BrandPane(
            entrance: _entrance,
            child: _scrollCentred(
              padding: const EdgeInsets.fromLTRB(56, 48, 48, 40),
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _rise(0, const _Brand(large: true)),
                    const SizedBox(height: 40),
                    for (final (index, point) in _points(context).indexed)
                      Padding(
                        padding: EdgeInsets.only(top: index == 0 ? 0 : 22),
                        child: _rise(1 + index, point),
                      ),
                    const SizedBox(height: 40),
                    _rise(
                      5,
                      Text(
                        l10n.welcomeOpenSource(appVersion),
                        style: AppText.footnote,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: right,
          child: FocusTraversalGroup(
            child: _scrollCentred(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _rise(
                  2,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          l10n.welcomeCreateTitle,
                          style: AppText.base.copyWith(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.welcomeCreateBody,
                        style: AppText.base.copyWith(color: AppColors.text2),
                      ),
                      const SizedBox(height: 26),
                      _form(context, l10n),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Centres [child] in the space there is, and scrolls it when the window
  /// is too short to show it all.
  Widget _scrollCentred({
    required EdgeInsets padding,
    required Alignment alignment,
    required Widget child,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: max(0, constraints.maxHeight - padding.vertical),
          ),
          child: Align(alignment: alignment, child: child),
        ),
      ),
    );
  }

  List<Widget> _points(BuildContext context) {
    final l10n = context.l10n;
    return [
      _Point(
        icon: AppIcons.nearby,
        title: l10n.welcomePoint1Title,
        body: l10n.welcomePoint1Body(context.deviceKind),
      ),
      _Point(
        icon: AppIcons.lock,
        title: l10n.welcomePoint2Title,
        body: l10n.welcomePoint2Body,
      ),
      _Point(
        icon: AppIcons.file,
        title: l10n.welcomePoint3Title,
        body: l10n.welcomePoint3Body(context.deviceKind),
      ),
      _Point(
        icon: AppIcons.people,
        title: l10n.welcomePoint4Title,
        body: l10n.welcomePoint4Body,
      ),
    ];
  }

  /// The name, the quick check, Get started and the note under it.
  Widget _form(BuildContext context, AppLocalizations l10n) {
    final still = MediaQuery.disableAnimationsOf(context);
    final quick = Duration(milliseconds: still ? 0 : 220);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Text(
            l10n.yourName,
            style: AppText.base.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AppTextBox(
                controller: _name,
                label: l10n.yourName,
                textInputAction: TextInputAction.done,
                // Enter goes on: to Get started once the check is done,
                // to the check before.
                onSubmitted: (_) =>
                    _ready ? _start() : FocusScope.of(context).nextFocus(),
              ),
            ),
            const SizedBox(width: 8),
            AppButton(
              label: l10n.random,
              onTap: _making != null
                  ? null
                  : () => _name.text = Names.random(_random.nextInt),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _PersonCheck(onPassed: () => setState(() => _checked = true)),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          layoutBuilder: _keepWidth,
          duration: quick,
          child: switch (_making) {
            final done? => _MakingKey(
              key: const ValueKey('making'),
              done: done,
            ),
            null => AnimatedOpacity(
              key: const ValueKey('start'),
              opacity: _ready ? 1 : 0.45,
              duration: quick,
              child: AppButton(
                label: l10n.getStarted,
                kind: AppButtonKind.primary,
                onTap: _ready ? _start : null,
              ),
            ),
          },
        ),
        // A switcher, not a size animation: while it changes, it is as tall
        // as it says it is, so the column around it never overflows.
        AnimatedSwitcher(
          layoutBuilder: _keepWidth,
          duration: quick,
          child: _ready
              ? const SizedBox(key: ValueKey('ready'), width: double.infinity)
              : Padding(
                  key: const ValueKey('locked'),
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.getStartedLocked,
                    textAlign: TextAlign.center,
                    style: AppText.footnote,
                  ),
                ),
        ),
        const SizedBox(height: 14),
        Text(
          l10n.welcomeFootnote(context.deviceKind),
          textAlign: TextAlign.center,
          style: AppText.footnote,
        ),
      ],
    );
  }

  /// The widest the start screen's column grows to on a narrow window.
  static const _columnWidth = 460.0;
}

/// Lifts and fades a part of the screen in as it first shows.
class _Rise extends StatelessWidget {
  const _Rise({
    required this.animation,
    required this.order,
    required this.child,
  });

  final Animation<double> animation;
  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (order * 0.09).clamp(0.0, 0.6);
    final interval = Interval(start, start + 0.4, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = interval.transform(animation.value);
        if (t == 1) return child!;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - t)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// The logo, the name and the one-line promise.
class _Brand extends StatelessWidget {
  const _Brand({required this.large});

  /// The bigger size of a wide window's left pane.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final logo = large ? 76.0 : 64.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.hero),
            child: Image.asset(
              'assets/brand/logo.png',
              width: logo,
              height: logo,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
        SizedBox(height: large ? 20 : 14),
        Semantics(
          header: true,
          child: Text(
            l10n.appName,
            style: AppText.base.copyWith(
              fontSize: large ? 56 : 40,
              fontWeight: FontWeight.w800,
              letterSpacing: large ? -1.2 : -0.8,
              height: 1.05,
            ),
          ),
        ),
        SizedBox(height: large ? 12 : 14),
        Text(
          l10n.welcomeTagline,
          style: AppText.base.copyWith(
            fontSize: large ? 21 : 18,
            color: AppColors.text2,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

/// The left pane of a wide window: the surface colour, a soft glow and a
/// drawing of devices linked into a mesh that draws itself in once, behind
/// what DNet is.
class _BrandPane extends StatelessWidget {
  const _BrandPane({required this.entrance, required this.child});

  final Animation<double> entrance;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.line)),
        gradient: RadialGradient(
          center: Alignment(-0.9, -0.9),
          radius: 1.3,
          colors: [Color(0xFF243246), AppColors.surface],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            child: CustomPaint(
              painter: _MeshPainter(
                CurvedAnimation(parent: entrance, curve: Curves.easeInOut),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Devices, drawn as rings, and the links between them, faint, toward the
/// right and the bottom so they stay behind the words. The links draw
/// themselves in as [progress] goes from 0 to 1.
class _MeshPainter extends CustomPainter {
  _MeshPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  /// Where each device sits, as a share of the pane's width and height.
  static const _nodes = [
    Offset(0.62, 0.16),
    Offset(0.80, 0.10),
    Offset(0.93, 0.28),
    Offset(0.74, 0.36),
    Offset(0.88, 0.52),
    Offset(0.66, 0.60),
    Offset(0.82, 0.74),
    Offset(0.95, 0.86),
    Offset(0.70, 0.90),
    Offset(0.56, 0.80),
  ];

  static const _links = [
    (0, 1), (1, 2), (0, 3), (1, 3), (2, 4), (3, 4), (3, 5), (4, 6), //
    (5, 6), (6, 7), (6, 8), (8, 9), (5, 9),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t == 0 || size.isEmpty) return;
    Offset at(int i) =>
        Offset(_nodes[i].dx * size.width, _nodes[i].dy * size.height);
    final line = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.16)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (final (index, (a, b)) in _links.indexed) {
      // Each link starts a little after the one before it.
      final start = index / _links.length * 0.6;
      final share = ((t - start) / 0.4).clamp(0.0, 1.0);
      if (share == 0) continue;
      canvas.drawLine(at(a), Offset.lerp(at(a), at(b), share)!, line);
    }
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final (index, _) in _nodes.indexed) {
      final grow = ((t - index * 0.05) / 0.5).clamp(0.0, 1.0);
      if (grow == 0) continue;
      final big = index % 3 == 0;
      ring.color = (index.isEven ? AppColors.green : const Color(0xFFD7E35A))
          .withValues(alpha: 0.32 * grow);
      canvas.drawCircle(at(index), (big ? 11 : 7) * grow, ring);
    }
  }

  @override
  bool shouldRepaint(_MeshPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final AppIconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: AppColors.raised,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: AppIcon(icon, size: 22, color: AppColors.accent),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.rowTitle),
              Text(body, style: AppText.detail14),
            ],
          ),
        ),
      ],
    );
  }
}

/// The key being made: a few seconds, with a bar that fills.
class _MakingKey extends StatelessWidget {
  const _MakingKey({super.key, required this.done});

  /// From 0 to 1.
  final double done;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final percent = (done.clamp(0, 1) * 100).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.raised,
        borderRadius: BorderRadius.circular(AppRadius.largeButton),
      ),
      child: Semantics(
        liveRegion: true,
        label: '${l10n.makingKeyTitle}. ${l10n.makingKeyProgress(percent)}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l10n.makingKeyTitle, style: AppText.strong),
                ),
                Text(
                  l10n.makingKeyProgress(percent),
                  style: AppText.mono(13, color: AppColors.text2),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(l10n.makingKeyBody(context.deviceKind), style: AppText.detail),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: AppColors.surface),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: done.clamp(0, 1).toDouble(),
                      child: const ColoredBox(color: AppColors.accent),
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

/// A finished step, shown with a tick.
class _Done extends StatelessWidget {
  const _Done({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.raised,
        borderRadius: BorderRadius.circular(AppRadius.largeButton),
      ),
      child: Row(
        children: [
          const AppIcon(AppIcons.check, size: 20, color: AppColors.green),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppText.detail14)),
        ],
      ),
    );
  }
}

/// A small check, done on the device with no internet. The usual way is
/// to tap the picture that is named; anyone who cannot see the pictures
/// types three numbers given in words instead. Each picture is named for
/// screen readers, so the pictures work without sight too.
///
/// It keeps out careless scripts and accidental starts, and after a few
/// wrong answers it makes them wait. It cannot stop a determined program,
/// and nothing is sent anywhere. What makes identities costly to make in
/// bulk is the stamp worked out when Get started is pressed.
class _PersonCheck extends StatefulWidget {
  const _PersonCheck({required this.onPassed});

  final VoidCallback onPassed;

  @override
  State<_PersonCheck> createState() => _PersonCheckState();
}

class _PersonCheckState extends State<_PersonCheck> {
  static const _pictures = [
    AppIcons.lock,
    AppIcons.camera,
    AppIcons.bookmark,
    AppIcons.chat,
  ];

  /// Wrong answers in a row before the check makes them wait.
  static const _triesBeforeWait = 3;
  static const _wait = Duration(seconds: 10);

  final _random = Random.secure();
  final _typed = TextEditingController();
  late List<int> _order;
  late int _asked;
  late List<int> _digits;
  bool _typing = false;
  bool _wrong = false;
  bool _passed = false;
  int _misses = 0;
  Timer? _waiting;

  @override
  void initState() {
    super.initState();
    _shuffle();
  }

  @override
  void dispose() {
    _waiting?.cancel();
    _typed.dispose();
    super.dispose();
  }

  void _shuffle() {
    _order = [0, 1, 2, 3]..shuffle(_random);
    _asked = _random.nextInt(_pictures.length);
    _digits = [for (var i = 0; i < 3; i++) _random.nextInt(10)];
    _typed.clear();
  }

  void _answer({required bool right}) {
    if (_waiting != null) return;
    setState(() {
      if (right) {
        _passed = true;
        widget.onPassed();
        return;
      }
      _wrong = true;
      _misses++;
      _shuffle();
      if (_misses >= _triesBeforeWait) {
        _waiting = Timer(_wait, () {
          if (!mounted) return;
          setState(() {
            _waiting = null;
            _misses = 0;
          });
        });
      }
    });
  }

  void _checkTyped() {
    final answer = _typed.text.replaceAll(RegExp(r'\D'), '');
    _answer(right: answer == _digits.join());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      layoutBuilder: _keepWidth,
      duration: Duration(milliseconds: still ? 0 : 220),
      child: _passed
          ? _Done(key: const ValueKey('passed'), text: l10n.personCheckDone)
          : _check(context, l10n),
    );
  }

  Widget _check(BuildContext context, AppLocalizations l10n) {
    final names = [
      l10n.checkPadlock,
      l10n.checkCamera,
      l10n.checkBookmark,
      l10n.checkSpeechBubble,
    ];
    final numberWords = l10n.numberWords.split(',');
    final waiting = _waiting != null;
    return Container(
      key: const ValueKey('check'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.raised,
        borderRadius: BorderRadius.circular(AppRadius.largeButton),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _typing
                ? l10n.personCheckTypePrompt(
                    [for (final d in _digits) numberWords[d]].join(', '),
                  )
                : l10n.personCheckPrompt(names[_asked]),
            style: AppText.detail14,
          ),
          if (waiting || _wrong)
            Semantics(
              liveRegion: true,
              child: Text(
                waiting ? l10n.personCheckWait : l10n.personCheckWrong,
                style: AppText.detail14.copyWith(color: AppColors.red),
              ),
            ),
          const SizedBox(height: 10),
          if (_typing)
            Row(
              children: [
                Expanded(
                  child: AppTextBox(
                    controller: _typed,
                    label: l10n.personCheckTypeLabel,
                    height: 46,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _checkTyped(),
                  ),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: l10n.personCheckTypeCheck,
                  height: 46,
                  onTap: waiting ? null : _checkTyped,
                ),
              ],
            )
          else
            Opacity(
              opacity: waiting ? 0.45 : 1,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final picture in _order)
                    Semantics(
                      button: true,
                      label: names[picture],
                      excludeSemantics: true,
                      child: Pressable(
                        onTap: () => _answer(right: picture == _asked),
                        focusRadius: BorderRadius.circular(24),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: AppIcon(
                            _pictures[picture],
                            size: 24,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Pressable(
            onTap: () => setState(() {
              _typing = !_typing;
              _wrong = false;
              _shuffle();
            }),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Center(
                child: Text(
                  _typing
                      ? l10n.personCheckPicturesInstead
                      : l10n.personCheckOtherWay,
                  style: AppText.detail.copyWith(color: AppColors.accent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lays out what an [AnimatedSwitcher] switches between at the full width
/// it is given, as the buttons and cards are drawn, rather than shrunk to
/// fit their words.
Widget _keepWidth(Widget? current, List<Widget> previous) => Stack(
  fit: StackFit.passthrough,
  alignment: Alignment.topCenter,
  children: [...previous, ?current],
);
