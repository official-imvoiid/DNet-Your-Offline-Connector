import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/app_state.dart';
import 'design/tokens.dart';
import 'l10n/l10n.dart';
import 'screens/call_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/welcome_screen.dart';
import 'shell/home_shell.dart';
import 'widgets/tab_bar.dart';

/// The widest a single column of content is drawn, where a screen wants
/// one in the middle of a big window, such as the first screen. Screens
/// inside the app fill the window instead.
const double kMaxContentWidth = 520;

class DNetApp extends StatefulWidget {
  const DNetApp({
    super.key,
    required this.state,
    this.home = const RootGate(),
    this.initialTab = AppTab.chats,
  });

  final AppState state;

  /// The first screen. Tests replace it to open one screen directly.
  final Widget home;
  final AppTab initialTab;

  @override
  State<DNetApp> createState() => _DNetAppState();
}

class _DNetAppState extends State<DNetApp> with WidgetsBindingObserver {
  late final _tab = ValueNotifier(widget.initialTab);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inFront(true);
  }

  /// While the app is in front of the user, contacts who are allowed to
  /// see that are told, and told again before they would stop believing
  /// it.
  Timer? _stillHere;

  void _inFront(bool active) {
    _stillHere?.cancel();
    _stillHere = active
        ? Timer.periodic(
            const Duration(minutes: 1),
            (_) => widget.state.onScreen(true),
          )
        : null;
    widget.state.onScreen(active);
  }

  @override
  void dispose() {
    _stillHere?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _tab.dispose();
    super.dispose();
  }

  /// When the app went out of sight, if it is.
  DateTime? _leftAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _leftAt ??= DateTime.now();
      _inFront(false);
    } else if (state == AppLifecycleState.resumed) {
      _inFront(true);
      final away = _leftAt == null
          ? Duration.zero
          : DateTime.now().difference(_leftAt!);
      _leftAt = null;
      // As long as the user chose on the Privacy screen.
      if (away >= widget.state.lockAfter) widget.state.lockNow();
      // The user may have been away switching Bluetooth on.
      widget.state.recheckRadio();
      widget.state.tidyUp();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: widget.state,
      child: TabSelection(
        notifier: _tab,
        child: MaterialApp(
          onGenerateTitle: (context) => context.l10n.appName,
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: appTheme,
          home: widget.home,
          navigatorKey: appNavigator,
          builder: (context, child) => _Frame(child: child!),
        ),
      ),
    );
  }
}

/// What every route sits inside: system bar colours and the base text
/// style.
class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The lock is drawn here, over every screen, so nothing can be left
    // showing above it. What is underneath is not built at all while
    // locked, so it cannot be read by a screen reader either.
    final locked = AppScope.of(context).locked;
    final content = DefaultTextStyle(
      style: AppText.base,
      child: Stack(
        // Fills the space whatever is in it. A hidden app has no size of
        // its own, and the lock must not shrink to match.
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: locked,
            // A call is drawn over the app, and under the lock.
            child: ExcludeSemantics(
              excluding: locked,
              child: CallFrame(child: child),
            ),
          ),
          // The lock sits above the app's own navigator, so it brings one
          // of its own: its passcode box and its "wipe everything?" question
          // both need somewhere to stand.
          if (locked)
            Positioned.fill(
              child: HeroControllerScope.none(
                child: Navigator(
                  onGenerateRoute: (_) => PageRouteBuilder<void>(
                    pageBuilder: (_, _, _) => const LockScreen(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0x00000000),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.bg,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      // The app fills the window, whatever its size: a wide one is split
      // into panes (see [HomeShell]) and a narrow one is one screen edge
      // to edge. Limits belong inside screens, such as a bubble's width.
      child: ColoredBox(
        color: AppColors.bg,
        child: Material(type: MaterialType.transparency, child: content),
      ),
    );
  }
}

/// The app's Material theme. The terms shown before the app opens use it
/// too, so the two look the same.
final ThemeData appTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  fontFamily: AppFonts.sans,
  scaffoldBackgroundColor: AppColors.bg,
  canvasColor: AppColors.bg,
  splashFactory: NoSplash.splashFactory,
  colorScheme: const ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: AppColors.accentInk,
    secondary: AppColors.accent,
    onSecondary: AppColors.accentInk,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    error: AppColors.red,
    onError: AppColors.redInk,
  ),
  textSelectionTheme: const TextSelectionThemeData(
    cursorColor: AppColors.accent,
    selectionColor: AppColors.ownBubble,
    selectionHandleColor: AppColors.accent,
  ),
);

/// Shows Welcome until an identity exists, and the four tabs afterwards.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    if (AppScope.of(context).hasIdentity) return const HomeShell();
    // Welcome fills the window: two panes on a wide one, one column on a
    // narrow one. It keeps its own widths inside.
    return const WelcomeScreen();
  }
}
