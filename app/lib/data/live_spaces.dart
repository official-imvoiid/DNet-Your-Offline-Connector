import 'dart:async';
import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../core/core_bridge.dart';
import '../design/tokens.dart';
import '../radio/link_pump.dart';
import 'live_directory.dart' show LiveDirectory;
import 'image_bounds.dart';
import 'models.dart';
import 'names.dart';
import 'place.dart';
import 'safe_name.dart';
import 'spaces.dart';
import 'stickers.dart';

/// The real spaces: kept, sealed and checked by the Rust core, and passed
/// between members' devices whenever two of them are in range.
///
/// Like the directory of people, this holds no keys and decides nothing.
/// Who may post where, and whose invite is welcome, is the core's business.
class LiveSpaces extends SpaceBook {
  LiveSpaces(this._bridge, this._pump, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _pump.onEvents(_onEvents);
  }

  final CoreBridge _bridge;
  final LinkPump _pump;
  final DateTime Function() _clock;

  /// What the core last said about every space. Null means ask again.
  Map<String, Object?>? _lists;

  /// What has been said in each channel, by channel id, as last read.
  final Map<String, List<Map<String, Object?>>> _said = {};

  /// What is pinned in each channel that has been read.
  final Map<String, Map<String, Object?>> _pins = {};

  /// What has been said under each post that has been looked at.
  final Map<String, List<Map<String, Object?>>> _under = {};

  /// Names learned from spaces, by key. People here need not be contacts.
  final Map<String, String> _names = {};

  String? _selectedId;

  /// The channel last opened in each space. Remembered until the app closes.
  final Map<String, String> _open = {};

  /// When the user last told each channel they were writing in it.
  final Map<String, int> _toldTyping = {};

  /// When each member last said they were writing, by channel and key.
  final Map<(String, String), int> _typing = {};

  bool _within(int? then, Duration time) =>
      then != null &&
      _clock().millisecondsSinceEpoch - then < time.inMilliseconds;

  void _onEvents(List<Map<String, Object?>> events) {
    var typing = false;
    for (final event in events) {
      switch (event) {
        case {
          'kind': 'space_typing',
          'channel': final String channel,
          'from': final String from,
        }:
          _typing[(channel, from)] = _clock().millisecondsSinceEpoch;
          typing = true;
        // Someone gone out of range is not writing anywhere the user can
        // see.
        case {'kind': 'peer_gone', 'key': final String key}:
          _typing.removeWhere((at, _) => at.$2 == key);
      }
    }
    // Someone coming or going changes who is nearby in each space.
    const ours = {'space', 'peer', 'peer_gone', 'room', 'room_in'};
    if (!events.any((event) => ours.contains(event['kind']))) {
      if (typing) notifyListeners();
      return;
    }
    _forget();
    notifyListeners();
  }

  void _forget() {
    _lists = null;
    _rooms = null;
    _said.clear();
    _pins.clear();
    _under.clear();
  }

  @override
  void refresh() {
    _forget();
    _names.clear();
    notifyListeners();
  }

  @override
  void reset() {
    _forget();
    _names.clear();
    _open.clear();
    _typing.clear();
    _toldTyping.clear();
    _icons.clear();
    _selectedId = null;
  }

  /// Asks the core for something. Null if it refused.
  Object? _ask(Map<String, Object?> request) {
    try {
      return _bridge.call(request);
    } on CoreException {
      return null;
    }
  }

  /// Asks the core to change something, sends on whatever that produces
  /// for members in range, and shows the result. Null if the core refused.
  Map<String, Object?>? _do(Map<String, Object?> request) {
    final Object? reply;
    try {
      reply = _bridge.call(request);
    } on CoreException {
      return null;
    }
    _pump.sendDeliveries(reply);
    _forget();
    notifyListeners();
    return reply is Map<String, Object?> ? reply : const {};
  }

  List<Map<String, Object?>> _list(String name) {
    final lists = _lists ??= switch (_ask({'op': 'spaces'})) {
      final Map<String, Object?> lists => lists,
      _ => const {},
    };
    return ((lists[name] as List?) ?? const []).cast<Map<String, Object?>>();
  }

  Space _space(Map<String, Object?> view) {
    final id = view['id']! as String;
    final name = view['name']! as String;
    final kind = view['kind'] as String?;
    final channels = <ChannelGroup, List<Channel>>{};
    for (final c
        in ((view['channels'] as List?) ?? const [])
            .cast<Map<String, Object?>>()) {
      final group = switch (c['group']) {
        'info' => ChannelGroup.info,
        'voice' => ChannelGroup.voice,
        _ => ChannelGroup.text,
      };
      channels
          .putIfAbsent(group, () => [])
          .add(
            Channel(
              id: c['id']! as String,
              name: c['name']! as String,
              kind: switch (c['kind']) {
                'announcements' => ChannelKind.announcements,
                'voice' => ChannelKind.voice,
                _ => ChannelKind.text,
              },
              unread: c['unread'] as int? ?? 0,
              mentions: c['mentions'] as int? ?? 0,
              disappearSeconds: c['disappear'] as int? ?? 0,
              maxLength: c['max_len'] as int? ?? 0,
              writerRoles: [
                for (final role in (c['writers'] as List?) ?? const [])
                  role as String,
              ],
              canWrite: c['can_write'] as bool? ?? true,
              slowSeconds: c['slow'] as int? ?? 0,
              noLinks: c['no_links'] as bool? ?? false,
              talkerIds: [
                for (final p in _people(id, c['id']! as String))
                  p['key']! as String,
              ],
              mutedIds: [
                for (final p in _people(id, c['id']! as String))
                  if (p['muted'] == true) p['key']! as String,
              ],
              speakingId: c['kind'] == 'voice'
                  ? _speakingIn(id, c['id']! as String)
                  : null,
            ),
          );
    }
    return Space(
      id: id,
      name: name,
      initials: _initials(name),
      tone: toneForKey(id),
      isPublic: kind != 'private',
      isBroadcast: kind == 'channel',
      memberCount: view['members'] as int? ?? 0,
      nearbyCount: view['nearby'] as int? ?? 0,
      description: view['description'] as String? ?? '',
      channels: channels,
      openChannelId: _open[id],
      mine: view['mine'] as bool? ?? false,
      ready: view['ready'] as bool? ?? true,
      role: _role(view['role']),
      myName: view['my_name'] as String?,
      bannedWords: [
        for (final word in (view['banned'] as List?) ?? const [])
          word as String,
      ],
      wordFilterOn: view['word_filter'] as bool? ?? true,
      roleDefs: [
        for (final role
            in ((view['roles'] as List?) ?? const [])
                .cast<Map<String, Object?>>())
          SpaceRoleDef(
            id: role['id']! as String,
            name: role['name']! as String,
            may: {
              for (final power in (role['may'] as List?) ?? const [])
                ?RolePower.fromWire(power),
            },
          ),
      ],
      powers: {
        for (final power in (view['powers'] as List?) ?? const [])
          ?RolePower.fromWire(power),
      },
      welcome: view['welcome'] as String? ?? '',
      rules: view['rules'] as String? ?? '',
      icon: _icon(id, view['icon']),
    );
  }

  /// Each space's icon as last read: its hex and its bytes. The same bytes
  /// are handed out until it changes, so a GIF is not started again on
  /// every look.
  final Map<String, (String, Uint8List)> _icons = {};

  Uint8List? _icon(String id, Object? hex) {
    if (hex is! String) {
      _icons.remove(id);
      return null;
    }
    final (known, bytes) = _icons[id] ?? ('', null);
    if (known == hex && bytes != null) return bytes;
    final read = _bytesOfHex(hex);
    // The owner's device sent it. One that claims a huge size is not
    // decoded: see image_bounds.dart.
    if (read == null || !soundImage(read)) return null;
    _icons[id] = (hex, read);
    return read;
  }

  @override
  bool setIcon(String spaceId, Uint8List? icon) =>
      _do({
        'op': 'space_icon',
        'space': spaceId,
        if (icon != null) 'icon': _hexOf(icon),
      }) !=
      null;

  static String _hexOf(Uint8List bytes) =>
      [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

  @override
  bool setWelcome(String spaceId, {String? welcome, String? rules}) =>
      _do({
        'op': 'space_welcome',
        'space': spaceId,
        'welcome': ?welcome,
        'rules': ?rules,
      }) !=
      null;

  @override
  bool setNickname(String spaceId, String personId, String name) =>
      _do({
        'op': 'space_nick',
        'space': spaceId,
        'member': personId,
        'name': name.trim(),
      }) !=
      null;

  static SpaceRole _role(Object? name) => switch (name) {
    'owner' => SpaceRole.owner,
    'admin' => SpaceRole.admin,
    _ => SpaceRole.member,
  };

  /// Two words give two letters, one word gives one.
  static String _initials(String name) => name
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2)
      .map((word) => word.substring(0, 1).toUpperCase())
      .join();

  // The lists

  @override
  List<Space> get joined => [for (final view in _list('joined')) _space(view)];

  @override
  List<Space> get discoverable => [
    for (final view in _list('nearby')) _space(view),
  ];

  @override
  List<SpaceInvite> get invites => [
    for (final view in _list('invited'))
      SpaceInvite(
        space: _space(view),
        invitedById: view['invited_by'] as String? ?? '',
      ),
  ];

  @override
  String? get selectedId => _selectedId;

  @override
  void select(String id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  // Making, joining, leaving

  @override
  String? create(String name, SpaceKind kind, {String description = ''}) {
    final made = _do({
      'op': 'space_create',
      'name': name,
      'kind': kind.coreName,
      'description': description,
    });
    final id = made?['id'] as String?;
    if (id != null && kind != SpaceKind.channel) _selectedId = id;
    return id;
  }

  @override
  bool join(String spaceId) {
    final wasBroadcast = _list('nearby')
        .followedBy(_list('invited'))
        .any((v) => v['id'] == spaceId && v['kind'] == 'channel');
    if (_do({'op': 'space_join', 'space': spaceId}) == null) return false;
    if (!wasBroadcast) select(spaceId);
    return true;
  }

  @override
  bool leave(String spaceId) {
    if (_do({'op': 'space_leave', 'space': spaceId}) == null) return false;
    _open.remove(spaceId);
    if (_selectedId == spaceId) _selectedId = null;
    return true;
  }

  @override
  bool invite(String spaceId, String personId) {
    final Object? envelope;
    try {
      envelope = _bridge.call({
        'op': 'space_invite',
        'space': spaceId,
        'to': personId,
      });
    } on CoreException {
      return false;
    }
    // Kept by the core until their device has it, like any message.
    _pump.deliver(envelope);
    return true;
  }

  @override
  String? inviteLink(String spaceId, {Duration? lasts}) => switch (_ask({
    'op': 'space_link',
    'space': spaceId,
    'lasts': ?lasts?.inSeconds,
  })) {
    {'link': final String link} => link,
    _ => null,
  };

  @override
  InviteCheck? checkLink(String link) => switch (_ask({
    'op': 'space_link_check',
    'link': link,
  })) {
    {'name': final String name, 'expired': final bool expired} && final found =>
      InviteCheck(
        name: name,
        expired: expired,
        endsAt: switch (found['expires_at']) {
          final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
          _ => null,
        },
      ),
    _ => null,
  };

  @override
  String? joinByLink(String link) {
    final id = _do({'op': 'space_join_link', 'link': link})?['id'] as String?;
    if (id != null) select(id);
    return id;
  }

  // Channels

  /// The space a channel belongs to. Channel ids are random, so one id is
  /// in one space.
  String? _spaceOf(String channelId) {
    for (final view in _list('joined')) {
      final channels = ((view['channels'] as List?) ?? const [])
          .cast<Map<String, Object?>>();
      if (channels.any((c) => c['id'] == channelId)) {
        return view['id'] as String?;
      }
    }
    return null;
  }

  List<Map<String, Object?>> _channel(String channelId) =>
      _said.putIfAbsent(channelId, () {
        final space = _spaceOf(channelId);
        if (space == null) return const [];
        final reply = _ask({
          'op': 'space_channel',
          'space': space,
          'channel': channelId,
        });
        final messages = switch (reply) {
          {'messages': final List<Object?> messages} =>
            messages.cast<Map<String, Object?>>(),
          _ => const <Map<String, Object?>>[],
        };
        if (reply case {'pinned': final Map<String, Object?> pinned}) {
          _pins[channelId] = pinned;
        }
        _learnNames(messages);
        return messages;
      });

  void _learnNames(List<Map<String, Object?>> messages) {
    for (final message in messages) {
      final name = safeName(message['name'] as String? ?? '');
      if (name.isNotEmpty) _names[message['author']! as String] = name;
    }
  }

  String _when(int sentAt) {
    final then = DateTime.fromMillisecondsSinceEpoch(sentAt);
    final now = _clock();
    final today =
        then.year == now.year && then.month == now.month && then.day == now.day;
    return today
        ? DateFormat.Hm().format(then)
        : DateFormat.MMMd().format(then);
  }

  /// Reactions someone has given. Kinds nobody has used are left out.
  /// The heart and agree first, then any emoji, the most given first.
  static List<Reaction> _reactions(Map<String, Object?> message) {
    final given = message['reactions'];
    if (given is! Map) return const [];
    final emoji = [
      for (final MapEntry(:key, :value) in given.entries)
        if (key is String &&
            key != ReactionKind.heart.name &&
            key != ReactionKind.agree.name)
          if (value case {'count': final int count, 'mine': final bool mine}
              when count > 0)
            Reaction(ReactionKind.emoji, count, mine: mine, emoji: key),
    ]..sort((a, b) => b.count.compareTo(a.count));
    return [
      for (final kind in const [ReactionKind.heart, ReactionKind.agree])
        if (given[kind.name]
            case {'count': final int count, 'mine': final bool mine}
            when count > 0)
          Reaction(kind, count, mine: mine),
      ...emoji,
    ];
  }

  @override
  void openChannel(String spaceId, String channelId) {
    _open[spaceId] = channelId;
    _ask({'op': 'space_read', 'space': spaceId, 'channel': channelId});
    _forget();
    notifyListeners();
  }

  /// A poll, if the message is one. Its question is the message's words.
  static Poll? _poll(Map<String, Object?> message) => switch (message['poll']) {
    {'options': final List<Object?> options, 'mine': final Object? mine} =>
      Poll(
        question: message['body'] as String? ?? '',
        options: [
          for (final option in options.cast<Map<String, Object?>>())
            PollOption(option['text']! as String, option['votes']! as int),
        ],
        myChoice: mine as int?,
      ),
    _ => null,
  };

  ChannelMessage _message(Map<String, Object?> m) {
    final poll = _poll(m);
    final location = Place.fromWire(m['location']);
    final sticker = stickerFromWire(m['sticker']);
    return ChannelMessage(
      id: m['id']! as String,
      authorId: m['mine'] == true ? meId : m['author']! as String,
      time: _when(m['sent_at']! as int),
      // A poll shows its question on the card, not as a line of text,
      // and a place shows on its own card, as a sticker does.
      text: poll == null && location == null && sticker == null
          ? m['body'] as String?
          : null,
      location: location,
      sticker: sticker,
      replyTo: switch (m['reply_to']) {
        {'name': final String name, 'body': final String body} =>
          '$name: $body',
        _ => null,
      },
      reactions: _reactions(m),
      poll: poll,
      pinned: m['pinned'] == true,
      edited: m['edited'] == true,
      mentions: [
        for (final name in (m['mentions'] as List?) ?? const []) name as String,
        for (final name in (m['roles'] as List?) ?? const []) name as String,
        if (m['everyone'] == true) 'everyone',
      ],
      mentionsMe: m['mentions_me'] == true,
      forwarded: m['forwarded'] == true,
      file: switch (m['file']) {
        final Map<String, Object?> file => _file(file),
        _ => null,
      },
      disappears: m['ends_at'] is int,
      endsAt: switch (m['ends_at']) {
        final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
        _ => null,
      },
    );
  }

  @override
  List<ChannelMessage> messages(String channelId) {
    final messages = [for (final m in _channel(channelId)) _message(m)];
    for (final message in messages) {
      _fetchIfSmall(channelId, message.id, message.file, message.authorId);
    }
    return messages;
  }

  @override
  set isContact(bool Function(String key) test) => _isContact = test;

  @override
  set speakingIn(String? Function(String space, String channel) find) =>
      _speakingIn = find;
  String? Function(String space, String channel) _speakingIn = _nobodySpeaks;
  static String? _nobodySpeaks(String space, String channel) => null;

  /// Who is in each voice room, as the core last heard. Null means ask
  /// again.
  List<Map<String, Object?>>? _rooms;

  List<Map<String, Object?>> get _roomsNow =>
      _rooms ??= switch (_ask({'op': 'rooms'})) {
        final List<Object?> list => list.cast<Map<String, Object?>>(),
        _ => const [],
      };

  Map<String, Object?>? _roomOf(String space, String channel) => _roomsNow
      .where((r) => r['space'] == space && r['channel'] == channel)
      .firstOrNull;
  bool Function(String key) _isContact = _nobody;
  static bool _nobody(String _) => false;

  /// A small picture, video or voice message from a contact is fetched
  /// without asking, as a small file from a contact is taken without asking. One
  /// from anyone else waits until the user asks for it. Asked for once.
  void _fetchIfSmall(
    String channelId,
    String id,
    FileAttachment? file,
    String author,
  ) {
    if (author != meId && !_isContact(author)) return;
    if (file == null ||
        file.held ||
        file.wanted ||
        file.kind == FileKind.file ||
        file.bytes > _fetchUnasked ||
        !_askedUnasked.add(id)) {
      return;
    }
    scheduleMicrotask(() => fetchFile(channelId, id));
  }

  /// The biggest picture, video or voice message fetched without asking.
  static const _fetchUnasked = 2 * 1024 * 1024;
  final _askedUnasked = <String>{};

  FileAttachment _file(Map<String, Object?> f) {
    final size = f['size'] as int? ?? 0;
    final pieces = f['pieces'] as int? ?? 1;
    return FileAttachment(
      f['name'] as String? ?? '',
      formatBytes(size),
      kind: FileKind.fromWire(f['kind']),
      held: f['held'] == true,
      wanted: f['wanted'] == true,
      progress: pieces == 0 ? 0 : (f['have'] as int? ?? 0) / pieces,
      path: f['path'] as String?,
      seconds: f['seconds'] as int? ?? 0,
      bytes: size,
    );
  }

  @override
  bool sendFile(
    String channelId,
    String path, {
    required FileKind kind,
    int seconds = 0,
    String caption = '',
  }) {
    final space = _spaceOf(channelId);
    if (space == null) return false;
    return _do({
          'op': 'space_post_file',
          'space': space,
          'channel': channelId,
          'path': path,
          'kind': kind.name,
          'seconds': seconds,
          'body': caption,
        }) !=
        null;
  }

  @override
  void fetchFile(String channelId, String messageId) {
    final space = _spaceOf(channelId);
    if (space == null) return;
    _do({'op': 'space_file_get', 'space': space, 'post': messageId});
  }

  @override
  String? saveFile(String channelId, String messageId, String dir) {
    final space = _spaceOf(channelId);
    if (space == null) return null;
    return _do({
          'op': 'space_file_save',
          'space': space,
          'post': messageId,
          'dir': dir,
        })?['path']
        as String?;
  }

  Map<String, Object?>? _pin(String channelId) {
    _channel(channelId);
    return _pins[channelId];
  }

  @override
  String? pinned(String channelId) => _pin(channelId)?['body'] as String?;

  @override
  String? pinnedId(String channelId) => _pin(channelId)?['id'] as String?;

  @override
  void setPinned(String channelId, String messageId, {required bool on}) {
    final space = _spaceOf(channelId);
    if (space == null) return;
    _do({'op': 'space_pin', 'space': space, 'target': messageId, 'on': on});
  }

  @override
  Refused? sendText(String channelId, String text, {String? replyTo}) =>
      _post(channelId, text, replyTo: replyTo);

  @override
  Refused? forwardText(String channelId, String text) =>
      _post(channelId, text, forwarded: true);

  @override
  ({bool sent, Refused? refused}) sendLocation(String channelId, Place place) {
    final space = _spaceOf(channelId);
    if (space == null) return (sent: false, refused: null);
    final Object? reply;
    try {
      reply = _bridge.call({
        'op': 'space_post',
        'space': space,
        'channel': channelId,
        // The core writes the place out as the words itself.
        'body': place.text,
        'location': place.toWire(),
      });
    } on CoreException catch (refusal) {
      return (sent: false, refused: _ruleOf(refusal));
    }
    _pump.sendDeliveries(reply);
    _forget();
    notifyListeners();
    return (sent: true, refused: null);
  }

  Refused? _post(
    String channelId,
    String text, {
    String? replyTo,
    bool forwarded = false,
  }) {
    final space = _spaceOf(channelId);
    if (space == null || text.trim().isEmpty) return null;
    final Object? reply;
    try {
      reply = _bridge.call({
        'op': 'space_post',
        'space': space,
        'channel': channelId,
        'body': text,
        'reply_to': ?replyTo,
        // Words passed on call on nobody here: whoever wrote them was
        // calling on people somewhere else.
        if (!forwarded) ...{
          'mentions': _calledOn(space, text),
          'roles': _rolesCalled(space, text),
          'everyone': _calls(text.toLowerCase(), 'everyone'),
        },
        'forwarded': forwarded,
      });
    } on CoreException catch (refusal) {
      return _ruleOf(refusal);
    }
    _pump.sendDeliveries(reply);
    _forget();
    notifyListeners();
    return null;
  }

  static final _wordGoesOn = RegExp(r'[\p{L}\p{N}_]', unicode: true);

  /// Whether [name] follows an @ in [lower], and is not just the start of
  /// a longer word. Both in small letters.
  static bool _calls(String lower, String name) {
    if (name.isEmpty) return false;
    final written = '@$name';
    for (
      var at = lower.indexOf(written);
      at >= 0;
      at = lower.indexOf(written, at + 1)
    ) {
      final next = at + written.length;
      if (next == lower.length || !_wordGoesOn.hasMatch(lower[next])) {
        return true;
      }
    }
    return false;
  }

  /// The members a message calls on: each whose name, as the space
  /// lists it, follows an @ in the text, and is not just the start of a
  /// longer word. Capitals do not matter.
  List<String> _calledOn(String spaceId, String text) {
    if (!text.contains('@')) return const [];
    final members = _ask({'op': 'space_members', 'space': spaceId});
    if (members is! List) return const [];
    final lower = text.toLowerCase();
    final listed = [
      for (final m in members.cast<Map<String, Object?>>())
        (
          key: m['key']! as String,
          name: safeName(m['name'] as String? ?? '').toLowerCase(),
        ),
    ];
    // A name two members share calls on one of them only with that one's
    // tag after it, as "@amber-tiger·4F2A": it is the key that is called
    // on, never just the name.
    final shared = Names.shared(listed);
    return [
      for (final m in listed)
        if (shared.contains(m.name)
            ? _calls(
                lower,
                '${m.name}${Names.tagMark}${Names.tag(m.key).toLowerCase()}',
              )
            : _calls(lower, m.name))
          m.key,
    ];
  }

  /// The roles a message calls on, by id: each whose name follows an @
  /// in the text, as for members.
  List<String> _rolesCalled(String spaceId, String text) {
    if (!text.contains('@')) return const [];
    final lower = text.toLowerCase();
    final view = _list('joined').where((v) => v['id'] == spaceId).firstOrNull;
    return [
      for (final role
          in ((view?['roles'] as List?) ?? const [])
              .cast<Map<String, Object?>>())
        if (_calls(lower, (role['name'] as String? ?? '').trim().toLowerCase()))
          role['id']! as String,
    ];
  }

  /// Which of the channel's rules the core says stood in the way, if it
  /// was one of them.
  static Refused? _ruleOf(CoreException refusal) {
    const slow = 'rule:slow:';
    const quiet = 'rule:timeout:';
    const long = 'rule:long:';
    if (refusal.message == 'rule:links') return const Refused(links: true);
    if (refusal.message == 'rule:banned') return const Refused(banned: true);
    if (refusal.message == 'rule:role') {
      return const Refused(roleNeeded: true);
    }
    if (refusal.message == 'rule:everyone') {
      return const Refused(everyoneNotAllowed: true);
    }
    if (refusal.message.startsWith(long)) {
      return Refused(
        maxLength: int.tryParse(refusal.message.substring(long.length)) ?? 1,
      );
    }
    if (refusal.message.startsWith(quiet)) {
      return Refused(
        timeoutSeconds:
            int.tryParse(refusal.message.substring(quiet.length)) ?? 1,
      );
    }
    if (refusal.message.startsWith(slow)) {
      return Refused(
        waitSeconds: int.tryParse(refusal.message.substring(slow.length)) ?? 1,
      );
    }
    return null;
  }

  @override
  ({bool changed, Refused? refused}) editText(
    String channelId,
    String messageId,
    String text,
  ) => _edit(_spaceOf(channelId), messageId, text);

  @override
  ({bool changed, Refused? refused}) editComment(
    String spaceId,
    String commentId,
    String text,
  ) => _edit(spaceId, commentId, text);

  ({bool changed, Refused? refused}) _edit(
    String? space,
    String messageId,
    String text,
  ) {
    if (space == null || text.trim().isEmpty) {
      return (changed: false, refused: null);
    }
    final Object? reply;
    try {
      reply = _bridge.call({
        'op': 'space_edit_post',
        'space': space,
        'target': messageId,
        'body': text,
      });
    } on CoreException catch (refusal) {
      return (changed: false, refused: _ruleOf(refusal));
    }
    _pump.sendDeliveries(reply);
    _forget();
    notifyListeners();
    return (changed: true, refused: null);
  }

  @override
  bool sendPoll(String channelId, String question, List<String> options) {
    final space = _spaceOf(channelId);
    final choices = [
      for (final option in options)
        if (option.trim().isNotEmpty) option.trim(),
    ];
    if (space == null || question.trim().isEmpty || choices.length < 2) {
      return false;
    }
    final sent = _do({
      'op': 'space_post',
      'space': space,
      'channel': channelId,
      'body': question,
      'options': choices,
    });
    return sent != null;
  }

  void _react(
    String space,
    String channelId,
    String target,
    ReactionKind kind, {
    String emoji = '',
  }) {
    final wire = Reaction(kind, 0, emoji: emoji).wire;
    final given = _channel(channelId)
        .where((m) => m['id'] == target)
        .expand(_reactions)
        .any((r) => r.wire == wire && r.mine);
    _do({
      'op': 'space_react',
      'space': space,
      'target': target,
      'kind': wire,
      'on': !given,
    });
  }

  @override
  bool get anyEmojiReactions => true;

  @override
  void toggleEmojiReaction(String channelId, String messageId, String emoji) {
    final space = _spaceOf(channelId);
    if (space != null) {
      _react(space, channelId, messageId, ReactionKind.emoji, emoji: emoji);
    }
  }

  @override
  void togglePostEmojiReaction(String spaceId, String postId, String emoji) {
    final feed = _feed(spaceId);
    if (feed != null) {
      _react(spaceId, feed, postId, ReactionKind.emoji, emoji: emoji);
    }
  }

  @override
  bool get canSendStickers => true;

  @override
  ({bool sent, Refused? refused}) sendSticker(
    String channelId,
    Sticker sticker,
  ) {
    final space = _spaceOf(channelId);
    if (space == null) return (sent: false, refused: null);
    final Object? reply;
    try {
      reply = _bridge.call({
        'op': 'space_post',
        'space': space,
        'channel': channelId,
        'body': '',
        'sticker': stickerToWire(sticker),
      });
    } on CoreException catch (refusal) {
      return (sent: false, refused: _ruleOf(refusal));
    }
    _pump.sendDeliveries(reply);
    _forget();
    notifyListeners();
    return (sent: true, refused: null);
  }

  @override
  void toggleReaction(String channelId, String messageId, ReactionKind kind) {
    final space = _spaceOf(channelId);
    if (space != null) _react(space, channelId, messageId, kind);
  }

  @override
  void votePoll(String channelId, String messageId, int option) {
    final space = _spaceOf(channelId);
    if (space == null) return;
    _do({
      'op': 'space_vote',
      'space': space,
      'target': messageId,
      'choice': option,
    });
  }

  // Public channels

  /// A public channel has one feed.
  String? _feed(String spaceId) {
    for (final view in _list('joined')) {
      if (view['id'] != spaceId) continue;
      final channels = ((view['channels'] as List?) ?? const [])
          .cast<Map<String, Object?>>();
      return channels.firstOrNull?['id'] as String?;
    }
    return null;
  }

  @override
  List<OwnerPost> posts(String spaceId) {
    final feed = _feed(spaceId);
    if (feed == null) return const [];
    final posts = [
      // Newest first, as a feed is read.
      for (final m in _channel(feed).reversed)
        OwnerPost(
          id: m['id']! as String,
          authorId: m['mine'] == true ? meId : m['author'] as String? ?? '',
          text: m['body'] as String? ?? '',
          time: _when(m['sent_at']! as int),
          reactions: _reactions(m),
          comments: m['comments'] as int? ?? 0,
          edited: m['edited'] == true,
          file: switch (m['file']) {
            final Map<String, Object?> file => _file(file),
            _ => null,
          },
        ),
    ];
    for (final post in posts) {
      _fetchIfSmall(feed, post.id, post.file, post.authorId);
    }
    return posts;
  }

  @override
  void togglePostReaction(String spaceId, String postId, ReactionKind kind) {
    final feed = _feed(spaceId);
    if (feed != null) _react(spaceId, feed, postId, kind);
  }

  @override
  List<ChannelMessage> comments(String spaceId, String postId) {
    final under = _under.putIfAbsent(postId, () {
      final reply = _ask({
        'op': 'space_comments',
        'space': spaceId,
        'post': postId,
      });
      final comments = reply is List
          ? reply.cast<Map<String, Object?>>()
          : const <Map<String, Object?>>[];
      _learnNames(comments);
      return comments;
    });
    return [for (final m in under) _message(m)];
  }

  @override
  void sendComment(String spaceId, String postId, String text) {
    final feed = _feed(spaceId);
    if (feed == null || text.trim().isEmpty) return;
    _do({
      'op': 'space_post',
      'space': spaceId,
      'channel': feed,
      'body': text,
      'reply_to': postId,
    });
  }

  @override
  bool canComment(String spaceId) =>
      _list('joined')
          .any((view) => view['id'] == spaceId && view['kind'] == 'channel');

  // Running a space

  @override
  bool get canManage => true;

  @override
  bool edit(String spaceId, {String? name, String? description}) =>
      _do({
        'op': 'space_edit',
        'space': spaceId,
        'name': ?name,
        'description': ?description,
      }) !=
      null;

  @override
  String? addChannel(
    String spaceId,
    String name, {
    bool info = false,
    bool voice = false,
  }) =>
      _do({
            'op': 'space_channel_add',
            'space': spaceId,
            'name': name,
            'group': voice
                ? 'voice'
                : info
                ? 'info'
                : 'text',
          })?['id']
          as String?;

  @override
  bool setVoiceRule(
    String spaceId,
    String memberId, {
    bool mute = false,
    bool deafen = false,
  }) =>
      _do({
        'op': 'space_voice',
        'space': spaceId,
        'member': memberId,
        'mute': mute,
        'deafen': deafen,
      }) !=
      null;

  /// Everyone in a voice room as heard, the user not counted.
  List<Map<String, Object?>> _people(String space, String channel) => [
    for (final p in (_roomOf(space, channel)?['people'] as List?) ?? const [])
      (p as Map).cast<String, Object?>(),
  ];

  @override
  bool renameChannel(String spaceId, String channelId, String name) =>
      _do({
        'op': 'space_channel_rename',
        'space': spaceId,
        'channel': channelId,
        'name': name,
      }) !=
      null;

  @override
  bool setChannelRules(
    String spaceId,
    String channelId, {
    int? slowSeconds,
    bool? noLinks,
    bool? ownersOnly,
    int? disappearSeconds,
    int? maxLength,
    List<String>? writerRoles,
  }) =>
      _do({
        'op': 'space_channel_rules',
        'space': spaceId,
        'channel': channelId,
        'slow': ?slowSeconds,
        'no_links': ?noLinks,
        'owners_only': ?ownersOnly,
        'disappear': ?disappearSeconds,
        'max_len': ?maxLength,
        'writers': ?writerRoles,
      }) !=
      null;

  @override
  String? addRole(String spaceId, String name, Set<RolePower> may) =>
      _do({
            'op': 'space_role_add',
            'space': spaceId,
            'name': name,
            'may': [for (final power in may) power.wire],
          })?['id']
          as String?;

  @override
  bool editRole(
    String spaceId,
    String roleId, {
    String? name,
    Set<RolePower>? may,
  }) =>
      _do({
        'op': 'space_role_edit',
        'space': spaceId,
        'role': roleId,
        'name': ?name,
        'may': ?may?.map((power) => power.wire).toList(),
      }) !=
      null;

  @override
  bool removeRole(String spaceId, String roleId) =>
      _do({'op': 'space_role_remove', 'space': spaceId, 'role': roleId}) !=
      null;

  @override
  bool grantRole(
    String spaceId,
    String personId,
    String roleId, {
    required bool on,
  }) =>
      _do({
        'op': 'space_grant',
        'space': spaceId,
        'member': personId,
        'role': roleId,
        'on': on,
      }) !=
      null;

  @override
  Map<String, List<String>> memberRoleIds(String spaceId) {
    final members = _ask({'op': 'space_members', 'space': spaceId});
    if (members is! List) return const {};
    return {
      for (final m in members.cast<Map<String, Object?>>())
        m['key']! as String: [
          for (final role in (m['roles'] as List?) ?? const []) role as String,
        ],
    };
  }

  @override
  bool setBannedWords(String spaceId, List<String> words) =>
      _do({'op': 'space_banned_words', 'space': spaceId, 'words': words}) !=
      null;

  @override
  bool setWordFilter(String spaceId, bool on) =>
      _do({'op': 'space_word_filter', 'space': spaceId, 'on': on}) != null;

  @override
  bool removeChannel(String spaceId, String channelId) {
    final removed =
        _do({
          'op': 'space_channel_remove',
          'space': spaceId,
          'channel': channelId,
        }) !=
        null;
    if (removed && _open[spaceId] == channelId) _open.remove(spaceId);
    return removed;
  }

  @override
  bool timeOut(String spaceId, String personId, int seconds) =>
      _do({
        'op': 'space_timeout',
        'space': spaceId,
        'member': personId,
        'seconds': seconds,
      }) !=
      null;

  @override
  bool resetInviteLinks(String spaceId) =>
      _do({'op': 'space_reset_links', 'space': spaceId}) != null;

  @override
  bool setMyName(String spaceId, String name) =>
      _do({'op': 'space_name', 'space': spaceId, 'name': name}) != null;

  @override
  bool deleteSpace(String spaceId) {
    if (_do({'op': 'space_delete_space', 'space': spaceId}) == null) {
      return false;
    }
    _open.remove(spaceId);
    if (_selectedId == spaceId) _selectedId = null;
    return true;
  }

  @override
  bool setAdmin(String spaceId, String personId, {required bool admin}) =>
      _do({
        'op': 'space_role',
        'space': spaceId,
        'member': personId,
        'admin': admin,
      }) !=
      null;

  @override
  bool removeMember(String spaceId, String personId) =>
      _do({'op': 'space_remove', 'space': spaceId, 'member': personId}) != null;

  @override
  bool handOver(String spaceId, String personId) =>
      _do({'op': 'space_handover', 'space': spaceId, 'to': personId}) != null;

  @override
  void deleteMessage(String spaceId, String messageId) {
    _do({'op': 'space_delete', 'space': spaceId, 'target': messageId});
  }

  @override
  Map<String, SpaceRole> roles(String spaceId) {
    final members = _ask({'op': 'space_members', 'space': spaceId});
    if (members is! List) return const {};
    return {
      for (final m in members.cast<Map<String, Object?>>())
        m['key']! as String: _role(m['role']),
    };
  }

  @override
  Map<String, MemberStatus> statuses(String spaceId) {
    final members = _ask({'op': 'space_members', 'space': spaceId});
    if (members is! List) return const {};
    return {
      for (final m in members.cast<Map<String, Object?>>())
        m['key']! as String: MemberStatus.fromWire(m['status']),
    };
  }

  @override
  void typingIn(String channelId) {
    final space = _spaceOf(channelId);
    // As in a chat: said only to someone in range, and not for every
    // letter. The core says nothing unless the user switched it on.
    if (space == null ||
        !joined.any((s) => s.id == space && s.nearbyCount > 0) ||
        _within(_toldTyping[channelId], LiveDirectory.typingEvery)) {
      return;
    }
    _toldTyping[channelId] = _clock().millisecondsSinceEpoch;
    final reply = _ask({
      'op': 'space_typing',
      'space': space,
      'channel': channelId,
    });
    if (reply != null) _pump.sendDeliveries(reply);
  }

  @override
  List<String> typingNow(String channelId) => [
    for (final MapEntry(key: (channel, who), value: at) in _typing.entries)
      if (channel == channelId && _within(at, LiveDirectory.typingFor)) who,
  ];

  @override
  bool isMuted(String spaceId) =>
      _list('joined').any((v) => v['id'] == spaceId && v['muted'] == true);

  @override
  void toggleMuted(String spaceId) {
    _do({'op': 'space_mute', 'space': spaceId, 'on': !isMuted(spaceId)});
  }

  /// The call key words of the voice room the user is in, if it is this
  /// one.
  @override
  List<String>? callWords(String channelId) {
    final room = _roomsNow
        .where((r) => r['channel'] == channelId && r['joined'] == true)
        .firstOrNull;
    final words = room?['words'];
    return words is List ? words.cast<String>() : null;
  }

  // People

  Person _person(String id, String name) => Person(
    id: id,
    name: name,
    tone: toneForKey(id),
    // Whether they can be reached is the directory's to say. From a space
    // alone, nothing is known.
    link: const PersonLink.outOfRange(),
    photo: _photos[id],
    away: _aways[id],
  );

  /// Why members in range said they are away, by key, as their spaces
  /// last said.
  final Map<String, String> _aways = {};

  /// Members' profile photos, by key, as their spaces last said.
  final Map<String, Uint8List> _photos = {};

  static Uint8List? _bytesOfHex(Object? hex) {
    if (hex is! String || hex.isEmpty || hex.length.isOdd) return null;
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      final byte = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) return null;
      bytes[i] = byte;
    }
    return bytes;
  }

  @override
  Person? member(String id) => switch (_names[id]) {
    final name? => _person(id, name),
    null => null,
  };

  @override
  List<Person> members(String spaceId) {
    final members = _ask({'op': 'space_members', 'space': spaceId});
    if (members is! List) return const [];
    for (final m in members.cast<Map<String, Object?>>()) {
      final key = m['key']! as String;
      switch (m['away']) {
        case final String away:
          _aways[key] = away;
        case _:
          _aways.remove(key);
      }
      switch (_bytesOfHex(m['photo'])) {
        case final photo?:
          _photos[key] = photo;
        case null:
          _photos.remove(key);
      }
    }
    return [
      for (final m in members.cast<Map<String, Object?>>())
        _person(
          m['key']! as String,
          _names[m['key']! as String] = safeName(m['name']! as String),
        ),
    ];
  }
}
