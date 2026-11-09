import 'package:flutter/material.dart' show showLicensePage;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/terms_record.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../legal/licences.dart';
import '../routes.dart';
import '../version.dart';
import '../widgets/badges.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/link_text.dart' show showLinkCheck;
import '../widgets/pressable.dart';
import '../widgets/scaffold.dart';

/// About DNet: what it is for and what it aims to do, how it works in
/// brief, where it honestly stands, where its source code is and where to
/// report a bug, and its terms and licences.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  /// From this width the page is laid out in two columns.
  static const _twoColumns = 760.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppScreen(
      header: AppTopBar(title: l10n.aboutApp, divider: true),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= _twoColumns;
          final first = [
            const _Hero(),
            const _Words(kind: _WordsKind.purpose),
            const _Words(kind: _WordsKind.aim),
            const _HowItWorks(),
          ];
          final second = [
            const _Status(),
            const _Links(),
            const _Legal(),
            const _Footer(),
          ];
          Widget column(List<Widget> cards, {int from = 0}) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, card) in cards.indexed) ...[
                if (index > 0) const SizedBox(height: 14),
                _Rise(order: from + index, child: card),
              ],
            ],
          );
          return SingleChildScrollView(
            padding: wide
                ? const EdgeInsets.fromLTRB(28, 24, 28, 32)
                : const EdgeInsets.fromLTRB(16, 14, 16, 28),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: column(first)),
                      const SizedBox(width: 20),
                      Expanded(flex: 5, child: column(second, from: 2)),
                    ],
                  )
                : column([...first, ...second]),
          );
        },
      ),
    );
  }
}

/// Slides and fades a card into place, a little after the one before it.
class _Rise extends StatelessWidget {
  const _Rise({required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final delay = (order * 0.08).clamp(0.0, 0.5);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Interval(delay, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// The logo, the name, the tagline and the version.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppCard(
      padding: const EdgeInsets.all(20),
      radius: AppRadius.hero,
      child: Row(
        children: [
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.hero),
              child: Image.asset(
                'assets/brand/logo.png',
                width: 76,
                height: 76,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l10n.appName,
                    style: AppText.base.copyWith(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      height: 1.05,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.aboutTagline,
                  style: AppText.base.copyWith(
                    fontSize: 16,
                    color: AppColors.text2,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Pressable(
                      // Copied as a bug report wants it.
                      onTap: () async {
                        await Clipboard.setData(
                          ClipboardData(text: 'DNet $appVersion+$appBuild'),
                        );
                        if (context.mounted) {
                          showAppToast(context, l10n.aboutVersionCopied);
                        }
                      },
                      semanticLabel:
                          '${l10n.aboutVersion(appVersion)}. '
                          '${l10n.aboutCopyVersion}',
                      focusRadius: BorderRadius.circular(AppRadius.chip),
                      child: AppChip(
                        l10n.aboutVersion(appVersion),
                        tone: ChipTone.accent,
                      ),
                    ),
                    AppChip(l10n.aboutLicence),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _WordsKind { purpose, aim }

/// A card of plain words under a heading.
class _Words extends StatelessWidget {
  const _Words({required this.kind});

  final _WordsKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (title, body) = switch (kind) {
      _WordsKind.purpose => (l10n.aboutPurposeTitle, l10n.aboutPurposeBody),
      _WordsKind.aim => (l10n.aboutAimTitle, l10n.aboutAimBody),
    };
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading(title),
          const SizedBox(height: 8),
          Text(body, style: _body),
        ],
      ),
    );
  }
}

final _body = AppText.base.copyWith(height: 1.5, color: AppColors.text2);

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Semantics(header: true, child: Text(text, style: AppText.rowTitle));
}

/// The five ideas DNet is built on, each with its icon.
class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final points = [
      (AppIcons.nearby, l10n.aboutHowNearbyTitle, l10n.aboutHowNearbyBody),
      (AppIcons.link, l10n.aboutHowMeshTitle, l10n.aboutHowMeshBody),
      (AppIcons.lock, l10n.aboutHowSealedTitle, l10n.aboutHowSealedBody),
      (AppIcons.hash, l10n.aboutHowSpacesTitle, l10n.aboutHowSpacesBody),
      (AppIcons.antenna, l10n.aboutHowRadioTitle, l10n.aboutHowRadioBody),
    ];
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading(l10n.aboutHowTitle),
          const SizedBox(height: 12),
          for (final (icon, title, body) in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AppColors.raised,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: AppIcon(icon, size: 20, color: AppColors.accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppText.strong),
                        const SizedBox(height: 2),
                        Text(body, style: AppText.detail14),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Where the app honestly stands: what has and has not been checked.
class _Status extends StatelessWidget {
  const _Status();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.amberSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: AppIcon(AppIcons.warning, size: 22, color: AppColors.amber),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l10n.aboutStatusTitle,
                    style: AppText.rowTitle.copyWith(color: AppColors.amber),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.aboutStatusBody,
                  style: AppText.base.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The source code and the place to report bugs. Both open in the user's
/// own browser, after the link check every link in the app goes through.
class _Links extends StatelessWidget {
  const _Links();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Group(
      title: l10n.aboutLinksTitle,
      rows: [
        _Row(
          icon: AppIcons.globe,
          title: l10n.aboutGithub,
          detail: l10n.aboutGithubDetail,
          onTap: () => showLinkCheck(context, sourceCodeUrl),
        ),
        _Row(
          icon: AppIcons.chat,
          title: l10n.aboutIssues,
          detail: l10n.aboutIssuesDetail,
          onTap: () => showLinkCheck(context, issuesUrl),
        ),
      ],
    );
  }
}

/// The terms, DNet's own licence and the licences of what it is built
/// with.
class _Legal extends StatelessWidget {
  const _Legal();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final accepted = AcceptedTerms.maybeOf(context);
    return _Group(
      title: l10n.aboutLegalTitle,
      rows: [
        _Row(
          icon: AppIcons.file,
          title: l10n.termsOfUse,
          detail: accepted == null
              ? l10n.aboutTermsDetail
              : l10n.termsAcceptedOn(accepted.version, accepted.acceptedAt),
          onTap: () => Go.terms(context),
        ),
        _Row(
          icon: AppIcons.bookmark,
          title: l10n.aboutLicence,
          detail: l10n.aboutLicenceDetail,
          onTap: () => _showMitLicence(context),
        ),
        _Row(
          icon: AppIcons.info,
          title: l10n.aboutOpenSource,
          detail: l10n.aboutOpenSourceDetail,
          onTap: () {
            registerAppLicences();
            showLicensePage(
              context: context,
              applicationName: l10n.appName,
              applicationVersion: appVersion,
              applicationIcon: Padding(
                padding: const EdgeInsets.all(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: Image.asset(
                    'assets/brand/logo.png',
                    width: 56,
                    height: 56,
                  ),
                ),
              ),
              applicationLegalese: '© 2026 The DNet authors. MIT License.',
            );
          },
        ),
      ],
    );
  }
}

/// DNet's MIT License, word for word.
Future<void> _showMitLicence(BuildContext context) {
  return showAppSheet<void>(
    context,
    builder: (context) {
      final l10n = context.l10n;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Semantics(
              header: true,
              child: Text(
                l10n.aboutLicence,
                style: AppText.base.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(AppRadius.smallButton),
            ),
            child: Text(
              mitLicenceText.trim(),
              style: AppText.mono(12, color: AppColors.text2),
            ),
          ),
          const SizedBox(height: 14),
          AppButton(
            label: l10n.close,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      );
    },
  );
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        context.l10n.aboutFooter,
        textAlign: TextAlign.center,
        style: AppText.footnote,
      ),
    );
  }
}

class _Row {
  const _Row({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final AppIconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
}

/// A heading over a card of rows, each opening something.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.rows});

  final String title;
  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Semantics(
            header: true,
            child: Text(title, style: AppText.sectionLabel),
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (index, row) in rows.indexed)
                Pressable(
                  onTap: row.onTap,
                  focusRadius: BorderRadius.circular(AppRadius.card),
                  child: DividedRow(
                    minHeight: 64,
                    divider: index < rows.length - 1,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        AppIcon(row.icon, size: 20, color: AppColors.text2),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(row.title, style: AppText.strong),
                              const SizedBox(height: 2),
                              Text(row.detail, style: AppText.detail),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        const AppIcon(
                          AppIcons.chevronRight,
                          size: 16,
                          color: AppColors.text3,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
