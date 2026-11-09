import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/place.dart';
import '../data/safe_link.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import 'buttons.dart';
import 'feedback.dart';

/// A place someone sent: its numbers, how far off it may be, and two ways
/// to use it. No map is drawn, because drawing one would mean fetching it
/// from somewhere, and that would tell somebody the place.
class LocationCard extends StatelessWidget {
  const LocationCard({
    super.key,
    required this.place,
    this.background = AppColors.raised,
    this.metaColor = AppColors.text2,
    this.borderRadius,
    this.footer,
  });

  final Place place;
  final Color background;
  final Color metaColor;
  final BorderRadius? borderRadius;

  /// Under the buttons: in a chat, when it was sent and how far it got.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final meta = AppText.base.copyWith(fontSize: 12, color: metaColor);
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: borderRadius ?? BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Semantics(
              label: l10n.locationCardLabel(place.text),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: AppColors.accentSoft,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const AppIcon(
                        AppIcons.location,
                        size: 22,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.locationCard, style: meta),
                          Text(place.text, style: AppText.mono(14)),
                          if (place.accuracy > 0)
                            Text(
                              l10n.locationWithin(place.accuracy),
                              style: meta,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: l10n.copy,
                  height: 40,
                  horizontalPadding: 8,
                  onTap: () => copyPlace(context, place),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: l10n.openInMaps,
                  height: 40,
                  horizontalPadding: 8,
                  onTap: () => openPlaceInMap(context, place),
                ),
              ),
            ],
          ),
          if (footer case final footer?) ...[const SizedBox(height: 4), footer],
        ],
      ),
    );
  }
}

/// Copies a place as its numbers, which any map app takes.
Future<void> copyPlace(BuildContext context, Place place) async {
  final l10n = context.l10n;
  await Clipboard.setData(ClipboardData(text: place.text));
  if (context.mounted) showAppToast(context, l10n.locationCopied);
}

/// Says what opening a map gives away, and opens it only if the user
/// still wants to. On a PC the map is a web page, held to the same rules
/// as any link someone sent: it must go where it says, privately.
Future<void> openPlaceInMap(BuildContext context, Place place) async {
  final l10n = context.l10n;
  final state = AppScope.read(context);
  final web = state.mapsInBrowser;
  if (web) {
    final link = SafeLink.parse(place.webMap);
    if (link == null ||
        link.warnings.isNotEmpty ||
        link.domain != 'www.openstreetmap.org') {
      showAppToast(context, l10n.noMapApp);
      return;
    }
  }
  final sure = await showAppConfirm(
    context,
    title: l10n.openMapWarnTitle,
    body: l10n.openMapWarnBody(web ? 'pc' : 'phone'),
    confirmLabel: l10n.open,
  );
  if (!sure || !context.mounted) return;
  if (!await state.openMap(place) && context.mounted) {
    showAppToast(context, l10n.noMapApp);
  }
}
