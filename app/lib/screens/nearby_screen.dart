import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/mesh.dart';
import '../data/models.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/extra_icons.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../radio/radio.dart';
import '../routes.dart';
import '../widgets/avatar.dart';
import '../widgets/badges.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/mesh_map.dart';
import '../widgets/pressable.dart';
import '../widgets/scaffold.dart';
import 'scan_screen.dart';

/// 14 Nearby. The app's core screen: who is in range, whom they reach,
/// and how a message to each person would go right now.
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  /// The map the user chose. Until they choose, the one that shows more.
  MeshRadio? _chosen;
  String? _picked;
  final _map = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final people = state.nearbyPeople;
    final mesh = state.mesh;
    final radio =
        _chosen ??
        (mesh.routes(MeshRadio.wifi).length >
                mesh.routes(MeshRadio.bluetooth).length
            ? MeshRadio.wifi
            : MeshRadio.bluetooth);

    return AppScreen(
      safeBottom: false,
      header: AppTabHeader(
        title: l10n.tabNearby,
        actions: [
          // The design's code button scans. Where this device cannot, it
          // shows the user's own code, on the New chat screen, instead.
          AppIconButton(
            icon: AppIcons.qr,
            label: state.works(Extra.codeScanning) || state.canScan
                ? l10n.scanACode
                : l10n.showMyCode,
            onTap: () => state.works(Extra.codeScanning)
                ? showNotBuiltYet(context)
                : state.canScan
                ? scanAndAct(context)
                : Go.newChat(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          if (state.radioState != RadioState.on) ...[
            _RadioNotice(state: state.radioState),
            const SizedBox(height: 14),
          ],
          MeshPanel(
            key: _map,
            mesh: mesh,
            radio: radio,
            picked: _picked,
            onRadio: (radio) => setState(() => _chosen = radio),
            onPick: (id) => setState(() => _picked = id),
            onOpen: () => Go.meshMap(context, radio: radio, picked: _picked),
          ),
          const SizedBox(height: 14),
          if (people.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l10n.nearbyEmpty,
                textAlign: TextAlign.center,
                style: AppText.base.copyWith(color: AppColors.text2),
              ),
            ),
          for (final person in people)
            _PersonRow(
              person: person,
              route: mesh.routeTo(person.id),
              picked: person.id == _picked,
              onTap: () => _show(person.id, mesh, radio),
            ),
        ],
      ),
    );
  }

  /// Picks someone from the list and brings the map to them, on the radio
  /// their way starts on if the one shown does not reach them.
  void _show(String id, Mesh mesh, MeshRadio shown) {
    setState(() {
      _picked = id;
      if (!mesh.routes(shown).containsKey(id)) {
        _chosen = mesh.routeTo(id)?.hops.first.radio ?? _chosen;
      }
    });
    final map = _map.currentContext;
    if (map != null) {
      Scrollable.ensureVisible(
        map,
        duration: const Duration(milliseconds: 250),
      );
    }
  }
}

/// The mesh, full size: on a wide window it fills the pane beside the
/// list.
class MeshMapScreen extends StatefulWidget {
  const MeshMapScreen({
    super.key,
    this.radio = MeshRadio.bluetooth,
    this.picked,
  });

  final MeshRadio radio;
  final String? picked;

  @override
  State<MeshMapScreen> createState() => _MeshMapScreenState();
}

class _MeshMapScreenState extends State<MeshMapScreen> {
  late MeshRadio _radio = widget.radio;
  late String? _picked = widget.picked;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return AppScreen(
      header: AppTopBar(title: context.l10n.tabNearby),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          MeshPanel(
            mesh: state.mesh,
            radio: _radio,
            picked: _picked,
            mapMax: 640,
            onRadio: (radio) => setState(() => _radio = radio),
            onPick: (id) => setState(() => _picked = id),
          ),
        ],
      ),
    );
  }
}

/// The switch between the two maps, the map itself with its counts, and
/// whoever is picked on it.
class MeshPanel extends StatelessWidget {
  const MeshPanel({
    super.key,
    required this.mesh,
    required this.radio,
    required this.picked,
    required this.onRadio,
    required this.onPick,
    this.onOpen,
    this.mapMax = 380,
  });

  final Mesh mesh;
  final MeshRadio radio;
  final String? picked;
  final ValueChanged<MeshRadio> onRadio;
  final ValueChanged<String?> onPick;

  /// Opens the map full size. Null where it already is.
  final VoidCallback? onOpen;

  /// The tallest the map grows.
  final double mapMax;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final routes = mesh.routes(radio);
    final inRange = routes.values.where((route) => route.direct).length;
    final through = routes.length - inRange;
    final shown = routes.containsKey(picked) ? picked : null;
    final radioName = radio == MeshRadio.bluetooth
        ? l10n.bluetooth
        : l10n.meshWifi;

    MeshFace faceOf(String id) {
      final name = state.meshName(id);
      return (
        name: name,
        initial: name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        tone: state.isBlocked(id)
            ? AvatarTone.grey
            : state.findPerson(id)?.tone ?? toneForKey(id),
      );
    }

    final count = AppText.strong.copyWith(fontSize: 15);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RadioSwitch(
          radio: radio,
          bluetooth: mesh.routes(MeshRadio.bluetooth).length,
          wifi: mesh.routes(MeshRadio.wifi).length,
          onChanged: onRadio,
        ),
        const SizedBox(height: 10),
        AppCard(
          radius: AppRadius.hero,
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: l10n.meshInRange(inRange)),
                          if (through > 0) ...[
                            const TextSpan(text: '  ·  '),
                            TextSpan(text: l10n.meshThroughOthers(through)),
                          ],
                        ],
                      ),
                      style: count,
                    ),
                  ),
                  if (onOpen != null)
                    AppIconButton(
                      icon: ExtraIcons.expand,
                      label: l10n.meshOpenMap,
                      iconSize: 20,
                      color: AppColors.text2,
                      onTap: onOpen,
                    )
                  else
                    const SizedBox(height: kMinTouchTarget),
                ],
              ),
              LayoutBuilder(
                builder: (context, constraints) => SizedBox(
                  height: math.min(constraints.maxWidth, mapMax),
                  child: MeshMap(
                    mesh: mesh,
                    radio: radio,
                    faceOf: faceOf,
                    selected: shown,
                    onSelect: onPick,
                    label: l10n.meshMapLabel(radioName, inRange, through),
                  ),
                ),
              ),
              if (routes.isEmpty)
                Text(
                  l10n.meshNobodyOn(radioName),
                  textAlign: TextAlign.center,
                  style: AppText.base.copyWith(color: AppColors.text2),
                ),
              if (shown != null) ...[
                const SizedBox(height: 6),
                _Picked(
                  id: shown,
                  route: routes[shown]!,
                  onClose: () => onPick(null),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Bluetooth or Wi-Fi, with how many devices each map shows.
class _RadioSwitch extends StatelessWidget {
  const _RadioSwitch({
    required this.radio,
    required this.bluetooth,
    required this.wifi,
    required this.onChanged,
  });

  final MeshRadio radio;
  final int bluetooth;
  final int wifi;
  final ValueChanged<MeshRadio> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final radius = BorderRadius.circular(AppRadius.smallButton);
    Widget segment(MeshRadio which, AppIconData icon, String label, int n) {
      final on = which == radio;
      return Expanded(
        child: Pressable(
          onTap: () => onChanged(which),
          selected: on,
          focusRadius: radius,
          child: Container(
            constraints: const BoxConstraints(minHeight: kMinTouchTarget),
            decoration: BoxDecoration(
              color: on ? AppColors.raised : null,
              borderRadius: radius,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(
                  icon,
                  size: 18,
                  color: on ? AppColors.accent : AppColors.text2,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.base.copyWith(
                      fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                      color: on ? AppColors.text : AppColors.text2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$n',
                  style: AppText.base.copyWith(
                    fontWeight: FontWeight.w700,
                    color: on ? AppColors.accent : AppColors.text3,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.largeButton),
      ),
      child: Row(
        children: [
          segment(
            MeshRadio.bluetooth,
            AppIcons.bluetooth,
            l10n.bluetooth,
            bluetooth,
          ),
          const SizedBox(width: 4),
          segment(MeshRadio.wifi, AppIcons.wifi, l10n.meshWifi, wifi),
        ],
      ),
    );
  }
}

/// Whoever is picked on the map: who, how the last step reaches them,
/// the way there, and a way into a chat.
class _Picked extends StatelessWidget {
  const _Picked({required this.id, required this.route, required this.onClose});

  final String id;
  final MeshRoute route;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final person = state.findPerson(id);
    final name = state.meshName(id);
    final last = route.hops.last;
    final radio = last.radio == MeshRadio.wifi ? l10n.meshWifi : l10n.bluetooth;
    final signal = _signalWords(l10n, last.near);
    final way = route.direct
        ? l10n.meshDirect
        : '${l10n.meshHops(route.hops.length)} '
              '${l10n.meshThroughPath(route.through.map(state.meshName).join(' › '))}';
    final action = person == null
        ? null
        : _actionFor(context, person, meshed: true);

    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
        decoration: BoxDecoration(
          color: AppColors.raised,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            Avatar(
              tone: state.isBlocked(id)
                  ? AvatarTone.grey
                  : person?.tone ?? toneForKey(id),
              photo: person?.photo,
              label: name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              size: 40,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.rowTitle,
                        ),
                      ),
                      if (person?.verified ?? false) ...[
                        const SizedBox(width: 6),
                        const VerifiedBadge(),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      AppIcon(
                        last.radio == MeshRadio.wifi
                            ? AppIcons.wifi
                            : AppIcons.bluetooth,
                        size: 13,
                        color: AppColors.text2,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          signal == null ? radio : '$radio · $signal',
                          style: AppText.detail,
                        ),
                      ),
                    ],
                  ),
                  Text(way, style: AppText.detail),
                ],
              ),
            ),
            if (action != null) ...[const SizedBox(width: 8), action],
            AppIconButton(
              icon: AppIcons.close,
              label: l10n.close,
              iconSize: 18,
              color: AppColors.text2,
              onTap: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

String? _signalWords(AppLocalizations l10n, Nearness? near) => switch (near) {
  Nearness.veryClose => l10n.signalStrong,
  Nearness.near => l10n.signalFair,
  Nearness.far => l10n.signalWeak,
  null => null,
};

/// Chat for a contact who can be reached, in range or through the mesh;
/// Request, or Requested, for someone in range who is not one yet.
/// Nothing for anyone else.
Widget? _actionFor(BuildContext context, Person person, {bool meshed = false}) {
  final l10n = context.l10n;
  final state = AppScope.of(context);
  if (!person.link.inRange && !(meshed && person.isContact)) return null;
  if (person.isContact) {
    // Only an accepted contact gets a way straight into a chat.
    return AppButton(
      label: l10n.chat,
      height: 44,
      horizontalPadding: 16,
      onTap: () => Go.directMessage(context, person.id),
    );
  }
  if (state.hasOutgoingRequest(person.id)) {
    return AppButton(
      label: l10n.requested,
      height: 44,
      horizontalPadding: 14,
      onTap: null,
    );
  }
  return AppButton(
    label: l10n.request,
    kind: AppButtonKind.primary,
    height: 44,
    horizontalPadding: 14,
    onTap: () => state.sendRequest(person.id),
  );
}

/// Shown when the radio is not running: why not, in plain words, and the
/// one thing the user can do about it. Every action opens a question or a
/// settings page of the device's own. The app changes nothing by itself.
class _RadioNotice extends StatelessWidget {
  const _RadioNotice({required this.state});

  final RadioState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final app = AppScope.read(context);
    final (String title, String body, String? action) = switch (state) {
      RadioState.bluetoothOff => (
        l10n.radioBluetoothOffTitle,
        l10n.radioBluetoothOffBody,
        l10n.radioBluetoothOffAction,
      ),
      RadioState.noPermission => (
        l10n.radioNoPermissionTitle,
        l10n.radioNoPermissionBody,
        l10n.radioNoPermissionAction,
      ),
      RadioState.locationOff => (
        l10n.radioLocationOffTitle,
        l10n.radioLocationOffBody,
        l10n.radioLocationOffAction,
      ),
      RadioState.unsupported => (
        l10n.radioUnsupportedTitle,
        l10n.radioUnsupportedBody,
        null,
      ),
      RadioState.off || RadioState.on => (
        l10n.radioSwitchedOffTitle,
        l10n.radioSwitchedOffBody,
        l10n.radioSwitchedOffAction,
      ),
    };
    return AppCard(
      color: AppColors.amberSoft,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: AppIcon(
                  AppIcons.bluetooth,
                  size: 22,
                  color: AppColors.amber,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        title,
                        style: AppText.rowTitle.copyWith(
                          color: AppColors.amber,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(body, style: AppText.base),
                  ],
                ),
              ),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            AppButton(
              label: action,
              kind: AppButtonKind.primary,
              height: 46,
              onTap: () => state == RadioState.off
                  ? Go.network(context)
                  : app.allowRadio(),
            ),
          ],
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.route,
    required this.picked,
    required this.onTap,
  });

  final Person person;

  /// How a message to them would go right now, where the mesh knows.
  final MeshRoute? route;
  final bool picked;

  /// Shows them on the map.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final link = person.link;
    final route = this.route;
    final (AppIconData? icon, String label, Color color) = switch (link.kind) {
      LinkKind.wifi => (AppIcons.wifi, l10n.linkWifiFast, AppColors.accent),
      LinkKind.bluetooth => (
        AppIcons.bluetooth,
        l10n.linkBluetoothChatOnly,
        AppColors.text2,
      ),
      LinkKind.radio => (
        AppIcons.nearby,
        l10n.linkRadioChatOnly,
        AppColors.text2,
      ),
      // The whole way, where the mesh knows it; else the device it came
      // through. A contact not heard from lately may still be reached.
      LinkKind.relayed ||
      LinkKind.outOfRange when route != null && !route.direct => (
        AppIcons.nearby,
        l10n.reachedThroughHops(
          route.hops.length,
          route.through.map(state.meshName).join(' › '),
        ),
        AppColors.text2,
      ),
      LinkKind.relayed => (
        AppIcons.nearby,
        l10n.reachedThroughHops(link.hops, state.person(link.viaId!).name),
        AppColors.text2,
      ),
      LinkKind.outOfRange => (null, l10n.outOfRange, AppColors.text2),
    };
    final signal = link.kind == LinkKind.wifi || link.kind == LinkKind.bluetooth
        ? state.nearness(person.id)
        : null;
    final reached = link.inRange || (route != null && person.isContact);
    final action = _actionFor(context, person, meshed: route != null);

    return Opacity(
      opacity: reached ? 1 : 0.55,
      child: Pressable(
        onTap: reached ? onTap : null,
        selected: picked,
        focusRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: picked ? AppColors.selected : null,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            children: [
              Avatar(
                tone: person.tone,
                label: person.initial,
                size: 44,
                photo: person.photo,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            person.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.rowTitle,
                          ),
                        ),
                        if (person.verified) ...[
                          const SizedBox(width: 6),
                          const VerifiedBadge(),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        if (icon != null) ...[
                          AppIcon(icon, size: 13, color: color),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            label,
                            style: AppText.detail.copyWith(color: color),
                          ),
                        ),
                        if (signal != null) ...[
                          const SizedBox(width: 8),
                          _SignalBars(near: signal),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (action != null) ...[const SizedBox(width: 12), action],
            ],
          ),
        ),
      ),
    );
  }
}

/// Three bars: how strongly someone in range is heard.
class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.near});

  final Nearness near;

  @override
  Widget build(BuildContext context) {
    final lit = switch (near) {
      Nearness.veryClose => 3,
      Nearness.near => 2,
      Nearness.far => 1,
    };
    return Semantics(
      label: _signalWords(context.l10n, near),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var bar = 1; bar <= 3; bar++) ...[
            if (bar > 1) const SizedBox(width: 2),
            Container(
              width: 3,
              height: 3.0 + bar * 3,
              decoration: BoxDecoration(
                color: bar <= lit ? AppColors.green : AppColors.switchOff,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
