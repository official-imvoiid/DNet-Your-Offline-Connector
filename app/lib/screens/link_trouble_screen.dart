import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/scaffold.dart';

/// 16 Link trouble. Shown when links fail together while people are still
/// in range. It reports what the app sees and what it is doing about it.
/// It never claims to know the cause.
class LinkTroubleScreen extends StatelessWidget {
  const LinkTroubleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final report = state.linkTrouble;
    if (report == null) {
      return AppScreen(
        header: AppTopBar(title: l10n.linkTroubleTitle),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.linksAreWorking,
              textAlign: TextAlign.center,
              style: AppText.base.copyWith(color: AppColors.text2),
            ),
          ),
        ),
      );
    }
    String name(String id) => state.person(id).name;
    String names(List<String> ids) => ids.length == 1
        ? name(ids.single)
        : l10n.twoNames(name(ids.first), name(ids.last));
    final towards = name(report.signalPersonId);
    final wifiNearby = report.wifiNearbyWorking;
    final restart = state.canRestartRadios;
    final actions = [
      // The Wi-Fi Direct group was made again on the other band, because
      // the one it was on did not carry.
      if (report.movedIds.isNotEmpty)
        l10n.movedToFiveGhz(names(report.movedIds)),
      if (report.movedToLowIds.isNotEmpty)
        l10n.movedToTwoGhz(names(report.movedToLowIds)),
      if (report.heldCount > 0)
        report.heldForIds.length == 1
            ? l10n.holdingMessagesFor(
                report.heldCount,
                name(report.heldForIds.single),
              )
            : l10n.holdingMessages(report.heldCount, names(report.heldForIds)),
    ];

    return AppScreen(
      header: AppTopBar(title: l10n.linkTroubleTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          AppCard(
            color: AppColors.amberSoft,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: AppIcon(
                    AppIcons.warning,
                    size: 24,
                    color: AppColors.amber,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.strongInterference,
                        style: AppText.rowTitle.copyWith(
                          color: AppColors.amber,
                        ),
                      ),
                      Text(
                        l10n.strongInterferenceDetail,
                        style: AppText.base.copyWith(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                _RadioRow(
                  name: l10n.bluetooth,
                  working: report.bluetoothWorking,
                ),
                if (wifiNearby != null)
                  _RadioRow(
                    name: l10n.wifiNearby,
                    working: wifiNearby,
                    divider: false,
                  )
                else ...[
                  _RadioRow(name: l10n.wifi24, working: report.wifi24Working),
                  _RadioRow(
                    name: l10n.wifi5,
                    working: report.wifi5Working,
                    divider: false,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                _SignalMeter(level: report.signalLevel),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(switch (report.trend) {
                        SignalTrend.better => l10n.signalGettingBetter(towards),
                        SignalTrend.worse => l10n.signalGettingWorse(towards),
                        SignalTrend.steady => l10n.signalHolding(towards),
                      }, style: AppText.strong),
                      Text(switch (report.trend) {
                        SignalTrend.better => l10n.keepWalkingToward(towards),
                        SignalTrend.worse => l10n.walkBackToward(towards),
                        SignalTrend.steady => l10n.tryWalkingToward(towards),
                      }, style: AppText.detail),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.whatAppIsDoing, style: AppText.sectionLabel),
                  for (final action in actions) ...[
                    const SizedBox(height: 8),
                    _Action(text: action),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
      footer: !state.works(Extra.linkTroubleActions) && !restart
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Handing messages over by camera code is not built.
                  if (state.works(Extra.linkTroubleActions)) ...[
                    AppButton(
                      label: l10n.passByCameraCode,
                      icon: AppIcons.qr,
                      kind: AppButtonKind.primary,
                      onTap: () => showNotBuiltYet(context),
                    ),
                    const SizedBox(height: 12),
                  ],
                  AppButton(
                    label: l10n.tryAllRadiosAgain,
                    onTap: restart
                        ? () {
                            state.restartRadios();
                            showAppToast(context, l10n.radiosRestarted);
                          }
                        : () => showNotBuiltYet(context),
                  ),
                ],
              ),
            ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  const _RadioRow({
    required this.name,
    required this.working,
    this.divider = true,
  });

  final String name;
  final bool working;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DividedRow(
      minHeight: divider ? 49 : 48,
      divider: divider,
      child: Row(
        children: [
          Expanded(child: Text(name)),
          const SizedBox(width: 12),
          Text(
            working ? l10n.working : l10n.noSignal,
            style: AppText.base.copyWith(
              color: working ? AppColors.green : AppColors.red,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Five bars of rising height. Lit bars are amber.
class _SignalMeter extends StatelessWidget {
  const _SignalMeter({required this.level});

  final int level;

  static const _heights = <double>[12, 19, 26, 33, 40];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.signalStrength(level),
      child: SizedBox(
        height: 40,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (index, height) in _heights.indexed) ...[
              if (index > 0) const SizedBox(width: 4),
              Container(
                width: 10,
                height: height,
                decoration: BoxDecoration(
                  color: index < level ? AppColors.amber : AppColors.raised,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: AppIcon(AppIcons.check, size: 16, color: AppColors.green),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: AppText.base.copyWith(fontSize: 14))),
      ],
    );
  }
}
