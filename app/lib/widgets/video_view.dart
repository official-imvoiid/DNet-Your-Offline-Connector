import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../data/models.dart';
import '../data/video_probe.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/extra_icons.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import 'buttons.dart';
import 'pressable.dart';
import 'scaffold.dart';

/// Only a few videos in a chat hold a player open to show their first
/// frame, since each holds a decoder. The rest show a plain cover until
/// they are played.
abstract final class _Covers {
  static const most = 3;
  static final _open = <_VideoViewState>[];

  static bool take(_VideoViewState view) {
    if (_open.contains(view)) return true;
    if (_open.length >= most) return false;
    _open.add(view);
    return true;
  }

  /// Makes room for [view], which is about to play, by closing the
  /// oldest cover that is not playing.
  static void force(_VideoViewState view) {
    if (take(view)) return;
    final oldest = _open.where((v) => !v._playing).firstOrNull;
    oldest?._close();
    _open.add(view);
  }

  static void give(_VideoViewState view) => _open.remove(view);
}

/// A video in a chat or channel: its first frame where it can be shown,
/// how long it runs, and a button to play it here or full screen. Where
/// this device cannot play it, it says so instead of showing a player
/// that does nothing.
class VideoView extends StatefulWidget {
  const VideoView({
    super.key,
    required this.path,
    required this.name,
    this.seconds = 0,
    this.width = 240,
  });

  final String path;
  final String name;

  /// How long it runs, if known before it is opened.
  final int seconds;
  final double width;

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  VideoPlayerController? _controller;
  bool _failed = false;
  late final AppLifecycleListener _life;

  bool get _playing => _controller?.value.isPlaying ?? false;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onHide: () => _controller?.pause());
    if (_Covers.take(this)) _open();
  }

  @override
  void didUpdateWidget(VideoView old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _close();
      _failed = false;
      if (_Covers.take(this)) _open();
    }
  }

  Future<void> _open({bool play = false}) async {
    final controller = VideoPlayerController.file(
      File(widget.path),
      videoPlayerOptions: videoOptions,
    );
    _controller = controller;
    try {
      await controller.initialize();
    } on Object {
      if (_controller == controller) _controller = null;
      _Covers.give(this);
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (!mounted || _controller != controller) {
      await controller.dispose();
      return;
    }
    controller.addListener(_changed);
    setState(() {});
    if (play) await controller.play();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Lets go of the player, keeping the cover. [redraw] is false while
  /// the view itself is going.
  void _close({bool redraw = true}) {
    final controller = _controller;
    _controller = null;
    _Covers.give(this);
    if (controller != null && controller.value.isInitialized) {
      controller.removeListener(_changed);
      unawaited(controller.dispose());
    }
    if (redraw && mounted) setState(() {});
  }

  Future<void> _toggle() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      _Covers.force(this);
      await _open(play: true);
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      if (controller.value.isCompleted) await controller.seekTo(Duration.zero);
      await controller.play();
    }
  }

  Future<void> _fullScreen() async {
    final at = _controller?.value.position ?? Duration.zero;
    await _controller?.pause();
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) =>
            VideoScreen(path: widget.path, name: widget.name, startAt: at),
      ),
    );
  }

  @override
  void dispose() {
    _life.dispose();
    _close(redraw: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final radius = BorderRadius.circular(AppRadius.smallButton);
    if (_failed) {
      return Container(
        width: widget.width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: radius,
        ),
        child: Row(
          children: [
            const AppIcon(AppIcons.video, size: 22, color: AppColors.text2),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.videoCannotPlay(context.deviceKind),
                style: AppText.detail,
              ),
            ),
          ],
        ),
      );
    }
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final aspect = ready && controller.value.aspectRatio > 0
        ? controller.value.aspectRatio.clamp(0.75, 1.9)
        : 1.5;
    final height = widget.width / aspect;
    final length = ready ? controller.value.duration.inSeconds : widget.seconds;
    final playing = ready && controller.value.isPlaying;
    final shownTime =
        playing || (ready && controller.value.position > Duration.zero)
        ? formatSeconds(controller.value.position.inSeconds)
        : length > 0
        ? formatSeconds(length)
        : null;
    return Semantics(
      label: [
        l10n.videoNamed(widget.name),
        if (length > 0) l10n.videoLength(formatSeconds(length)),
      ].join('. '),
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: widget.width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Color(0xFF000000)),
              if (ready)
                FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
                  ),
                ),
              // Pressing anywhere plays and pauses it.
              Pressable(
                onTap: _toggle,
                semanticLabel: playing ? l10n.pauseVideo : l10n.playVideo,
                focusRadius: radius,
                child: Center(
                  child: Opacity(
                    opacity: playing ? 0 : 1,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.bg.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const AppIcon(
                        AppIcons.play,
                        size: 26,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ),
              ),
              if (shownTime != null)
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.bg.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AppIcon(
                            AppIcons.video,
                            size: 14,
                            color: AppColors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            shownTime,
                            style: AppText.timestamp.copyWith(
                              color: AppColors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: 2,
                top: 2,
                child: AppIconButton(
                  icon: ExtraIcons.expand,
                  label: l10n.videoFullScreen,
                  iconSize: 18,
                  color: AppColors.white,
                  onTap: _fullScreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A video opened to fill the screen, with play, pause and a bar to move
/// through it.
class VideoScreen extends StatefulWidget {
  const VideoScreen({
    super.key,
    required this.path,
    required this.name,
    this.startAt = Duration.zero,
  });

  final String path;
  final String name;
  final Duration startAt;

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late final VideoPlayerController _controller;
  late final AppLifecycleListener _life;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(
      onHide: () => _ready ? _controller.pause() : null,
    );
    _controller = VideoPlayerController.file(
      File(widget.path),
      videoPlayerOptions: videoOptions,
    );
    _start();
  }

  Future<void> _start() async {
    try {
      await _controller.initialize();
    } on Object {
      if (mounted) setState(() => _failed = true);
      return;
    }
    _controller.addListener(_changed);
    if (widget.startAt > Duration.zero) {
      await _controller.seekTo(widget.startAt);
    }
    if (!mounted) return;
    setState(() => _ready = true);
    await _controller.play();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    if (_controller.value.isPlaying) {
      await _controller.pause();
    } else {
      if (_controller.value.isCompleted) {
        await _controller.seekTo(Duration.zero);
      }
      await _controller.play();
    }
  }

  @override
  void dispose() {
    _life.dispose();
    // A player that never started has nothing to stop.
    if (_ready) {
      _controller.removeListener(_changed);
      unawaited(_controller.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final value = _controller.value;
    final playing = _ready && value.isPlaying;
    final length = value.duration;
    return AppScreen(
      header: AppTopBar(title: widget.name),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ColoredBox(
              color: const Color(0xFF000000),
              child: Center(
                child: _failed
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l10n.videoCannotPlay(context.deviceKind),
                          textAlign: TextAlign.center,
                          style: AppText.base.copyWith(color: AppColors.text2),
                        ),
                      )
                    : _ready
                    ? GestureDetector(
                        onTap: _toggle,
                        child: AspectRatio(
                          aspectRatio: value.aspectRatio > 0
                              ? value.aspectRatio
                              : 16 / 9,
                          child: VideoPlayer(_controller),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
          if (!_failed)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
              child: Row(
                children: [
                  AppIconButton(
                    icon: playing ? AppIcons.pause : AppIcons.play,
                    label: playing ? l10n.pauseVideo : l10n.playVideo,
                    round: true,
                    color: AppColors.accentInk,
                    background: AppColors.accent,
                    onTap: _ready ? _toggle : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Scrubber(
                      position: value.position,
                      length: length,
                      onSeek: _ready ? _controller.seekTo : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${formatSeconds(value.position.inSeconds)} / '
                    '${formatSeconds(length.inSeconds)}',
                    style: AppText.detail,
                    semanticsLabel: l10n.videoPosition(
                      formatSeconds(value.position.inSeconds),
                      formatSeconds(length.inSeconds),
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

/// How far through a video it is. Pressed or dragged, it moves there.
class _Scrubber extends StatelessWidget {
  const _Scrubber({
    required this.position,
    required this.length,
    required this.onSeek,
  });

  final Duration position;
  final Duration length;
  final ValueChanged<Duration>? onSeek;

  @override
  Widget build(BuildContext context) {
    final whole = length.inMilliseconds;
    final done = whole == 0
        ? 0.0
        : (position.inMilliseconds / whole).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, box) {
        void seekAt(double x) {
          if (whole == 0) return;
          final part = (x / box.maxWidth).clamp(0.0, 1.0);
          onSeek?.call(Duration(milliseconds: (whole * part).round()));
        }

        return Semantics(
          slider: true,
          value: '${(done * 100).round()}%',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => seekAt(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
            child: SizedBox(
              height: kMinTouchTarget,
              child: Center(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.raised,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: done,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
