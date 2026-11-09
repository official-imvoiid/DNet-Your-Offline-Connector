import 'dart:async';

import 'package:flutter/widgets.dart';

import '../calls/call_engine.dart';
import '../core/device_notices.dart';
import '../l10n/l10n.dart';
import '../widgets/format_help.dart';
import 'app_state.dart';
import 'models.dart';

/// Shows the device's own notifications for what arrives while DNet is not
/// in front of the user: a message, a chat request, a mention in a space, a
/// call that is ringing.
///
/// It watches what the screens would show, not the radio: each time the
/// app's state changes it compares what is there with what was there
/// before. A chat with more unread messages than before is news; one with
/// none left has been read, and its notification goes. So nothing is said
/// twice, and nothing is said for what the user has already seen.
///
/// While the app is in front, nothing is shown: the screens say it. With
/// an app lock on, a notification says neither who it is from nor what was
/// said, since anyone holding the device would see it.
///
/// It also tells the device whether the app goes on in the background
/// once it is put away, as the user chose.
class NoticeWatcher {
  NoticeWatcher(
    this._state,
    this._device,
    this._l10n, {
    this.onOpen,
    bool Function()? inFront,
  }) : _inFrontOverride = inFront;

  final AppState _state;
  final DeviceNotices _device;
  final AppLocalizations _l10n;

  /// Opens what a tapped notification was about.
  final void Function(String key)? onOpen;

  /// Tests say whether the app is in front; on a device the app's
  /// lifecycle does.
  final bool Function()? _inFrontOverride;

  /// The longest message text a notification shows.
  static const mostText = 200;

  Map<String, int> _unread = const {};
  Set<String> _asking = const {};
  Map<String, int> _mentions = const {};
  String? _ringing;
  bool _looked = false;
  bool _on = false;
  bool? _keeping;
  bool _asked = false;
  StreamSubscription<String>? _taps;

  bool get _inFront {
    if (_inFrontOverride case final inFront?) return inFront();
    final now = WidgetsBinding.instance.lifecycleState;
    return now == null || now == AppLifecycleState.resumed;
  }

  void start() {
    _device.words(
      NoticeWords(
        messages: _l10n.noticeChannelMessages,
        calls: _l10n.noticeChannelCalls,
        appName: _l10n.appName,
        open: _l10n.trayOpen,
        quit: _l10n.trayQuit,
        stillRunningTitle: _l10n.trayStillRunningTitle,
        stillRunningText: _l10n.trayStillRunningText,
      ),
    );
    _taps = _device.opened.listen(_open);
    _state.addListener(_look);
    _look();
    unawaited(
      _device.launchKey().then((key) {
        if (key != null) _open(key);
      }),
    );
  }

  void dispose() {
    _state.removeListener(_look);
    unawaited(_taps?.cancel());
  }

  void _open(String key) => onOpen?.call(key);

  void _look() {
    // The first look only learns what is already there.
    final first = !_looked;
    _looked = true;
    final identity = _state.hasIdentity;

    final keep = identity && _state.device(DeviceSetting.background);
    if (keep != _keeping) {
      _keeping = keep;
      _device.keepRunning(keep);
    }

    final on = identity && _state.device(DeviceSetting.notifications);
    if (on && !_asked) {
      _asked = true;
      unawaited(
        _device.allowed().then((allowed) {
          if (!allowed) _device.ask();
        }),
      );
    }

    final chats = _state.chats;
    final unread = {for (final c in chats) c.personId: c.unread};
    final asking = {for (final r in _state.incomingRequests) r.personId};
    final channels = <String, (Space, Channel)>{
      for (final space in _state.spaces)
        for (final channel in space.channels.values.expand((list) => list))
          channel.id: (space, channel),
    };
    final mentions = {
      for (final MapEntry(:key, :value) in channels.entries)
        key: value.$2.mentions,
    };
    final call = _state.calls?.call;
    final ringing =
        call != null && call.phase == CallPhase.incoming && call.showable
        ? call.peer
        : null;

    if (!on) {
      if (_on) _device.cancelAll();
    } else {
      final quiet = first || _inFront;
      // With an app lock, whoever holds the device sees nothing of it.
      final hidden = _state.hasPasscode;
      final withText = !hidden && _state.device(DeviceSetting.notifyText);

      for (final chat in chats) {
        final before = _unread[chat.personId] ?? 0;
        if (chat.unread == 0) {
          if (before > 0) _device.cancel('chat:${chat.personId}');
        } else if (chat.unread > before && !quiet) {
          _device.show(
            Notice(
              key: 'chat:${chat.personId}',
              kind: NoticeKind.message,
              title: hidden ? _l10n.appName : _name(chat.personId),
              text: withText
                  ? _preview(chat)
                  : _l10n.noticeNewMessages(chat.unread),
            ),
          );
        }
      }
      for (final MapEntry(:key, :value) in _unread.entries) {
        if (value > 0 && !unread.containsKey(key)) {
          _device.cancel('chat:$key');
        }
      }

      if (!quiet) {
        for (final id in asking.difference(_asking)) {
          _device.show(
            Notice(
              key: 'request:$id',
              kind: NoticeKind.request,
              title: _l10n.noticeRequestTitle,
              text: hidden
                  ? _l10n.noticeRequestHidden
                  : _l10n.noticeRequestText(_name(id)),
            ),
          );
        }
      }
      for (final id in _asking.difference(asking)) {
        _device.cancel('request:$id');
      }

      for (final MapEntry(key: id, value: count) in mentions.entries) {
        final before = _mentions[id] ?? 0;
        if (count == 0) {
          if (before > 0) _device.cancel('mention:$id');
        } else if (count > before && !quiet) {
          final (space, channel) = channels[id]!;
          _device.show(
            Notice(
              key: 'mention:$id',
              kind: NoticeKind.mention,
              title: hidden ? _l10n.appName : space.name,
              text: hidden
                  ? _l10n.noticeMentionHidden
                  : _l10n.noticeMention(channel.name),
            ),
          );
        }
      }

      // A call is shown however the app was started, unless it is in
      // front, where the call screen is.
      if (ringing != null && ringing != _ringing && !_inFront) {
        _device.show(
          Notice(
            key: 'call',
            kind: NoticeKind.call,
            title: _l10n.noticeCallTitle,
            text: hidden
                ? _l10n.noticeCallHidden
                : _l10n.noticeCallText(_name(ringing)),
          ),
        );
      }
      if (ringing == null && _ringing != null) _device.cancel('call');
    }

    _unread = unread;
    _asking = asking;
    _mentions = mentions;
    _ringing = ringing;
    _on = on;
  }

  String _name(String id) => _state.person(id).name;

  /// What the last message was, in a few words.
  String _preview(ChatSummary chat) {
    final words = switch (chat.previewKind) {
      PreviewKind.text => plainText(chat.previewText),
      PreviewKind.voice => _l10n.voiceMessage,
      PreviewKind.photo => _l10n.sharePhoto,
      PreviewKind.file =>
        chat.previewText.isEmpty ? _l10n.shareFile : chat.previewText,
      PreviewKind.sticker => _l10n.stickerPreview,
      PreviewKind.video => _l10n.shareVideo,
      PreviewKind.location => _l10n.locationCard,
      PreviewKind.poll => _l10n.sharePoll,
      PreviewKind.deleted => '',
    };
    if (words.trim().isEmpty) return _l10n.noticeNewMessages(chat.unread);
    return words.length <= mostText
        ? words
        : '${words.substring(0, mostText).trimRight()}…';
  }
}
