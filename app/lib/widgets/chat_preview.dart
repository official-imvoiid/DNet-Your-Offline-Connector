import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../data/models.dart';
import '../data/place.dart';
import '../data/video_probe.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import 'format_help.dart';

/// The line under a person's name in the Chats list: what the last
/// message was. Words for a message, and for a video, a place or a poll a
/// small picture and the facts that matter: how long, where, how the
/// votes stand.
///
/// Everything here is drawn from what is already on the device. Nothing
/// is fetched: a place is drawn as a pin on a grid, never a map tile.
class ChatPreview extends StatelessWidget {
  const ChatPreview(this.chat, {super.key});

  final ChatSummary chat;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return switch (chat.previewKind) {
      PreviewKind.text => _line(plainText(chat.previewText)),
      PreviewKind.voice => _line(l10n.voiceMessagePreview(chat.previewText)),
      PreviewKind.photo => _line(l10n.photo),
      PreviewKind.file => _line(l10n.filePreview(chat.previewText)),
      PreviewKind.sticker => _line(l10n.stickerPreview),
      PreviewKind.video => _VideoLine(chat.video ?? const VideoPreview()),
      PreviewKind.location => _LocationLine(chat.place),
      PreviewKind.poll => _PollLines(chat.poll),
      PreviewKind.deleted => _line(l10n.messageDeleted),
    };
  }

  static Widget _line(String text) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: AppText.detail14,
  );
}

/// The small picture beside a video or a place, 36 points square.
const _thumb = 36.0;

/// A video: its first frame where the device can show one, and how long
/// it runs. Says plainly when it is not here yet, is still being read, or
/// cannot be played on this device.
class _VideoLine extends StatelessWidget {
  const _VideoLine(this.video);

  final VideoPreview video;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final words = !video.here
        ? l10n.videoPreviewNotHere
        : video.reading
        ? l10n.videoPreviewReading
        : video.failed
        ? l10n.videoPreviewCannotRead
        : l10n.videoPreviewLength(formatSeconds(video.seconds ?? 0));
    return Row(
      children: [
        VideoThumb(video: video),
        const SizedBox(width: 8),
        Expanded(child: ChatPreview._line(words)),
      ],
    );
  }
}

/// How many list rows may hold a player open for a first frame. Each one
/// holds a decoder, and a long list must not open one per row.
abstract final class _ThumbCovers {
  static const most = 4;
  static final _open = <_VideoThumbState>[];

  static bool take(_VideoThumbState thumb) {
    if (_open.contains(thumb)) return true;
    if (_open.length >= most) return false;
    _open.add(thumb);
    return true;
  }

  static void give(_VideoThumbState thumb) => _open.remove(thumb);
}

/// The first frame of a video, small, with a film mark over it. Four
/// states: still opening (a dim box), open (the frame), could not open
/// (the film mark alone), and not here yet (the same, dimmer).
class VideoThumb extends StatefulWidget {
  const VideoThumb({super.key, required this.video, this.size = _thumb});

  final VideoPreview video;
  final double size;

  @override
  State<VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<VideoThumb> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _openIfCan();
  }

  @override
  void didUpdateWidget(VideoThumb old) {
    super.didUpdateWidget(old);
    if (old.video.path != widget.video.path) {
      _close();
      _failed = false;
      _openIfCan();
    }
  }

  void _openIfCan() {
    if (!widget.video.here || widget.video.failed) return;
    if (_ThumbCovers.take(this)) unawaited(_open());
  }

  Future<void> _open() async {
    final controller = VideoPlayerController.file(
      File(widget.video.path),
      videoPlayerOptions: videoOptions,
    );
    _controller = controller;
    try {
      await controller.initialize().timeout(const Duration(seconds: 8));
    } on Object {
      if (_controller == controller) _controller = null;
      _ThumbCovers.give(this);
      unawaited(controller.dispose().then((_) {}, onError: (_) {}));
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (!mounted || _controller != controller) {
      await controller.dispose();
      return;
    }
    setState(() {});
  }

  void _close() {
    final controller = _controller;
    _controller = null;
    _ThumbCovers.give(this);
    if (controller != null) unawaited(controller.dispose());
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final size = widget.size;
    final absent = !widget.video.here;
    final broken = widget.video.failed || _failed;
    final opening = !absent && !broken && !ready;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: absent ? AppColors.surface : AppColors.raised),
            if (ready)
              FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: math.max(controller.value.size.width, 1),
                  height: math.max(controller.value.size.height, 1),
                  child: VideoPlayer(controller),
                ),
              ),
            Center(
              child: AppIcon(
                AppIcons.video,
                size: size * 0.5,
                color: ready
                    ? AppColors.white
                    : opening
                    ? AppColors.text3
                    : absent
                    ? AppColors.text3
                    : AppColors.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A place: a pin on a grid beside its numbers, and how far off it may
/// be. The grid stands for a map without being one: drawing a real map
/// would mean fetching it, and that would tell somebody the place.
class _LocationLine extends StatelessWidget {
  const _LocationLine(this.place);

  final Place? place;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final place = this.place;
    return Row(
      children: [
        LocationSnippet(place: place),
        const SizedBox(width: 8),
        Expanded(
          child: ChatPreview._line(
            place == null
                ? l10n.locationPreviewGone
                : l10n.locationPreview(place.text),
          ),
        ),
        if (place != null && place.accuracy > 0) ...[
          const SizedBox(width: 6),
          Text(l10n.locationAccuracy(place.accuracy), style: AppText.timestamp),
        ],
      ],
    );
  }
}

/// A small square: a grid, with a pin where the place is. The pin sits
/// where the place's numbers put it within its own degree, so two
/// places nearby look alike and two far apart do not. With no place, the
/// grid alone, dim.
class LocationSnippet extends StatelessWidget {
  const LocationSnippet({super.key, required this.place, this.size = _thumb});

  final Place? place;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CustomPaint(
        size: Size.square(size),
        painter: _SnippetPainter(place),
      ),
    );
  }
}

class _SnippetPainter extends CustomPainter {
  const _SnippetPainter(this.place);

  final Place? place;

  @override
  void paint(Canvas canvas, Size size) {
    final place = this.place;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = place == null ? AppColors.surface : AppColors.raised,
    );
    final grid = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final at = size.width * i / 4;
      canvas.drawLine(Offset(at, 0), Offset(at, size.height), grid);
      canvas.drawLine(Offset(0, at), Offset(size.width, at), grid);
    }
    if (place == null) return;
    // Where within its degree the place falls: east across, north up.
    final x = (place.lon - place.lon.floor()) * size.width;
    final y = (1 - (place.lat - place.lat.floor())) * size.height;
    final tip = Offset(x.clamp(5, size.width - 5), y.clamp(9, size.height - 2));
    final head = tip - const Offset(0, 7);
    final pin = Paint()..color = AppColors.accent;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(head.dx - 4, head.dy)
        ..lineTo(head.dx + 4, head.dy)
        ..close(),
      pin,
    );
    canvas.drawCircle(head, 4, pin);
    canvas.drawCircle(head, 1.5, Paint()..color = AppColors.accentInk);
  }

  @override
  bool shouldRepaint(_SnippetPainter old) => old.place != place;
}

/// A poll: its question, then the choices with the most votes and how
/// many each has. With no votes yet, it says so.
class _PollLines extends StatelessWidget {
  const _PollLines(this.poll);

  final Poll? poll;

  /// How many choices are shown. A poll can have more.
  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final poll = this.poll;
    if (poll == null) return ChatPreview._line(l10n.pollPreview(''));
    final top = [...poll.options.indexed]
      ..sort((a, b) {
        final byVotes = b.$2.votes.compareTo(a.$2.votes);
        return byVotes != 0 ? byVotes : a.$1.compareTo(b.$1);
      });
    final standing = poll.totalVotes == 0
        ? l10n.pollNoVotesYet
        : [
            for (final (_, option) in top.take(_shown))
              l10n.pollOptionVotes(option.label, option.votes),
          ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ChatPreview._line(l10n.pollPreview(plainText(poll.question))),
        Text(
          standing,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.timestamp,
        ),
      ],
    );
  }
}
