import 'package:flutter/foundation.dart';

import '../design/tokens.dart';
import '../radio/lora/radio_protocol.dart' show RadioSendState;
import '../radio/radio.dart' show Transport;
import 'place.dart';

/// How a person can be reached right now.
enum LinkKind { wifi, bluetooth, radio, relayed, outOfRange }

@immutable
class PersonLink {
  const PersonLink.wifi() : kind = LinkKind.wifi, hops = 1, viaId = null;
  const PersonLink.bluetooth()
    : kind = LinkKind.bluetooth,
      hops = 1,
      viaId = null;

  /// Reached only through a LoRa radio: far away, slow, chat only.
  const PersonLink.radio() : kind = LinkKind.radio, hops = 1, viaId = null;
  const PersonLink.relayed({required this.hops, required String this.viaId})
    : kind = LinkKind.relayed;
  const PersonLink.outOfRange()
    : kind = LinkKind.outOfRange,
      hops = 0,
      viaId = null;

  final LinkKind kind;
  final int hops;

  /// The person a relayed link passes through.
  final String? viaId;

  bool get inRange => kind != LinkKind.outOfRange;
}

@immutable
class Person {
  const Person({
    required this.id,
    required this.name,
    required this.tone,
    required this.link,
    this.verified = false,
    this.isContact = false,
    this.online = false,
    this.photo,
    this.verifiedBy,
    this.verifiedAt,
    this.away,
  });

  final String id;
  final String name;
  final AvatarTone tone;
  final PersonLink link;

  /// Why they said they are away, as with ".afk lunch", while they are.
  /// Empty when they gave no reason; null when they are not away.
  final String? away;

  /// Their profile photo or GIF, if they show it to the user.
  final Uint8List? photo;

  /// Shown as the green dot. Only people who chose to share it have one.
  final bool online;

  /// True once both people compared words or scanned a code.
  final bool verified;

  /// How, and when, a verified person was verified, where that is known.
  final VerifyMethod? verifiedBy;
  final DateTime? verifiedAt;

  /// True once a chat request between the two has been accepted. Only
  /// contacts can exchange direct messages.
  final bool isContact;

  String get initial => name.isEmpty ? '?' : name[0].toUpperCase();

  Person copyWith({
    String? name,
    bool? verified,
    bool? isContact,
    PersonLink? link,
    Uint8List? photo,
    String? away,
  }) => Person(
    id: id,
    name: name ?? this.name,
    away: away ?? this.away,
    tone: tone,
    link: link ?? this.link,
    verified: verified ?? this.verified,
    isContact: isContact ?? this.isContact,
    online: online,
    photo: photo ?? this.photo,
    verifiedBy: verifiedBy,
    verifiedAt: verifiedAt,
  );
}

/// How a person was verified. A tap and a code on their screen come from
/// their own device, in the user's hand, so the app can check them itself.
/// Words and the long code are compared by the two people.
enum VerifyMethod {
  tap('tap'),
  qr('qr'),
  words('words'),
  code('code');

  const VerifyMethod(this.coreName);

  /// What the core calls this way.
  final String coreName;

  static VerifyMethod? fromCore(Object? name) =>
      values.where((m) => m.coreName == name).firstOrNull;
}

/// What came of asking someone for a chat by their link.
enum LinkRequest {
  /// The request is on its way, or waiting for a path to them.
  sent,

  /// The text is not a DNet link, or has been altered.
  notALink,

  /// It is the user's own link.
  yourself,
  alreadyContact,

  /// A one-time link that has run out. They need to send a new one.
  ranOut,
}

/// A chat request someone sent to the user.
@immutable
class IncomingRequest {
  const IncomingRequest({required this.personId, this.note, this.commonSpace});
  final String personId;
  final String? note;

  /// A space both people are in, or null when they share none.
  final String? commonSpace;
}

/// What the app keeps on this device, counted when asked.
@immutable
class StorageReport {
  const StorageReport({
    this.storeBytes = 0,
    this.receivedFiles = 0,
    this.receivedBytes = 0,
    this.voiceFiles = 0,
    this.voiceBytes = 0,
    this.carriedMessages = 0,
    this.carriedBytes = 0,
  });

  /// The sealed store: chats, spaces, settings and keys.
  final int storeBytes;

  /// Files other people sent, saved as ordinary files.
  final int receivedFiles;
  final int receivedBytes;

  /// Voice messages the user recorded.
  final int voiceFiles;
  final int voiceBytes;

  /// Sealed messages being passed on for other people. They are held
  /// inside the store, so their size is part of [storeBytes] already.
  final int carriedMessages;
  final int carriedBytes;

  int get total => storeBytes + receivedBytes + voiceBytes;
}

/// One entry in a direct message thread.
sealed class DirectItem {
  const DirectItem();
}

class DirectText extends DirectItem {
  const DirectText({
    required this.text,
    required this.time,
    required this.mine,
    this.delivered = false,
    this.read = false,
    this.disappears = false,
    this.goneInSeconds = 24 * 60 * 60,
    this.id = '',
    this.deleted = false,
    this.canDeleteForEveryone = false,
    this.forwarded = false,
    this.sticker,
    this.radioStatus,
  });
  final String text;
  final String time;
  final bool mine;
  final String id;

  /// Passed on from a channel or another chat.
  final bool forwarded;

  /// For the user's own message, when it went by a LoRa radio: how far
  /// the radio says it got. Null for a message that went another way.
  final RadioSendState? radioStatus;

  /// The sticker this message is, shown large in place of words. Its
  /// [text] is then empty.
  final Sticker? sticker;

  /// Deleted for everyone by whoever wrote it. Only its place is shown.
  final bool deleted;

  /// The user wrote it in the last two days, so they can still delete it
  /// for everyone.
  final bool canDeleteForEveryone;

  /// For a message that disappears: how long it has left.
  final int goneInSeconds;

  /// For the user's own messages: the other person's device has it. Until
  /// then the message is held on this device and sent again when the two
  /// next meet.
  final bool delivered;

  /// For the user's own messages: the other person has read it, and has
  /// chosen to say so.
  final bool read;
  final bool disappears;
}

class DirectVoice extends DirectItem {
  const DirectVoice({required this.duration, required this.mine});
  final String duration;
  final bool mine;
}

/// How far a file in a chat has got.
enum FileState {
  /// Offered to the user, who has not answered.
  asked,

  /// Offered by the user, who is waiting for an answer.
  offered,
  moving,
  paused,
  done,
  declined,
  cancelled,

  /// What arrived was not what was offered, so it was not kept.
  failed;

  bool get active =>
      this == asked || this == offered || this == moving || this == paused;
}

/// A file sent or received in a direct chat.
class DirectFile extends DirectItem {
  const DirectFile({
    required this.id,
    required this.name,
    required this.size,
    required this.done,
    required this.state,
    required this.time,
    required this.mine,
    this.path = '',
    this.once = false,
    this.viewed = false,
  });
  final String id;
  final String name;

  /// A picture the receiver may open one time, after which their device
  /// deletes it.
  final bool once;

  /// It has been opened, and the receiver's copy is gone.
  final bool viewed;

  /// Whether this is a picture waiting on this device to be opened its
  /// one time.
  bool get canOpenOnce =>
      once && !mine && !viewed && state == FileState.done && path.isNotEmpty;

  /// In bytes.
  final int size;
  final int done;
  final FileState state;
  final String time;
  final bool mine;

  /// Where a received file was saved. Empty until it is accepted.
  final String path;

  int get percent => size == 0 ? 0 : (done * 100 ~/ size).clamp(0, 100);

  /// Whether the name says this is a picture the app can draw.
  bool get isPicture => isPictureName(name);

  /// Whether the name says this is a video.
  bool get isVideo => isVideoName(name);

  static bool isVideoName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return const {
      'mp4',
      'm4v',
      'mov',
      '3gp',
      'webm',
      'mkv',
      'avi',
      'wmv',
    }.contains(name.substring(dot + 1).toLowerCase());
  }

  static bool isPictureName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return const {
      'png',
      'jpg',
      'jpeg',
      'gif',
      'webp',
      'bmp',
    }.contains(name.substring(dot + 1).toLowerCase());
  }

  /// Whether there is a whole picture on this device to draw. One sent
  /// to be seen once is never drawn in the chat, where it would stay.
  bool get showsPicture =>
      isPicture && state == FileState.done && path.isNotEmpty && !once;

  /// How long the recording is, if this is a voice message. The app names
  /// a recording after its length, which is how the other side knows.
  int? get voiceSeconds => voiceSecondsIn(name);
}

/// How long a recording is, going by its file name, or null if the name
/// is not one the app gives a voice message.
int? voiceSecondsIn(String name) => switch (_voiceName.firstMatch(name)) {
  final match? => int.tryParse(match.group(1)!),
  null => null,
};

final _voiceName = RegExp(r'^voice-(\d{1,5})s-\d+\.m4a$');

/// The name a recording is sent under: its length, then when it was made.
String voiceFileName(int seconds, DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${at.year}${two(at.month)}${two(at.day)}'
      '${two(at.hour)}${two(at.minute)}${two(at.second)}';
  return 'voice-${seconds}s-$stamp.m4a';
}

/// "0:12", "1:05".
String formatSeconds(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// "84 KB", "1.5 MB", "4.2 GB".
String formatBytes(int bytes) {
  const kb = 1024, mb = kb * 1024, gb = mb * 1024;
  if (bytes < kb) return '$bytes B';
  if (bytes < mb) return '${(bytes / kb).round()} KB';
  if (bytes < gb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / gb).toStringAsFixed(1)} GB';
}

/// A contact someone passed on. It is enough to ask that person for a
/// chat, and does nothing more.
class DirectCard extends DirectItem {
  const DirectCard({
    required this.personId,
    required this.name,
    required this.identity,
    required this.time,
    required this.mine,
  });

  /// The key of the person on the card, which is what they are known by.
  final String personId;
  final String name;

  /// Their public identity, as hex: what a request to them is sealed to.
  final String identity;
  final String time;
  final bool mine;
}

/// Where someone was, sent in a chat: shown with its numbers, to copy or
/// open in a map. Nothing is looked up to show it.
class DirectLocation extends DirectItem {
  const DirectLocation({
    required this.id,
    required this.place,
    required this.time,
    required this.mine,
    this.delivered = false,
    this.read = false,
    this.canDeleteForEveryone = false,
  });
  final String id;
  final Place place;
  final String time;
  final bool mine;

  /// For the user's own: the other person's device has it, and they read
  /// it, as for a message.
  final bool delivered;
  final bool read;

  /// The user sent it in the last two days, so can still delete it for
  /// everyone.
  final bool canDeleteForEveryone;
}

/// What can be done with a contact card.
enum CardState {
  /// The person is not known to the user. They can be asked.
  canAsk,

  /// The user has asked them and is waiting.
  asked,

  /// They are already one of the user's contacts.
  inChats,

  /// The card is of the user themselves.
  you,
}

/// A poll in a one-to-one chat. Each of the two has one choice.
class DirectPoll extends DirectItem {
  const DirectPoll({
    required this.id,
    required this.poll,
    required this.time,
    required this.mine,
  });
  final String id;
  final Poll poll;
  final String time;
  final bool mine;
}

class DirectPhoto extends DirectItem {
  const DirectPhoto({required this.time, required this.mine});
  final String time;
  final bool mine;
}

/// What the Chats list shows for one conversation.
enum PreviewKind {
  text,
  voice,
  photo,
  file,
  sticker,
  video,
  location,
  poll,

  /// The last message was deleted for everyone by whoever wrote it.
  deleted,
}

/// A video as the Chats list previews it: a first frame and how long it
/// runs, once both are known.
@immutable
class VideoPreview {
  const VideoPreview({this.path = '', this.seconds, this.failed = false});

  /// Where the video is on this device. Empty until it has arrived.
  final String path;

  /// How long it runs. Null while the device is still reading it.
  final int? seconds;

  /// The device could not read it, so there is no length and no frame.
  final bool failed;

  /// Whether the video is on this device at all.
  bool get here => path.isNotEmpty;

  /// Whether the device is still working out how long it runs.
  bool get reading => here && seconds == null && !failed;

  @override
  bool operator ==(Object other) =>
      other is VideoPreview &&
      other.path == path &&
      other.seconds == seconds &&
      other.failed == failed;

  @override
  int get hashCode => Object.hash(path, seconds, failed);
}

@immutable
class ChatSummary {
  const ChatSummary({
    required this.personId,
    required this.previewKind,
    this.previewText = '',
    this.time = '',
    this.unread = 0,
    this.disappearing = false,
    this.video,
    this.place,
    this.poll,
  });

  final String personId;
  final PreviewKind previewKind;

  /// The message text for [PreviewKind.text], the duration for voice, the
  /// file's name for a file.
  final String previewText;
  final String time;
  final int unread;
  final bool disappearing;

  /// For [PreviewKind.video]: the video, as far as it is known.
  final VideoPreview? video;

  /// For [PreviewKind.location]: the place, or null if it is gone.
  final Place? place;

  /// For [PreviewKind.poll]: the question and how the votes stand.
  final Poll? poll;

  ChatSummary copyWith({
    PreviewKind? previewKind,
    String? previewText,
    String? time,
    int? unread,
  }) => ChatSummary(
    personId: personId,
    previewKind: previewKind ?? this.previewKind,
    previewText: previewText ?? this.previewText,
    time: time ?? this.time,
    unread: unread ?? this.unread,
    disappearing: disappearing,
    video: video,
    place: place,
    poll: poll,
  );
}

enum ChannelKind { announcements, text, voice }

@immutable
class Channel {
  const Channel({
    required this.id,
    required this.name,
    required this.kind,
    this.unread = 0,
    this.mentions = 0,
    this.talkerIds = const [],
    this.speakingId,
    this.mutedIds = const [],
    this.slowSeconds = 0,
    this.noLinks = false,
    this.disappearSeconds = 0,
    this.maxLength = 0,
    this.writerRoles = const [],
    this.canWrite = true,
  });

  /// If any: only members holding one of these roles (and the owner and
  /// admins) write here.
  final List<String> writerRoles;

  /// Whether the user may write here.
  final bool canWrite;

  /// The longest a member's message here may be, in characters. Zero: no
  /// limit set.
  final int maxLength;

  /// How long a message written here lasts before every device deletes
  /// it. Zero: messages stay.
  final int disappearSeconds;

  /// How many of the unread messages call on the user.
  final int mentions;

  /// Slow mode: how long a member must leave between two messages here.
  /// Zero is no limit.
  final int slowSeconds;

  /// Whether members are kept from posting links here.
  final bool noLinks;

  final String id;
  final String name;
  final ChannelKind kind;
  final int unread;

  /// People inside a voice room right now.
  final List<String> talkerIds;
  final String? speakingId;
  final List<String> mutedIds;

  Channel copyWith({int? unread}) => Channel(
    id: id,
    name: name,
    kind: kind,
    unread: unread ?? this.unread,
    mentions: mentions,
    talkerIds: talkerIds,
    speakingId: speakingId,
    mutedIds: mutedIds,
    slowSeconds: slowSeconds,
    noLinks: noLinks,
    disappearSeconds: disappearSeconds,
    maxLength: maxLength,
    writerRoles: writerRoles,
    canWrite: canWrite,
  );
}

/// Where a channel is listed inside its space.
enum ChannelGroup { info, text, voice }

/// What a role the owner makes can let its holder do. Running the space
/// itself (its name, channels, roles and who is in it) stays with the
/// owner.
enum RolePower {
  pin('pin'),
  announce('announce'),
  delete('delete'),
  timeout('timeout'),

  /// Call on everyone in the space at once, with @everyone.
  mentionEveryone('mention_everyone');

  const RolePower(this.wire);

  /// The name the core uses.
  final String wire;

  static RolePower? fromWire(Object? name) =>
      values.where((p) => p.wire == name).firstOrNull;
}

/// How the user tells fellow members in range they are. Chosen on the You
/// screen. [offline] is never chosen: it is how anyone out of range, or
/// invisible, is shown.
enum MemberStatus {
  online('online'),
  idle('idle'),
  dnd('dnd'),

  /// Nothing is sent: fellow members see the user as offline.
  invisible('invisible'),
  offline('offline');

  const MemberStatus(this.wire);

  /// The name the core uses.
  final String wire;

  /// What the user can choose.
  static const choices = [online, idle, dnd, invisible];

  static MemberStatus fromWire(Object? name) =>
      values.where((s) => s.wire == name).firstOrNull ?? offline;
}

/// A role in a space: a name, and what whoever holds it may do.
@immutable
class SpaceRoleDef {
  const SpaceRoleDef({
    required this.id,
    required this.name,
    this.may = const {},
  });

  final String id;
  final String name;
  final Set<RolePower> may;
}

/// What came of something the camera read.
enum ScanResult {
  requestSent,
  verified,
  alreadyContact,
  yourself,
  joinedSpace,
  inviteRunOut,
  notACode,

  /// A person's code, but they are not in range, so nothing could be
  /// fetched to ask them with.
  notInRange,
}

/// What a space's invite link is for, read without joining.
@immutable
class InviteCheck {
  const InviteCheck({required this.name, this.endsAt, this.expired = false});

  final String name;

  /// When it stops letting people in, if it does.
  final DateTime? endsAt;
  final bool expired;
}

/// Why a channel would not take a message: a rule its owner set.
@immutable
class Refused {
  const Refused({
    this.links = false,
    this.waitSeconds = 0,
    this.timeoutSeconds = 0,
    this.banned = false,
    this.maxLength = 0,
    this.roleNeeded = false,
    this.everyoneNotAllowed = false,
  });

  /// It called on @everyone, which only the owner, admins and roles
  /// allowed to may do.
  final bool everyoneNotAllowed;

  /// The channel is kept for some roles to write in, and the user holds
  /// none of them.
  final bool roleNeeded;

  /// It had a word the owner keeps out of the space.
  final bool banned;

  /// It was longer than the channel allows: how long it may be.
  final int maxLength;

  /// Whoever runs the space told the user to keep quiet: how long is left.
  final int timeoutSeconds;

  /// It had a link, and links are not allowed there.
  final bool links;

  /// Slow mode: how long until the next message may be sent.
  final int waitSeconds;
}

/// What someone is in a space. The owner made it, and alone can change
/// what it is and who is in it. Admins, chosen by the owner, can pin,
/// write in the info channels and take messages down.
enum SpaceRole { owner, admin, member }

/// Parts of the design that need something this build does not have yet:
/// a camera, a call, a second radio. A screen shows the control for one
/// only where `works` says it works, so nothing on screen is a dead end.
enum Extra {
  calls,
  codeScanning,
  tapToConnect,
  shareContact,
  shareLocation,
  viewOnce,
  pollsInChats,
  filesInChannels,
  voiceInChannels,
  stripPhotoLocation,
  namesInSpaces,
  linkedDevices,
  recoveryContacts,
  storageDetails,
  linkTroubleActions,

  /// Passing a message on to another channel or a contact.
  forwarding,

  /// Online, idle, do not disturb or invisible, shown to members in range.
  memberStatus,

  /// A picture or GIF the owner sets as a space's icon.
  spaceIcons,

  /// Calls with a camera as well as sound. [calls] is sound alone.
  videoCalls,

  /// Talking in a space's voice rooms.
  voiceRooms,

  /// Stickers in chats and channels: the app's own, and the user's.
  stickers,

  /// Reacting to a message with any emoji, not only a heart or agree.
  emojiReactions,

  /// Sending videos, and playing them in the chat.
  videos,
}

/// The three kinds of space a person can make.
enum SpaceKind {
  /// Invite only. People nearby are never told it exists.
  private('private'),

  /// Anyone nearby can find it and join.
  public('public'),

  /// Public, and only its owner posts.
  channel('channel');

  const SpaceKind(this.coreName);

  /// What the core calls this kind.
  final String coreName;
}

/// An invite to a space, waiting for the user's answer.
@immutable
class SpaceInvite {
  const SpaceInvite({required this.space, required this.invitedById});
  final Space space;

  /// The contact who sent it.
  final String invitedById;
}

@immutable
class Space {
  const Space({
    required this.id,
    required this.name,
    required this.initials,
    required this.tone,
    required this.isPublic,
    this.isBroadcast = false,
    this.memberCount = 0,
    this.nearbyCount = 0,
    this.description = '',
    this.channels = const {},
    this.openChannelId,
    this.mine = false,
    this.ready = true,
    this.role = SpaceRole.member,
    this.myName,
    this.bannedWords = const [],
    this.wordFilterOn = true,
    this.roleDefs = const [],
    this.powers = const {},
    this.welcome = '',
    this.rules = '',
    this.icon,
  });

  /// The space's icon, a small picture or GIF the owner chose, once this
  /// device has it. Null shows the initials.
  final Uint8List? icon;

  /// What the owner says to everyone who joins. Empty if nothing.
  final String welcome;

  /// The space's rules, as the owner wrote them. Empty if none.
  final String rules;

  /// The roles the owner has made.
  final List<SpaceRoleDef> roleDefs;

  /// What the user may do here beyond writing, through their roles.
  final Set<RolePower> powers;

  /// Whether the user may do [power] here: the owner and admins can do
  /// all of them, and a role can allow some.
  bool may(RolePower power) => iRunIt || powers.contains(power);

  /// What the user goes by in this space, if not their usual name.
  final String? myName;

  /// Words and phrases the owner keeps out of every channel.
  final List<String> bannedWords;

  /// Whether [bannedWords] are kept out now. Switched off, the list is
  /// kept for later.
  final bool wordFilterOn;

  final String id;
  final String name;
  final String initials;
  final AvatarTone tone;
  final bool isPublic;

  /// A public channel: one feed where only the owner posts.
  final bool isBroadcast;
  final int memberCount;
  final int nearbyCount;
  final String description;
  final Map<ChannelGroup, List<Channel>> channels;

  /// The channel the user had open last, shown as selected.
  final String? openChannelId;

  /// The user made this space. Only its owner writes in its Info channels,
  /// and in a public channel only its owner posts.
  final bool mine;

  /// False for a space joined by a pasted invite until a member has been
  /// met. Until then only its name is known.
  final bool ready;

  /// What the user is in this space.
  final SpaceRole role;

  /// Whether the user is the owner or an admin.
  bool get iRunIt => role != SpaceRole.member;

  Space copyWith({
    Map<ChannelGroup, List<Channel>>? channels,
    String? openChannelId,
  }) => Space(
    id: id,
    name: name,
    initials: initials,
    tone: tone,
    isPublic: isPublic,
    isBroadcast: isBroadcast,
    memberCount: memberCount,
    nearbyCount: nearbyCount,
    description: description,
    channels: channels ?? this.channels,
    openChannelId: openChannelId ?? this.openChannelId,
    role: role,
    mine: mine,
    ready: ready,
    myName: myName,
    bannedWords: bannedWords,
    wordFilterOn: wordFilterOn,
    roleDefs: roleDefs,
    powers: powers,
    welcome: welcome,
    rules: rules,
    icon: icon,
  );
}

/// The two reactions the app has always had, and any one emoji.
enum ReactionKind { heart, agree, emoji }

@immutable
class Reaction {
  const Reaction(this.kind, this.count, {this.mine = false, this.emoji = ''});
  final ReactionKind kind;
  final int count;
  final bool mine;

  /// For [ReactionKind.emoji]: which one.
  final String emoji;

  /// What the core calls it.
  String get wire => kind == ReactionKind.emoji ? emoji : kind.name;

  Reaction toggled() =>
      Reaction(kind, mine ? count - 1 : count + 1, mine: !mine, emoji: emoji);
}

/// A sticker: one the app comes with, by [name], or one of someone's own,
/// a small picture or GIF carried in the message as [image].
@immutable
class Sticker {
  const Sticker.builtIn(this.name) : image = null;
  const Sticker.own(Uint8List this.image) : name = '';

  final String name;
  final Uint8List? image;

  bool get isOwn => image != null;
}

@immutable
class PollOption {
  const PollOption(this.label, this.votes);
  final String label;
  final int votes;
}

@immutable
class Poll {
  const Poll({required this.question, required this.options, this.myChoice});
  final String question;
  final List<PollOption> options;
  final int? myChoice;

  int get totalVotes => options.fold(0, (sum, o) => sum + o.votes);

  int percentFor(int index) =>
      totalVotes == 0 ? 0 : (options[index].votes * 100 / totalVotes).round();

  /// Moves the user's vote to [index], or casts it if they had not voted.
  Poll votedFor(int index) {
    if (index == myChoice) return this;
    final updated = [
      for (var i = 0; i < options.length; i++)
        PollOption(
          options[i].label,
          options[i].votes + (i == index ? 1 : 0) - (i == myChoice ? 1 : 0),
        ),
    ];
    return Poll(question: question, options: updated, myChoice: index);
  }
}

@immutable
class FileAttachment {
  const FileAttachment(
    this.name,
    this.size, {
    this.kind = FileKind.file,
    this.held = true,
    this.wanted = false,
    this.progress = 0,
    this.path,
    this.seconds = 0,
    this.bytes = 0,
  });
  final String name;

  /// How big it is, written for a person: "84 KB".
  final String size;
  final FileKind kind;

  /// Whether the whole file is on this device.
  final bool held;

  /// Whether the user asked for it and it is still on its way.
  final bool wanted;

  /// How much of it has come, from 0 to 1.
  final double progress;

  /// Where it is on this device, once it is here.
  final String? path;

  /// How long a voice message is.
  final int seconds;

  /// How big it is, in bytes.
  final int bytes;
}

/// Roughly how near someone is, from how strongly their device is heard.
/// Never which way: Bluetooth cannot tell.
enum Nearness {
  /// About an arm's length to a couple of metres.
  veryClose,

  /// A few steps away.
  near,

  /// Further off, or something in between.
  far;

  /// From the middle of a run of readings in dBm. The lines are rough:
  /// a wall, a pocket or a body between the two moves a reading as much
  /// as a few metres do.
  static Nearness fromRssi(int rssi) => rssi >= -60
      ? Nearness.veryClose
      : rssi >= -78
      ? Nearness.near
      : Nearness.far;
}

/// What a file in a channel is.
enum FileKind {
  picture,
  video,
  voice,
  file;

  static FileKind fromWire(Object? name) =>
      values.where((kind) => kind.name == name).firstOrNull ?? FileKind.file;
}

/// One message in a space channel.
@immutable
class ChannelMessage {
  const ChannelMessage({
    required this.id,
    required this.authorId,
    required this.time,
    this.text,
    this.replyTo,
    this.file,
    this.reactions = const [],
    this.poll,
    this.voiceDuration,
    this.disappears = false,
    this.pinned = false,
    this.edited = false,
    this.mentions = const [],
    this.mentionsMe = false,
    this.endsAt,
    this.forwarded = false,
    this.location,
    this.sticker,
  });

  final String id;

  /// Passed on from another channel or a chat.
  final bool forwarded;

  /// The sticker this message is, if it is one. Its [text] is then null.
  final Sticker? sticker;

  /// Where its writer was, if that is what they posted. Its [text] is
  /// then null.
  final Place? location;

  /// When every device deletes it, in a channel set to forget.
  final DateTime? endsAt;

  /// The names of the members and roles it calls on, as written after an
  /// @, and "everyone" if it calls on everyone.
  final List<String> mentions;

  /// Whether it calls on the user.
  final bool mentionsMe;

  /// Whether its writer has changed its words since it was sent.
  final bool edited;

  /// A person id, or [meId] for the user's own messages.
  final String authorId;
  final String time;
  final String? text;

  /// Whether the space's owner has put this at the top of its channel.
  final bool pinned;

  /// The quoted line this message replies to.
  final String? replyTo;
  final FileAttachment? file;
  final List<Reaction> reactions;
  final Poll? poll;
  final String? voiceDuration;
  final bool disappears;

  ChannelMessage copyWith({List<Reaction>? reactions, Poll? poll}) =>
      ChannelMessage(
        id: id,
        authorId: authorId,
        time: time,
        text: text,
        replyTo: replyTo,
        file: file,
        reactions: reactions ?? this.reactions,
        poll: poll ?? this.poll,
        voiceDuration: voiceDuration,
        disappears: disappears,
        pinned: pinned,
        edited: edited,
        mentions: mentions,
        mentionsMe: mentionsMe,
        endsAt: endsAt,
        forwarded: forwarded,
        location: location,
        sticker: sticker,
      );
}

/// One post in a public channel. Only the owner posts.
@immutable
class OwnerPost {
  const OwnerPost({
    required this.id,
    required this.text,
    required this.time,
    this.photoLabel,
    this.reactions = const [],
    this.comments = 0,
    this.file,
    this.edited = false,
    this.authorId = '',
  });

  /// Whether the owner has changed its words since posting it.
  final bool edited;

  /// Who posted it, by key, or [meId]. Empty when not known.
  final String authorId;

  final String id;
  final String text;
  final String time;

  /// A picture, voice message or file the owner put with the post.
  final FileAttachment? file;

  /// Stand-in caption for a photo, until real media exists.
  final String? photoLabel;
  final List<Reaction> reactions;
  final int comments;

  OwnerPost copyWith({List<Reaction>? reactions}) => OwnerPost(
    authorId: authorId,
    id: id,
    text: text,
    time: time,
    photoLabel: photoLabel,
    reactions: reactions ?? this.reactions,
    comments: comments,
    file: file,
    edited: edited,
  );
}

/// A file on its way to or from someone nearby.
@immutable
class Transfer {
  const Transfer({
    required this.fileName,
    required this.totalSize,
    required this.sentSize,
    required this.recipientId,
    required this.percent,
    required this.bytesPerSecond,
    required this.minutesLeft,
    this.id = '',
    this.incoming = false,
    this.paused = false,
    this.transport = Transport.bluetooth,
    this.foundOver = Transport.bluetooth,
  });
  final String id;
  final String fileName;
  final String totalSize;
  final String sentSize;

  /// The person at the other end, whichever way the file is going.
  final String recipientId;
  final int percent;
  final int bytesPerSecond;

  /// Null while there is not yet enough to judge by.
  final int? minutesLeft;
  final bool incoming;
  final bool paused;

  /// The link the file is going over now. The screen says which it is
  /// and never claims a speed it does not have.
  final Transport transport;

  /// The link the other person was first found over this time they were
  /// in range. Two PCs on one Wi-Fi find each other over Wi-Fi, with no
  /// Bluetooth involved at all.
  final Transport foundOver;

  /// Whether the file is going over Wi-Fi, which is fast.
  bool get overWifi => transport == Transport.wifi;
}

/// What the app can see when several links fail together. It records what
/// is and is not working, never a cause.
@immutable
class LinkTroubleReport {
  const LinkTroubleReport({
    required this.bluetoothWorking,
    required this.wifi24Working,
    required this.wifi5Working,
    required this.signalLevel,
    required this.signalPersonId,
    required this.movedIds,
    required this.heldCount,
    required this.heldForIds,
    this.wifiNearbyWorking,
    this.trend = SignalTrend.better,
    this.movedToLowIds = const [],
  });
  final bool bluetoothWorking;

  /// Whether any Wi-Fi link to someone nearby is up. When this is known,
  /// the screen shows it in place of the two Wi-Fi bands the design
  /// draws, which the app cannot tell apart.
  final bool? wifiNearbyWorking;

  /// Whether the signal to [signalPersonId] is getting better or worse.
  final SignalTrend trend;
  final bool wifi24Working;
  final bool wifi5Working;

  /// Bars lit on the five bar signal meter.
  final int signalLevel;
  final String signalPersonId;

  /// Who the Wi-Fi Direct group was moved to 5 GHz for, and to 2.4 GHz.
  final List<String> movedIds;
  final List<String> movedToLowIds;
  final int heldCount;
  final List<String> heldForIds;
}

/// Which way the signal to someone is going, from its last few readings.
enum SignalTrend { better, worse, steady }

/// The id used for the user in author fields.
const meId = 'me';

/// The id of the private notes chat.
const savedMessagesId = 'saved';

/// The sharing choices on the Privacy screen. All start off.
enum SharingSetting {
  showOnline('show_online'),
  findByName('find_by_name'),
  addToGroups('add_to_groups'),
  showIpInCalls('show_ip_in_calls'),
  readReceipts('read_receipts'),
  typing('typing'),
  screenshots('screenshots'),

  /// Contacts and members of the user's spaces see their profile photo.
  showPhoto('show_photo');

  const SharingSetting(this.coreName);

  /// What the core calls this setting.
  final String coreName;
}

/// The phone-level choices on the Privacy screen.
enum DeviceSetting {
  appLock('app_lock'),
  autoDelete('auto_delete'),
  eraseOnWrongPasscode('erase_on_wrong_passcode'),

  /// The device's own notifications, while the app is not in front.
  /// Starts on.
  notifications('notifications'),

  /// Notifications show what was said, not only who it is from. Starts
  /// on; never with an app lock on.
  notifyText('notify_text'),

  /// The app goes on in the background once put away: in the tray on a
  /// PC, with a notice on a phone. Starts on.
  background('background');

  const DeviceSetting(this.coreName);
  final String coreName;
}

/// Choices on the Privacy screen that keep the user safe. Unlike sharing,
/// each starts the way most people want it.
enum SafetySetting {
  /// A contact's own device showing their key, by a tap or a code on its
  /// screen, verifies them with no words to compare. Starts on.
  autoVerify('auto_verify'),

  /// This device passes on sealed messages between other people in range.
  /// Starts on: it is how people out of range reach each other.
  relay('relay'),

  /// Files from people who are not verified wait to be accepted, however
  /// small. Starts off.
  verifiedFilesOnly('verified_files_only');

  const SafetySetting(this.coreName);
  final String coreName;
}

/// Who may send the user a chat request. Someone using one of the user's
/// own links always may.
enum RequestsFrom {
  everyone('everyone'),

  /// Only people who are in one of the user's spaces.
  spaces('spaces'),
  nobody('nobody');

  const RequestsFrom(this.coreName);
  final String coreName;
}

/// The automatic protections listed on the Network screen.
enum LinkProtection {
  bothRadios,
  changesBand,
  longRange,
  rebuildsFiles,
  holdsMessages,
}

/// The protections the Privacy screen lists as always on.
enum AlwaysOn {
  chatEncryption,
  postQuantumKeys,
  encryptedStorage,
  keyChangeAlerts,
}

/// The link switches on the Network screen.
enum LinkSetting {
  bluetooth('bluetooth'),
  wifiNearby('wifi_nearby'),
  longRange('long_range'),
  internet('internet');

  const LinkSetting(this.coreName);
  final String coreName;
}
