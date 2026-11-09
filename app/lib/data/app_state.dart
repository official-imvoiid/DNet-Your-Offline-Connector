import 'dart:io' as io;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../calls/call_engine.dart';
import '../design/tokens.dart';
import '../radio/link_traffic.dart';
import '../radio/lora/byte_link.dart';
import '../radio/lora/lora_radio.dart';
import '../radio/lora/radio_settings.dart';
import '../radio/lora/radio_transport.dart';
import '../radio/radio.dart';
import '../core/voice.dart';
import 'codes.dart';
import 'directory.dart';
import 'emoji.dart';
import 'mesh.dart';
import 'models.dart';
import 'names.dart';
import 'photo_prep.dart';
import 'place.dart';
import 'spaces.dart';
import 'sticker_book.dart';
import 'stickers.dart';
import 'store.dart';

/// Everything the screens show and every action they can take.
///
/// It holds nothing of its own. Each kind of thing comes from one source:
///
/// - [Store]: the identity and the switches, kept encrypted by the core.
/// - [Directory]: people, chat requests, direct messages, verification.
/// - [SpaceBook]: spaces, channels and voice rooms.
/// - [transfer] and [linkTrouble]: a file on its way, and links failing
///   together.
///
/// A source that is missing means the device has none of that yet, and the
/// screens show their empty state. Nothing is ever made up to fill a gap.
class AppState extends ChangeNotifier {
  AppState({
    required this._store,
    required this._directory,
    this._spaces,
    this._transfer,
    this._linkTrouble,
    this._pickFile,
    this._screenshots,
    this._voice,
    this._voiceDir,
    this._share,
    this._scan,
    this._locator,
    this._takePhoto,
    this.isPc = false,
    String Function()? suggestName,
    DateTime Function()? clock,
  }) : _suggestName = suggestName ?? _randomName,
       _clock = clock ?? DateTime.now {
    _applyScreenshots();
    // Whoever opens the app has to give the passcode, if there is one.
    _locked = _store.hasPasscode;
    tidyUp();
    finishStamp();
    for (final source in _sources) {
      source.addListener(notifyListeners);
    }
    // Pictures in spaces come down by themselves only from contacts.
    _spaces?.isContact = (key) => _directory.find(key)?.isContact ?? false;
    _spaces?.speakingIn = (space, channel) =>
        _directory.calls?.speakingIn(space, channel);
  }

  final Store _store;
  final Directory _directory;
  final SpaceBook? _spaces;
  final ValueListenable<Transfer?>? _transfer;
  final ValueListenable<LinkTroubleReport?>? _linkTrouble;
  final Future<String?> Function()? _pickFile;

  /// Tells the device whether pictures of the app's screen may be taken.
  final void Function(bool allowed)? _screenshots;

  /// Opens the camera to read a code, where the device has a camera the
  /// app can use. Gives back what it read, or null.
  final Future<String?> Function(BuildContext context)? _scan;

  /// The device's own "share" sheet, where it has one.
  final Future<bool> Function(String text)? _share;

  /// The device's own way of knowing where it is, where it has one.
  final Locator? _locator;

  /// Takes a photo to send, where the device has a camera the app can
  /// use. Gives back where the photo was saved, or null if none was taken.
  final Future<String?> Function(BuildContext context)? _takePhoto;

  /// Whether a photo can be taken here to send.
  bool get canTakePhoto => _takePhoto != null;

  /// Opens the camera for a photo to send. Gives back where it was saved,
  /// or null if the user took none or the camera could not be used.
  Future<String?> takePhoto(BuildContext context) async =>
      _takePhoto?.call(context);

  /// The microphone and speaker, if this device has them.
  final Voice? _voice;

  /// The folder recordings are made in.
  final String? _voiceDir;
  String? _recordingTo;
  DateTime? _recordingSince;
  String? _playing;
  DateTime? _playingUntil;

  /// Screenshots are blocked unless the user has switched them on.
  void _applyScreenshots() =>
      _screenshots?.call(sharing(SharingSetting.screenshots));

  /// True on a PC. The interface text says "this PC" there, not "this
  /// phone".
  final bool isPc;
  final String Function() _suggestName;
  final DateTime Function() _clock;
  bool _locked = false;

  /// How old a chat message may get before auto-delete removes it.
  static const autoDeleteAfter = Duration(days: 30);

  Iterable<Listenable> get _sources => [
    _directory,
    ?_spaces,
    ?_transfer,
    ?_linkTrouble,
  ];

  static String _randomName() => Names.random(Random().nextInt);

  @override
  void dispose() {
    for (final source in _sources) {
      source.removeListener(notifyListeners);
    }
    super.dispose();
  }

  // Identity

  bool get hasIdentity => _store.profile != null;
  String get profileName => _store.profile?.name ?? '';

  /// What other people's devices know the user by.
  String get myId => _store.profile?.id ?? '';

  /// Whether spaces here can be run: renamed, given channels and admins.
  /// The design kit's sample world has no screen for it.
  bool get canManageSpaces => _spaces?.canManage ?? false;

  /// Calls and voice rooms, where this device has a microphone and
  /// speaker the app can use.
  CallEngine? get calls => _directory.calls;

  /// Whether this device keeps the name where it can be changed. The
  /// design kit's sample world does not.
  bool get canEditName => _store.canRename;

  /// Changes the name the user goes by, and tells contacts and spaces.
  /// False if the name cannot be used.
  bool setName(String name) {
    final reply = _store.rename(name);
    if (reply == null) return false;
    _directory.sendOn(reply);
    _spaces?.refresh();
    notifyListeners();
    return true;
  }

  String get profileInitial =>
      profileName.isEmpty ? '?' : profileName[0].toUpperCase();
  String get fingerprint => _store.profile?.fingerprint ?? '';

  /// The user's three code words for now. Made from their key and the
  /// time, so they change every ten minutes, and every device nearby
  /// works out the same ones. They tell apart people with the same name;
  /// they do not prove who anyone is.
  String get spokenCode =>
      _directory.codeWords(myId, _clock())?.words ??
      _store.profile?.spokenCode ??
      '';

  /// How long until the user's code words change. Null where they do not
  /// change, as in the design kit's sample.
  Duration? get codeWordsLeft {
    final now = _clock();
    return _directory.codeWords(myId, now)?.until.difference(now);
  }

  /// The colour of the user's own picture.
  AvatarTone get myTone => _store.profile?.tone ?? AvatarTone.green;

  /// A name to offer someone who has not thought of one.
  String suggestName() => _suggestName();

  /// Devices sharing this identity, this one included.
  int get linkedDevices => _store.linkedDevices;

  /// How many recovery contacts are set, out of how many are needed. Both
  /// are zero until recovery has been set up.
  (int set, int needed) get recoveryContacts => _store.recoveryContacts;

  // The app lock

  bool get hasPasscode => _store.hasPasscode;

  /// True while the passcode has to be given before anything is shown.
  bool get locked => _locked && hasIdentity && hasPasscode;

  /// How many more wrong passcodes there can be before everything is
  /// erased. Null if the user has not chosen that, so a miss costs nothing.
  int? get passcodeTriesLeft => device(DeviceSetting.eraseOnWrongPasscode)
      ? (10 - _store.wrongPasscodes).clamp(0, 10)
      : null;

  bool setPasscode(String passcode, {String? current}) {
    final set = _store.setPasscode(passcode, current: current);
    if (set) notifyListeners();
    return set;
  }

  bool clearPasscode(String passcode) {
    final cleared = _store.clearPasscode(passcode);
    if (cleared) {
      // Erasing after wrong passcodes means nothing with no passcode.
      _set('device', DeviceSetting.eraseOnWrongPasscode.coreName, false);
      notifyListeners();
    }
    return cleared;
  }

  /// Locks the app, if there is a passcode to unlock it with.
  void lockNow() {
    if (!hasPasscode || _locked) return;
    _locked = true;
    notifyListeners();
  }

  Future<Unlock> unlock(String passcode) async {
    final tried = _store.tryPasscode(passcode);
    if (tried.erased) {
      // The user chose to lose everything rather than have it guessed.
      await _store.startAfresh();
      _directory.reset();
      _spaces?.reset();
      _locked = false;
      _applyScreenshots();
      notifyListeners();
      return Unlock.erased;
    }
    if (tried.ok) _locked = false;
    notifyListeners();
    return tried.ok ? Unlock.opened : Unlock.wrong;
  }

  /// Does what the user asked to have done from time to time: at present,
  /// deleting old chat messages if they switched that on. Called when the
  /// app opens and when the user comes back to it.
  void tidyUp() {
    _forgetOldCopies();
    if (!hasIdentity || !device(DeviceSetting.autoDelete)) return;
    _store.deleteMessagesBefore(_clock().subtract(autoDeleteAfter));
    _directory.refresh();
  }

  /// Cleaned copies of photos are only needed while they are being sent.
  /// Any left from more than a week ago are deleted.
  void _forgetOldCopies() {
    final folder = _store.folder;
    if (folder == null) return;
    final weekAgo = _clock().subtract(const Duration(days: 7));
    try {
      final copies = io.Directory(
        '$folder${io.Platform.pathSeparator}outgoing',
      );
      if (!copies.existsSync()) return;
      for (final copy in copies.listSync().whereType<io.File>()) {
        if (copy.lastModifiedSync().isBefore(weekAgo)) copy.deleteSync();
      }
    } on io.FileSystemException {
      // Left for next time.
    }
  }

  /// Makes the user's identity: a key made on this device. The name may be
  /// anything; an empty one becomes a suggested name.
  void createIdentity(String name) {
    final trimmed = name.trim();
    _store.createIdentity(trimmed.isEmpty ? _suggestName() : trimmed);
    // There is someone to be now, so the radio may start.
    _directory.refresh();
    notifyListeners();
    // Made without the welcome screen's wait: the stamp is finished now,
    // a little at a time.
    finishStamp();
  }

  /// Makes the user's key ahead of their identity and does the work that
  /// stamps it, a slice at a time, telling [progress] how far along it is
  /// from 0 to 1. Other devices let a stranger ask to chat only with a
  /// stamp, which costs every new identity a few seconds of work, so they
  /// cannot be made in bulk for nothing. [createIdentity] then uses this
  /// key.
  Future<void> prepareIdentity({void Function(double done)? progress}) async {
    while (true) {
      final done = _store.stampWork();
      progress?.call(done);
      if (done >= 1) return;
      // Lets a frame be drawn between slices.
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Finishes the stamp on an identity that has none yet: one made before
  /// stamps, or one whose making was cut short.
  Future<void> finishStamp() async {
    if (_stamping || !hasIdentity) return;
    _stamping = true;
    try {
      while (hasIdentity && _store.stampWork() < 1) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    } finally {
      _stamping = false;
    }
  }

  bool _stamping = false;

  /// Erases the key and everything stored, and returns the app to first
  /// launch.
  Future<void> wipeEverything() async {
    await cancelVoice();
    await _voice?.stopPlaying();
    _playing = null;
    final recordings = _voiceDir == null ? null : io.Directory(_voiceDir);
    if (recordings != null && recordings.existsSync()) {
      recordings.deleteSync(recursive: true);
    }
    await _store.wipe();
    _stickerBook.reset();
    _directory.reset();
    _spaces?.reset();
    _locked = false;
    _applyScreenshots();
    notifyListeners();
  }

  // People, chat requests, direct messages and verification all come from
  // the directory. See [Directory] for what each one promises.

  /// A contact, someone in range, or someone met in a space.
  Person? findPerson(String id) {
    final found = _findPerson(id);
    // Being away is said to contacts directly, and to fellow members.
    final away = found?.away ?? _spaces?.member(id)?.away;
    return away == null || found == null || found.away == away
        ? found
        : found.copyWith(away: away);
  }

  Person? _findPerson(String id) {
    final known = _directory.find(id);
    final member = _spaces?.member(id);
    if (known == null) return member;
    // A stranger in range is shown by the code made from their key. If
    // they share a space with the user, the name they use there is more
    // use. A contact keeps the name they gave the user directly.
    if (!known.isContact && member != null) {
      return known.copyWith(name: member.name, photo: member.photo);
    }
    // A contact's photo comes to the user directly; a space's will do if
    // that has not arrived.
    if (known.photo == null && member?.photo != null) {
      return known.copyWith(photo: member!.photo);
    }
    return known;
  }

  /// The same, for a screen that is showing this person. Someone who has
  /// since been forgotten is shown by a short form of their key, never by
  /// a made-up name.
  Person person(String id) =>
      findPerson(id) ??
      Person(
        id: id,
        name: id.length > 8 ? id.substring(0, 8) : id,
        tone: toneForKey(id),
        link: const PersonLink.outOfRange(),
      );

  List<IncomingRequest> get incomingRequests => _directory.incomingRequests;
  List<Person> get outgoingRequests => _directory.outgoingRequests;
  bool hasOutgoingRequest(String id) =>
      _directory.outgoingRequests.any((p) => p.id == id);
  bool isBlocked(String id) => _directory.isBlocked(id);

  void acceptRequest(String id) => _directory.acceptRequest(id);
  void declineRequest(String id) => _directory.declineRequest(id);
  void blockPerson(String id) => _directory.blockPerson(id);
  List<Person> get blockedPeople => _directory.blockedPeople;
  void unblockPerson(String id) => _directory.unblockPerson(id);

  /// The code to compare with a contact who is somewhere else.
  ({String code, List<String> words})? checkCode(String id) =>
      _directory.checkCode(id);
  bool checkPastedCode(String id, String pasted) =>
      _directory.checkPastedCode(id, pasted);

  /// Hands text to the device's own way of sharing, where it has one.
  /// False if it has none, and the caller should copy the text instead.
  Future<bool> shareText(String text) async =>
      await _share?.call(text) ?? false;
  void sendRequest(String id) => _directory.sendRequest(id);
  String? get myLink => _directory.myLink;
  String? newInviteLink() => _directory.newInviteLink();

  // A link is often pasted with other words around it: "add me on DNet:
  // dnet:id/...". These find the link in whatever was pasted.
  static final _personLink = RegExp(r'dnet:(id|invite)/[0-9a-fA-F]+');
  static final _spaceLink = RegExp(r'dnet:space/[0-9a-fA-F]+');

  LinkRequest requestByLink(String pasted) => _directory.requestByLink(
    _personLink.firstMatch(pasted)?.group(0) ?? pasted,
  );

  // Codes for the camera.

  /// The user's own code, for someone else's camera.
  /// What the user's QR code holds: the short code for their key.
  String? get myCode => myId.isEmpty ? null : shortCode(myId);

  bool get canScan => _scan != null;
  Future<String?> scan(BuildContext context) async => _scan?.call(context);

  /// Acts on what the camera read. A person's code asks them to chat, or
  /// verifies them if they are a contact already: it was read off their
  /// own screen, so it is the identity their device really has. A space's
  /// invite joins the space.
  ///
  /// Verifying is automatic only while the user leaves that switched on.
  /// [verify] true is for the Verify screen, where scanning is the user's
  /// own way of checking.
  ScanResult scanned(String read, {bool? verify}) {
    final checks = verify ?? safety(SafetySetting.autoVerify);
    // The short code holds a key alone. Its owner is beside the user, so
    // the rest is already known from the radio.
    if (keyFromShortCode(read) case final key?) {
      if (key == myId) return ScanResult.yourself;
      if (findPerson(key)?.isContact ?? false) {
        return checks && _directory.verifyKey(key)
            ? ScanResult.verified
            : ScanResult.alreadyContact;
      }
      // Never met over the radio: nothing is known to ask them with.
      return switch (_directory.requestScanned(key, verify: checks)) {
        LinkRequest.sent => ScanResult.requestSent,
        LinkRequest.alreadyContact => ScanResult.alreadyContact,
        LinkRequest.yourself => ScanResult.yourself,
        LinkRequest.notALink || LinkRequest.ranOut => ScanResult.notInRange,
      };
    }
    final link = linkFromCode(read);
    if (link == null) return ScanResult.notACode;
    if (link.startsWith('dnet:space/')) {
      if (joinSpaceByLink(link) != null) return ScanResult.joinedSpace;
      return inviteHasRunOut(link)
          ? ScanResult.inviteRunOut
          : ScanResult.notACode;
    }
    return switch (_directory.requestByLink(link, scanned: checks)) {
      LinkRequest.sent => ScanResult.requestSent,
      LinkRequest.yourself => ScanResult.yourself,
      LinkRequest.notALink || LinkRequest.ranOut => ScanResult.notACode,
      LinkRequest.alreadyContact =>
        checks && _directory.verifyScanned(link)
            ? ScanResult.verified
            : ScanResult.alreadyContact,
    };
  }

  /// Acts on a link read off another phone tapped against this one. Like
  /// a code on their screen, it came from their own device, held in the
  /// user's hand: a contact is verified, and anyone else is asked to chat
  /// and verified once they accept. Only while verifying automatically is
  /// on; otherwise it asks, like any link.
  ScanResult tapped(String read) {
    final link = _personLink.firstMatch(read)?.group(0) ?? read.trim();
    final checks = safety(SafetySetting.autoVerify);
    final asked = checks
        ? _directory.requestTapped(link)
        : _directory.requestByLink(link);
    return switch (asked) {
      LinkRequest.sent => ScanResult.requestSent,
      LinkRequest.yourself => ScanResult.yourself,
      LinkRequest.ranOut => ScanResult.inviteRunOut,
      LinkRequest.notALink => ScanResult.notACode,
      LinkRequest.alreadyContact =>
        checks && _directory.verifyTapped(link)
            ? ScanResult.verified
            : ScanResult.alreadyContact,
    };
  }

  void cancelOutgoingRequest(String id) => _directory.cancelOutgoingRequest(id);

  void startVerify(String id) => _directory.startVerify(id);
  List<String>? verifyWords(String id) => _directory.verifyWords(id);
  void confirmVerify(String id, {required bool matched}) =>
      _directory.confirmVerify(id, matched: matched);

  List<ChatSummary> get chats => _directory.chats;
  List<DirectItem> thread(String chatId) => _directory.thread(chatId);
  void markChatRead(String id) => _directory.markChatRead(id);

  /// Adds the user's own message to a direct chat or to Saved messages.
  ///
  /// Refuses, and returns false, when the person has not accepted a chat
  /// request. That rule holds here as well as in the interface.
  bool sendDirectText(String chatId, String text) {
    final sent = _directory.sendDirectText(chatId, text);
    if (sent) _backOnSend();
    return sent;
  }

  /// Passes a message on to a contact. See [Directory.forwardText].
  bool forwardToChat(String chatId, String text) =>
      _directory.forwardText(chatId, text);

  /// Passes a message on to a channel. Returns why the channel refused
  /// it, if one of its rules did.
  Refused? forwardToChannel(String channelId, String text) =>
      _spaces?.forwardText(channelId, text);

  /// Where a message can be passed on to: every text channel the user may
  /// write in, with its space, but not [exceptChannel].
  List<(Space, Channel)> forwardTargets({String? exceptChannel}) => [
    for (final space in spaces)
      if (!space.isBroadcast && space.ready)
        for (final group in [ChannelGroup.info, ChannelGroup.text])
          for (final channel in space.channels[group] ?? const <Channel>[])
            if (channel.id != exceptChannel &&
                channel.kind != ChannelKind.voice &&
                channel.canWrite &&
                (group != ChannelGroup.info || space.may(RolePower.announce)))
              (space, channel),
  ];

  /// The user's own profile photo or GIF, if they set one.
  Uint8List? get myPhoto => _directory.myPhoto;

  /// Makes a profile photo from the picture or GIF at [path] and sets it.
  /// Contacts and members of the user's spaces are shown it, so the
  /// switch for that is turned on. False if it could not be used.
  Future<bool> setMyPhotoFrom(String path) async {
    final Uint8List? photo;
    try {
      photo = await preparePhoto(path);
    } on Object {
      return false;
    }
    if (photo == null || !_directory.setMyPhoto(photo)) return false;
    if (!sharing(SharingSetting.showPhoto)) {
      setSharing(SharingSetting.showPhoto, true);
    }
    notifyListeners();
    return true;
  }

  /// Takes the user's profile photo away, for everyone who had it.
  void clearMyPhoto() {
    _directory.clearMyPhoto();
    notifyListeners();
  }

  /// How the user tells fellow members in range they are.
  MemberStatus get myStatus => _directory.myStatus;
  bool setMyStatus(MemberStatus status) {
    final done = _directory.setMyStatus(status);
    // Members are shown with their status, the user among them.
    if (done) _spaces?.refresh();
    return done;
  }

  /// Why the user said they are away, as with ".afk lunch", while they
  /// are. Empty when they gave no reason; null when they are not away.
  String? get myAway => _directory.myAway;

  /// Says the user is away, and why. Anyone who calls on them or writes
  /// to them is told. False if it could not be said.
  bool setAway(String note) {
    final done = _directory.setAway(note.trim());
    if (done) _spaces?.refresh();
    return done;
  }

  /// Says the user is back.
  void clearAway() {
    if (myAway == null) return;
    if (_directory.setAway(null)) _spaces?.refresh();
  }

  /// Writing again is coming back.
  void _backOnSend() {
    if (myAway != null) clearAway();
  }

  /// Sets a space's welcome, its rules, or both. Owner only.
  bool setSpaceWelcome(String spaceId, {String? welcome, String? rules}) =>
      _spaces?.setWelcome(spaceId, welcome: welcome, rules: rules) ?? false;

  /// Makes a space's icon from the picture or GIF at [path] and sets it.
  /// Owner only. False if it could not be used or was refused.
  Future<bool> setSpaceIconFrom(String spaceId, String path) async {
    final Uint8List? icon;
    try {
      icon = await preparePhoto(path, maxBytes: maxSpaceIconBytes);
    } on Object {
      return false;
    }
    return icon != null && (_spaces?.setIcon(spaceId, icon) ?? false);
  }

  /// Takes a space's icon away, for everyone. Owner only.
  bool clearSpaceIcon(String spaceId) =>
      _spaces?.setIcon(spaceId, null) ?? false;

  /// Sets what a member is called in a space, for everyone.
  bool setMemberNickname(String spaceId, String personId, String name) =>
      _spaces?.setNickname(spaceId, personId, name) ?? false;

  /// How each member of a space says they are, by person id.
  Map<String, MemberStatus> memberStatuses(String spaceId) =>
      _spaces?.statuses(spaceId) ?? const {};

  /// The user is writing in a channel.
  void typingInChannel(String channelId) => _spaces?.typingIn(channelId);

  /// Who is writing in a channel right now, by person id.
  List<String> typingInChannelNow(String channelId) =>
      _spaces?.typingNow(channelId) ?? const [];
  bool sendDirectPoll(String chatId, String question, List<String> options) =>
      _directory.sendDirectPoll(chatId, question, options);
  void voteDirectPoll(String chatId, String messageId, int option) =>
      _directory.voteDirectPoll(chatId, messageId, option);

  // Nearby

  List<Person> get nearbyPeople => _directory.nearbyPeople;
  int get peopleInRange => nearbyPeople.where((p) => p.link.inRange).length;
  int get wifiLinkCount =>
      nearbyPeople.where((p) => p.link.kind == LinkKind.wifi).length;
  int get radioLinkCount =>
      nearbyPeople.where((p) => p.link.kind == LinkKind.radio).length;
  int get bluetoothLinkCount =>
      nearbyPeople.where((p) => p.link.kind == LinkKind.bluetooth).length;
  Offset? radarPosition(String id) => _directory.radarPosition(id);

  /// Roughly how near someone in range is. Null until their device has
  /// been heard.
  Nearness? nearness(String id) => _directory.nearness(id);

  /// Whether the radar places anyone by distance.
  bool get radarByDistance => _directory.radarByDistance;

  /// The mesh, for the Nearby maps. See [Directory.mesh].
  Mesh get mesh => _directory.mesh;

  /// What to call a device on the mesh: who they are to the user, else
  /// the code words made from their key, which every device works out
  /// the same.
  String meshName(String id) =>
      findPerson(id)?.name ??
      _directory.codeWords(id, _clock())?.words ??
      person(id).name;

  // The long-range radio

  /// The LoRa radio, where one is set up.
  LoRaRadio? get lora => _directory.lora;

  /// What the user chose for it: the device and the band.
  RadioSettings get radioSettings => _directory.radioSettings;

  /// Whether this build can be given a LoRa radio.
  bool get canSetUpRadio => _directory.canSetUpRadio;

  /// Sets the radio up, or with null forgets it. Returns what went
  /// wrong, or null. Switching the long-range link on is separate: see
  /// [setLink].
  Future<String?> setUpRadio(RadioEndpoint? endpoint, {RadioRegion? region}) =>
      _directory.setUpRadio(endpoint, region: region);

  /// Whether the nearby radio is working, and if not, why not.
  RadioState get radioState => _directory.radioState;
  Future<void> allowRadio() => _directory.allowRadio();

  /// Looks at the radio again. Called when the user comes back to the app,
  /// since they may have just switched Bluetooth on in the system settings.
  void recheckRadio() => _directory.retryRadio();

  // Files and link trouble

  /// The file being sent or received right now, if any.
  Transfer? get transfer => _transfer?.value ?? _directory.transfer;

  /// Whether this device can show the user their files to choose from.
  bool get canPickFiles => _pickFile != null;

  /// Lets the user choose a file. Returns its path, or null if they chose
  /// nothing.
  Future<String?> pickFile() async => _pickFile?.call();

  /// Offers a file to a contact. A photo goes as a copy with what the
  /// camera noted about it taken out, if the user has that switched on
  /// and it is a kind of picture that can be cleaned.
  ///
  /// With [once], it is a picture the receiver may open one time. Only
  /// a picture the app can show itself can be sent that way: anything
  /// else would have to be handed to another app to open, which would
  /// then have it for good.
  bool sendFile(String chatId, String path, {bool once = false}) {
    if (once && !DirectFile.isPictureName(path)) return false;
    return _directory.sendFile(chatId, _cleaned(path) ?? path, once: once);
  }

  /// The user has opened, and closed, a picture sent to be seen once.
  void viewedOnce(String id) => _directory.viewedOnce(id);

  /// Posts a file in a channel. A picture is told apart by its name and,
  /// like one sent to a person, goes as a copy without what the camera
  /// noted about it if the user has that switched on.
  bool sendChannelFile(
    String channelId,
    String path, {
    FileKind? kind,
    int seconds = 0,
    String caption = '',
  }) {
    final what =
        kind ??
        (_looksLikeAPicture(path)
            ? FileKind.picture
            : DirectFile.isVideoName(path)
            ? FileKind.video
            : FileKind.file);
    final sent = what == FileKind.picture ? (_cleaned(path) ?? path) : path;
    return _spaces?.sendFile(
          channelId,
          sent,
          kind: what,
          seconds: seconds,
          caption: caption,
        ) ??
        false;
  }

  /// Asks members in range for the file a channel message carries.
  void fetchChannelFile(String channelId, String messageId) =>
      _spaces?.fetchFile(channelId, messageId);

  /// Copies the file a channel message carries to where the app saves
  /// the user's files. Returns where it went.
  String? saveChannelFile(String channelId, String messageId) {
    final dir = _directory.receivedDir;
    if (dir == null) return null;
    return _spaces?.saveFile(channelId, messageId, dir);
  }

  /// Whether sending this file would send a picture with whatever the
  /// camera wrote into it, although the user asked for that to be
  /// removed. The app asks before sending such a one.
  bool cannotCleanPhoto(String path) =>
      removeLocationFromPhotos &&
      _looksLikeAPicture(path) &&
      _cleaned(path) == null;

  static bool _looksLikeAPicture(String path) {
    final dot = path.lastIndexOf('.');
    return dot >= 0 &&
        const {
          'jpg', 'jpeg', 'png', 'heic', 'heif', 'webp', 'avif', //
          'tif', 'tiff', 'dng', 'gif', 'bmp',
        }.contains(path.substring(dot + 1).toLowerCase());
  }

  /// A cleaned copy of a picture, kept in the app's own folder until it
  /// has been sent. Null if the switch is off or it cannot be cleaned.
  String? _cleaned(String path) {
    final folder = _store.folder;
    if (!removeLocationFromPhotos || folder == null) return null;
    return _directory.cleanPhoto(
      path,
      '$folder${io.Platform.pathSeparator}outgoing',
    );
  }

  // Voice messages. A recording is a sound file, sent like any other.

  bool get canRecordVoice => _voice != null && _voiceDir != null;
  bool get recordingVoice => _recordingTo != null;

  /// How long the recording under way has run.
  Duration get recordingFor => switch (_recordingSince) {
    final since? => _clock().difference(since),
    null => Duration.zero,
  };

  /// Starts recording. False if the microphone cannot be used.
  Future<bool> startVoice() async {
    final (voice, dir) = (_voice, _voiceDir);
    if (voice == null || dir == null || recordingVoice) return false;
    io.Directory(dir).createSync(recursive: true);
    final path = '$dir${io.Platform.pathSeparator}recording.m4a';
    if (!await voice.start(path)) return false;
    _recordingTo = path;
    _recordingSince = _clock();
    notifyListeners();
    return true;
  }

  /// Stops recording and sends what was recorded to the person in
  /// [chatId]. False if there was nothing to send or it could not be sent.
  Future<bool> sendVoice(String chatId) async {
    final done = await _finishRecording();
    return done != null && sendFile(chatId, done.$1);
  }

  /// Stops recording and posts what was recorded in a channel.
  Future<bool> sendChannelVoice(String channelId) async {
    final done = await _finishRecording();
    return done != null &&
        sendChannelFile(
          channelId,
          done.$1,
          kind: FileKind.voice,
          seconds: done.$2,
        );
  }

  /// Stops recording. Returns the recording, named for when it was made,
  /// and how long it runs; or null if there is nothing to send.
  Future<(String, int)?> _finishRecording() async {
    final (voice, path, since) = (_voice, _recordingTo, _recordingSince);
    if (voice == null || path == null || since == null) return null;
    final seconds = _clock().difference(since).inSeconds.clamp(1, 99999);
    _recordingTo = null;
    _recordingSince = null;
    final kept = await voice.stop();
    notifyListeners();
    final recorded = io.File(path);
    if (!kept || !recorded.existsSync()) return null;
    final named = recorded.renameSync(
      '${recorded.parent.path}${io.Platform.pathSeparator}'
      '${voiceFileName(seconds, _clock())}',
    );
    return (named.path, seconds);
  }

  /// Stops recording and throws the recording away.
  Future<void> cancelVoice() async {
    final path = _recordingTo;
    if (path == null) return;
    _recordingTo = null;
    _recordingSince = null;
    await _voice?.cancel();
    final recorded = io.File(path);
    if (recorded.existsSync()) recorded.deleteSync();
    notifyListeners();
  }

  /// The recording being played, if one is.
  String? get playingVoice {
    final until = _playingUntil;
    return until != null && _clock().isBefore(until) ? _playing : null;
  }

  /// Plays a voice message, or stops it if it is the one playing.
  /// [seconds] is how long it runs.
  Future<void> toggleVoice(String path, {int seconds = 0}) async {
    final voice = _voice;
    if (voice == null) return;
    if (playingVoice == path) {
      await voice.stopPlaying();
      _playing = null;
    } else if (await voice.play(path)) {
      _playing = path;
      _playingUntil = _clock().add(Duration(seconds: seconds + 1));
    }
    notifyListeners();
  }

  void answerFile(String id, {required bool accept}) =>
      _directory.answerFile(id, accept: accept);
  void cancelFile(String id) => _directory.cancelFile(id);
  void pauseFile(String id, {required bool paused}) =>
      _directory.pauseFile(id, paused: paused);
  bool get hasFastLink => _directory.hasFastLink;

  /// Who each radio reaches and what is waiting on it, as it changes.
  ValueListenable<LinkTraffic>? get linkTraffic => _directory.linkTraffic;

  /// Whether a setting or protection the screens show really does
  /// something yet. One that does not is marked, and is never shown as on.
  bool works(Object feature) =>
      _directory.works(feature) &&
      // A place can only be sent from a device that can find one.
      (feature != Extra.shareLocation || canLocate);

  /// What the app can see when links fail together, or null when they are
  /// working.
  LinkTroubleReport? get linkTrouble =>
      _linkTrouble?.value ?? _directory.linkTrouble;

  bool get canRestartRadios => _directory.canRestartRadios;

  /// Stops every radio and starts them again.
  void restartRadios() => _directory.restartRadios();

  // Spaces

  List<Space> get spaces => _spaces?.joined ?? const [];
  Space space(String id) => spaces.firstWhere((s) => s.id == id);
  bool isJoined(String spaceId) => spaces.any((s) => s.id == spaceId);

  /// The space shown on the Spaces tab. Public channels open on their own
  /// screen, so they are never the selected space.
  Space? get selectedSpace {
    final selected = _spaces?.selectedId;
    for (final s in spaces) {
      if (s.id == selected && !s.isBroadcast) return s;
    }
    for (final s in spaces) {
      if (!s.isBroadcast) return s;
    }
    return null;
  }

  void selectSpace(String id) => _spaces?.select(id);

  List<Space> get discoverableSpaces => _spaces?.discoverable ?? const [];

  /// A space the user has joined or can see nearby, or null.
  Space? findSpace(String id) {
    for (final s in spaces.followedBy(discoverableSpaces)) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Public spaces whose name or description contains [query].
  List<Space> searchPublicSpaces(String query) {
    final needle = query.trim().toLowerCase();
    return [
      for (final s in discoverableSpaces)
        if (needle.isEmpty ||
            s.name.toLowerCase().contains(needle) ||
            s.description.toLowerCase().contains(needle))
          s,
    ];
  }

  /// Joins a space the user was invited to, or a public one nearby. A
  /// private space nobody invited them to never gets here.
  bool joinSpace(String spaceId) => _spaces?.join(spaceId) ?? false;

  /// Leaves a space. False if the core refused, and the user is still in.
  bool leaveSpace(String spaceId) => _spaces?.leave(spaceId) ?? false;

  List<SpaceInvite> get spaceInvites => _spaces?.invites ?? const [];

  /// Makes a space. Returns its id, or null if it could not be made.
  String? createSpace(String name, SpaceKind kind, {String description = ''}) =>
      _spaces?.create(name, kind, description: description);

  bool inviteToSpace(String spaceId, String personId) =>
      _spaces?.invite(spaceId, personId) ?? false;
  String? spaceInviteLink(String spaceId, {Duration? lasts}) =>
      _spaces?.inviteLink(spaceId, lasts: lasts);

  /// What a pasted invite is for, without joining. Null if it is not one.
  InviteCheck? checkInvite(String pasted) =>
      _spaces?.checkLink(_spaceLink.firstMatch(pasted)?.group(0) ?? pasted);

  /// Whether the text holds a space's invite that has run out.
  bool inviteHasRunOut(String pasted) => checkInvite(pasted)?.expired ?? false;
  String? joinSpaceByLink(String pasted) =>
      _spaces?.joinByLink(_spaceLink.firstMatch(pasted)?.group(0) ?? pasted);
  List<Person> spaceMembers(String spaceId) =>
      _spaces?.members(spaceId) ?? const [];

  /// The people the user can invite or message directly.
  List<Person> get contacts => [
    for (final chat in chats) ?findPerson(chat.personId),
    // A deleted chat is off the list, but the person is still a contact.
    for (final id in _directory.hiddenChats) ?findPerson(id),
  ];

  /// Remembers [channelId] as the open channel and clears its unread count.
  /// How many were unread just before is kept for the "New messages" line.
  void openChannel(String spaceId, String channelId) {
    final unread = spaces
        .where((s) => s.id == spaceId)
        .expand((s) => s.channels.values.expand((list) => list))
        .where((c) => c.id == channelId)
        .firstOrNull
        ?.unread;
    _newWhenOpened[channelId] = unread ?? 0;
    _spaces?.openChannel(spaceId, channelId);
  }

  final Map<String, int> _newWhenOpened = {};

  /// How many messages from others were new when [channelId] was last
  /// opened.
  int newWhenOpened(String channelId) => _newWhenOpened[channelId] ?? 0;

  Channel channel(String spaceId, String channelId) =>
      space(spaceId).channels.values
          .expand((list) => list)
          .firstWhere((c) => c.id == channelId);

  List<ChannelMessage> channelMessages(String channelId) =>
      _spaces?.messages(channelId) ?? const [];

  String? pinnedMessage(String channelId) => _spaces?.pinned(channelId);
  String? pinnedMessageId(String channelId) => _spaces?.pinnedId(channelId);

  /// Pins a message to the top of its channel, or takes it down. Only the
  /// space's owner can.
  void setPinned(String channelId, String messageId, {required bool on}) =>
      _spaces?.setPinned(channelId, messageId, on: on);

  /// Returns why the channel refused it, if one of its rules did.
  Refused? sendChannelText(String channelId, String text, {String? replyTo}) {
    final refused = _spaces?.sendText(channelId, text, replyTo: replyTo);
    if (refused == null && text.trim().isNotEmpty) _backOnSend();
    return refused;
  }

  /// Changes the words of a comment the user wrote under a public post.
  ({bool changed, Refused? refused}) editComment(
    String spaceId,
    String commentId,
    String text,
  ) =>
      _spaces?.editComment(spaceId, commentId, text) ??
      (changed: false, refused: null);

  /// Changes the words of a message the user wrote in a channel.
  ({bool changed, Refused? refused}) editChannelText(
    String channelId,
    String messageId,
    String text,
  ) =>
      _spaces?.editText(channelId, messageId, text) ??
      (changed: false, refused: null);

  /// Sets the owner's rules for a channel: slow mode, no links, and
  /// whether only the owner and admins write there.
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
      _spaces?.setChannelRules(
        spaceId,
        channelId,
        disappearSeconds: disappearSeconds,
        maxLength: maxLength,
        writerRoles: writerRoles,
        slowSeconds: slowSeconds,
        noLinks: noLinks,
        ownersOnly: ownersOnly,
      ) ??
      false;

  /// Posts a poll. False if it has no question or fewer than two choices.
  bool sendPoll(String channelId, String question, List<String> options) =>
      _spaces?.sendPoll(channelId, question, options) ?? false;

  void toggleChannelReaction(
    String channelId,
    String messageId,
    ReactionKind kind,
  ) => _spaces?.toggleReaction(channelId, messageId, kind);

  void votePoll(String channelId, String messageId, int option) =>
      _spaces?.votePoll(channelId, messageId, option);

  List<String>? callWords(String channelId) => _spaces?.callWords(channelId);

  // Public channels

  List<OwnerPost> ownerPosts(String spaceId) =>
      _spaces?.posts(spaceId) ?? const [];

  void togglePostReaction(String spaceId, String postId, ReactionKind kind) =>
      _spaces?.togglePostReaction(spaceId, postId, kind);

  /// Whether a message or post can be given any emoji, not only the heart
  /// and agree.
  bool get canReactWithAnyEmoji => _spaces?.anyEmojiReactions ?? false;

  /// Gives a channel message one emoji, or takes it back. Anything that
  /// is not one emoji is ignored.
  void toggleChannelEmoji(String channelId, String messageId, String emoji) {
    if (!isOneEmoji(emoji)) return;
    _usedEmoji(emoji);
    _spaces?.toggleEmojiReaction(channelId, messageId, emoji);
  }

  /// The same, for a public channel's post.
  void togglePostEmoji(String spaceId, String postId, String emoji) {
    if (!isOneEmoji(emoji)) return;
    _usedEmoji(emoji);
    _spaces?.togglePostEmojiReaction(spaceId, postId, emoji);
  }

  List<ChannelMessage> postComments(String spaceId, String postId) =>
      _spaces?.comments(spaceId, postId) ?? const [];

  void sendComment(String spaceId, String postId, String text) =>
      _spaces?.sendComment(spaceId, postId, text);

  bool canComment(String spaceId) => _spaces?.canComment(spaceId) ?? false;

  // Running a space. See [SpaceBook] for who may do what.

  Map<String, SpaceRole> memberRoles(String spaceId) =>
      _spaces?.roles(spaceId) ?? const {};

  bool editSpace(String spaceId, {String? name, String? description}) =>
      _spaces?.edit(spaceId, name: name, description: description) ?? false;

  String? addChannel(
    String spaceId,
    String name, {
    bool info = false,
    bool voice = false,
  }) => _spaces?.addChannel(spaceId, name, info: info, voice: voice);

  /// Mutes or deafens a member in a space's voice rooms, or lets them be.
  bool setVoiceRule(
    String spaceId,
    String memberId, {
    bool mute = false,
    bool deafen = false,
  }) =>
      _spaces?.setVoiceRule(spaceId, memberId, mute: mute, deafen: deafen) ??
      false;

  bool renameChannel(String spaceId, String channelId, String name) =>
      _spaces?.renameChannel(spaceId, channelId, name) ?? false;

  bool removeChannel(String spaceId, String channelId) =>
      _spaces?.removeChannel(spaceId, channelId) ?? false;

  /// Makes a member an admin, or takes that back. Owner only. False if
  /// the core refused.
  bool setAdmin(String spaceId, String personId, {required bool admin}) =>
      _spaces?.setAdmin(spaceId, personId, admin: admin) ?? false;

  /// Tells a member to keep quiet for a while, or with 0 lets them speak.
  /// False if the core refused.
  bool timeOutMember(String spaceId, String personId, int seconds) =>
      _spaces?.timeOut(spaceId, personId, seconds) ?? false;

  bool resetInviteLinks(String spaceId) =>
      _spaces?.resetInviteLinks(spaceId) ?? false;

  /// Sets the name the user goes by in one space. Empty: their usual one.
  bool setNameInSpace(String spaceId, String name) =>
      _spaces?.setMyName(spaceId, name) ?? false;

  /// The name the user goes by in a space.
  String nameInSpace(String spaceId) => space(spaceId).myName ?? profileName;

  /// Deletes a space for everyone in it. Only its owner can. False if the
  /// core refused, and the space is still there.
  bool deleteSpace(String spaceId) => _spaces?.deleteSpace(spaceId) ?? false;

  /// Removes a member. Owner only. False if the core refused.
  bool removeFromSpace(String spaceId, String personId) =>
      _spaces?.removeMember(spaceId, personId) ?? false;

  /// Makes a role in a space. Returns its id, or null. Owner only.
  String? addRole(String spaceId, String name, Set<RolePower> may) =>
      _spaces?.addRole(spaceId, name, may);

  bool editRole(
    String spaceId,
    String roleId, {
    String? name,
    Set<RolePower>? may,
  }) => _spaces?.editRole(spaceId, roleId, name: name, may: may) ?? false;

  bool removeRole(String spaceId, String roleId) =>
      _spaces?.removeRole(spaceId, roleId) ?? false;

  /// Gives a member a role, or takes it back. Owner only.
  bool grantRole(
    String spaceId,
    String personId,
    String roleId, {
    required bool on,
  }) => _spaces?.grantRole(spaceId, personId, roleId, on: on) ?? false;

  /// Which roles each member of a space holds, by person id.
  Map<String, List<String>> memberRoleIds(String spaceId) =>
      _spaces?.memberRoleIds(spaceId) ?? const {};

  /// Sets the words members may not use anywhere in a space. Owner only.
  bool setBannedWords(String spaceId, List<String> words) =>
      _spaces?.setBannedWords(spaceId, words) ?? false;
  bool setWordFilter(String spaceId, bool on) =>
      _spaces?.setWordFilter(spaceId, on) ?? false;

  /// Gives a space the user owns to another member. False if refused.
  bool handOverSpace(String spaceId, String personId) =>
      _spaces?.handOver(spaceId, personId) ?? false;

  /// Takes a message in a channel down for everyone.
  void deleteChannelMessage(String channelId, String messageId) {
    final space = spaces
        .where(
          (s) =>
              s.channels.values.expand((c) => c).any((c) => c.id == channelId),
        )
        .firstOrNull;
    if (space != null) _spaces?.deleteMessage(space.id, messageId);
  }

  /// Takes a post or a comment in a public channel down for everyone.
  void deletePost(String spaceId, String postId) =>
      _spaces?.deleteMessage(spaceId, postId);

  /// Posts to a public channel. Only its owner can; for anyone else the
  /// core refuses and nothing happens.
  void postToChannel(String spaceId, String text) {
    final feed = findSpace(spaceId)?.channels.values
        .expand((c) => c)
        .firstOrNull;
    if (feed != null) _spaces?.sendText(feed.id, text);
  }

  /// The one channel of a public channel space: its feed.
  String? feedOf(String spaceId) =>
      findSpace(spaceId)?.channels.values.expand((c) => c).firstOrNull?.id;

  /// The owner puts a picture, voice message or file in a public channel.
  bool postFileToChannel(String spaceId, String path, {String caption = ''}) {
    final feed = feedOf(spaceId);
    return feed != null && sendChannelFile(feed, path, caption: caption);
  }

  /// Following a public channel is the same as having joined it.
  void setFollowing(String spaceId, bool following) =>
      following ? _spaces?.join(spaceId) : _spaces?.leave(spaceId);

  bool isMuted(String spaceId) => _spaces?.isMuted(spaceId) ?? false;
  void toggleMuted(String spaceId) => _spaces?.toggleMuted(spaceId);

  // Settings

  bool sharing(SharingSetting s) => _store.setting('sharing', s.coreName);
  void setSharing(SharingSetting s, bool on) {
    // Contacts who were shown the green dot are told it is going out,
    // while the app is still allowed to say so.
    if (s == SharingSetting.showOnline && !on) _directory.here(active: false);
    _set('sharing', s.coreName, on);
    if (s == SharingSetting.screenshots) _applyScreenshots();
    if (s == SharingSetting.showOnline && on) {
      _directory.here(active: _onScreen);
    }
  }

  /// The contact this person shares a name with, if they are not that
  /// contact.
  String? sameNameAs(String id) => _directory.sameNameAs(id);

  /// What the app keeps on this device and how much room it takes,
  /// counted now.
  StorageReport get storage {
    final (carried, carriedBytes) = _directory.carrying;
    final (_, store) = _filesIn(
      _store.folder,
      except: {_directory.receivedDir, _voiceDir},
    );
    final (received, receivedBytes) = _filesIn(_directory.receivedDir);
    final (voice, voiceBytes) = _filesIn(_voiceDir);
    return StorageReport(
      storeBytes: store,
      receivedFiles: received,
      receivedBytes: receivedBytes,
      voiceFiles: voice,
      voiceBytes: voiceBytes,
      carriedMessages: carried,
      carriedBytes: carriedBytes,
    );
  }

  /// How many files are under [folder] and how big they are together,
  /// leaving out anything under [except]. A folder that cannot be read
  /// counts as empty.
  static (int, int) _filesIn(String? folder, {Set<String?> except = const {}}) {
    if (folder == null) return (0, 0);
    final skipped = [
      for (final other in except)
        if (other != null && other != folder) io.Directory(other).absolute.path,
    ];
    var (count, bytes) = (0, 0);
    try {
      for (final entry in io.Directory(folder).listSync(recursive: true)) {
        if (entry is! io.File) continue;
        final path = entry.absolute.path;
        if (skipped.any(
          (other) => path.startsWith('$other${io.Platform.pathSeparator}'),
        )) {
          continue;
        }
        count++;
        bytes += entry.lengthSync();
      }
    } on io.FileSystemException {
      // Not there, or not readable. Nothing to count.
    }
    return (count, bytes);
  }

  /// Passes one of the user's contacts on to another.
  bool sendContact(String chatId, String contactId) =>
      _directory.sendCard(chatId, contactId);

  // Places

  /// Whether this device can say where it is.
  bool get canLocate => _locator != null;

  /// Works out where the device is, for a place the user is about to send.
  Future<Located> locate() async =>
      await _locator?.locate() ?? const Located.not(NoPlace.unknown);

  /// Opens the device's settings for location.
  Future<void> openLocationSettings() async => _locator?.openSettings();

  /// Shows a place in the map app, or on a PC in the browser. False if
  /// there was nothing to show it in.
  Future<bool> openMap(Place place) async =>
      await _locator?.openMap(place) ?? false;

  /// Whether a map opens as a web page, which then learns the place.
  bool get mapsInBrowser => _locator?.mapsInBrowser ?? isPc;

  /// Sends where the user is to the person in a chat.
  bool sendLocation(String chatId, Place place) =>
      place.sound && _directory.sendLocation(chatId, place);

  /// Posts where the user is in a channel. Returns why the channel
  /// refused it, if one of its rules did; sent is false if it did not go.
  ({bool sent, Refused? refused}) sendChannelLocation(
    String channelId,
    Place place,
  ) {
    if (!place.sound || _spaces == null) return (sent: false, refused: null);
    return _spaces.sendLocation(channelId, place);
  }

  // Emoji and stickers

  /// The user's stickers and what the emoji picker remembers, sealed in
  /// the vault. Where there is no vault, the design kit, in memory only.
  late final StickerBook _stickerBook = StickerBook(
    switch (_store) {
      final CoreStore store => store.stickers,
      _ => MemoryStickerVault(),
    },
    looseFolder: switch (_store.folder) {
      final folder? => '$folder${io.Platform.pathSeparator}stickers',
      null => null,
    },
  );

  /// The user's sticker packs, favourites and emoji choices, to read.
  /// Change them through the methods here, so screens hear of it.
  StickerBook get stickerBook => _stickerBook;

  /// Emoji the user chose lately, newest first.
  List<String> get recentEmoji => _stickerBook.recentEmoji;

  /// Notes that the user chose [emoji], for [recentEmoji].
  void choseEmoji(String emoji) => _usedEmoji(emoji);

  void _usedEmoji(String emoji) => _stickerBook.choseEmoji(emoji);

  /// The skin tone the emoji picker shows: 0 for none, 1 light to 5 dark.
  int get emojiSkinTone => _stickerBook.skinTone;

  void setEmojiSkinTone(int tone) {
    _stickerBook.skinTone = tone;
    notifyListeners();
  }

  /// The stickers the app comes with.
  List<Sticker> get stickerPack => [
    for (final name in builtInStickers) Sticker.builtIn(name),
  ];

  /// Whether the user can keep stickers of their own on this device.
  bool get canKeepStickers => true;

  /// The stickers the user has kept, pack by pack.
  List<Sticker> get myStickers => _stickerBook.mine;

  /// The user's sticker packs, in their order.
  List<StickerPack> get stickerPacks => _stickerBook.packs;

  /// The user's favourite stickers, of either kind.
  List<Sticker> get favouriteStickers => _stickerBook.favourites;

  /// Makes a sticker from the picture or GIF at [path] and keeps it, in
  /// [packId] or the first pack. False if it cannot be made into one.
  Future<bool> keepStickerFrom(String path, {String? packId}) async {
    final Uint8List? image;
    try {
      image = await prepareSticker(path);
    } on io.FileSystemException {
      return false;
    }
    return image != null && keepStickerImage(image, packId: packId);
  }

  /// Keeps a sticker the user made, in [packId] or the first pack.
  bool keepStickerImage(Uint8List image, {String? packId}) {
    if (!_stickerBook.keep(image, packId: packId)) return false;
    notifyListeners();
    return true;
  }

  /// Keeps a sticker of someone else's, in [packId] or the first pack.
  /// One the app comes with is everyone's already.
  bool keepSticker(Sticker sticker, {String? packId}) {
    final image = sticker.image;
    return image != null && keepStickerImage(image, packId: packId);
  }

  /// Whether the user has kept this sticker.
  bool keepsSticker(Sticker sticker) => _stickerBook.holds(sticker);

  /// Forgets a sticker of the user's own, wherever it is.
  void forgetSticker(Sticker sticker) {
    _stickerBook.forget(sticker);
    notifyListeners();
  }

  bool isFavouriteSticker(Sticker sticker) => _stickerBook.isFavourite(sticker);

  /// Makes [sticker] a favourite or not. One of someone's own is kept
  /// too. False if it could not be.
  bool setFavouriteSticker(Sticker sticker, bool favourite) {
    final done = _stickerBook.setFavourite(sticker, favourite);
    notifyListeners();
    return done;
  }

  void moveFavouriteSticker(Sticker sticker, int index) {
    _stickerBook.moveFavourite(sticker, index);
    notifyListeners();
  }

  /// Makes a sticker pack and gives back its id, or null if there are as
  /// many as there may be.
  String? createStickerPack(String name) {
    final id = _stickerBook.createPack(name);
    notifyListeners();
    return id;
  }

  void renameStickerPack(String id, String name) {
    _stickerBook.renamePack(id, name);
    notifyListeners();
  }

  /// Deletes the pack and the stickers in it.
  void deleteStickerPack(String id) {
    _stickerBook.deletePack(id);
    notifyListeners();
  }

  void moveStickerPack(String id, int index) {
    _stickerBook.movePack(id, index);
    notifyListeners();
  }

  /// Moves a sticker of the user's own to [index] in the pack [to].
  void moveSticker(Sticker sticker, String to, {int? index}) {
    _stickerBook.moveSticker(sticker, to, index: index);
    notifyListeners();
  }

  /// Sends a sticker to the person in a chat.
  bool sendSticker(String chatId, Sticker sticker) =>
      chatId != savedMessagesId && _directory.sendSticker(chatId, sticker);

  /// Whether stickers can be posted in channels.
  bool get canSendChannelStickers => _spaces?.canSendStickers ?? false;

  /// Posts a sticker in a channel. Returns why the channel refused it, if
  /// one of its rules did; sent is false if it did not go.
  ({bool sent, Refused? refused}) sendChannelSticker(
    String channelId,
    Sticker sticker,
  ) => _spaces?.sendSticker(channelId, sticker) ?? (sent: false, refused: null);

  /// What can be done with a card: ask the person on it, or nothing,
  /// because they are known already or are the user.
  CardState cardState(DirectCard card) {
    if (card.personId == myId) return CardState.you;
    if (_directory.find(card.personId)?.isContact ?? false) {
      return CardState.inChats;
    }
    return hasOutgoingRequest(card.personId)
        ? CardState.asked
        : CardState.canAsk;
  }

  /// Asks the person on a card for a chat. They are asked like anyone.
  bool askFromCard(DirectCard card) {
    final asked = _directory.requestByLink(
      'dnet:id/${card.identity}',
      knownAs: card.name,
    );
    return asked == LinkRequest.sent;
  }

  /// How long messages in a chat live, in seconds. Nought: for good.
  int chatTimer(String chatId) => _directory.timerFor(chatId);

  /// Sets it for both people in the chat, for what is written from now.
  /// Deletes messages in a chat from this device only.
  void deleteForMe(String chatId, List<String> ids) =>
      _directory.deleteForMe(chatId, ids);

  /// Deletes the user's own recent messages for everyone.
  bool deleteForEveryone(String chatId, List<String> ids) =>
      _directory.deleteForEveryone(chatId, ids);

  void clearChat(String chatId) => _directory.clearChat(chatId);
  void deleteChat(String chatId) => _directory.deleteChat(chatId);

  bool setChatTimer(String chatId, int seconds) =>
      _directory.setTimer(chatId, seconds);

  /// The user is writing in a chat.
  void typingIn(String chatId) => _directory.typing(chatId);

  /// Whether that person is writing to the user right now.
  bool isTyping(String id) => _directory.isTyping(id);

  /// Whether the app is in front of the user. Called when that changes,
  /// and again from time to time while it stays in front.
  void onScreen(bool active) {
    _onScreen = active;
    _directory.here(active: active);
  }

  bool _onScreen = false;

  bool device(DeviceSetting s) => _store.setting('device', s.coreName);
  void setDevice(DeviceSetting s, bool on) {
    _set('device', s.coreName, on);
    if (s == DeviceSetting.autoDelete && on) tidyUp();
  }

  bool safety(SafetySetting s) => _store.setting('safety', s.coreName);
  void setSafety(SafetySetting s, bool on) => _set('safety', s.coreName, on);

  /// Who may send the user a chat request.
  RequestsFrom get requestsFrom {
    final name = _store.choice('requests_from');
    return RequestsFrom.values.where((r) => r.coreName == name).firstOrNull ??
        RequestsFrom.everyone;
  }

  set requestsFrom(RequestsFrom choice) {
    _store.setChoice('requests_from', choice.coreName);
    notifyListeners();
  }

  /// The times the app can be left out of sight before it locks.
  static const lockAfterChoices = [
    Duration.zero,
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
  ];

  /// How long the app may be out of sight before it locks, when there is
  /// a passcode. Nought: at once.
  Duration get lockAfter {
    final minutes = int.tryParse(_store.choice('auto_lock'));
    return minutes == null
        ? const Duration(minutes: 1)
        : Duration(minutes: minutes);
  }

  set lockAfter(Duration after) {
    if (!lockAfterChoices.contains(after)) return;
    _store.setChoice('auto_lock', '${after.inMinutes}');
    notifyListeners();
  }

  /// Whether this device can keep the app out of screenshots, so the
  /// switch for allowing them does something.
  bool get canBlockScreenshots => _screenshots != null;

  bool link(LinkSetting s) => _store.setting('links', s.coreName);
  void setLink(LinkSetting s, bool on) {
    _set('links', s.coreName, on);
    // A link switched off stops its radio at once.
    _directory.refresh();
  }

  bool get removeLocationFromPhotos =>
      _store.setting('photos', 'remove_location');
  set removeLocationFromPhotos(bool value) {
    _set('photos', 'remove_location', value);
  }

  void _set(String group, String name, bool value) {
    if (_store.setting(group, name) == value) return;
    // Some changes are news for others, such as a photo shown or taken
    // back. Whatever the core made to send goes out.
    _directory.sendOn(_store.setSetting(group, name, value));
    notifyListeners();
  }
}

/// What came of trying a passcode.
enum Unlock {
  opened,
  wrong,

  /// It was the tenth wrong one, and the user had chosen to lose
  /// everything at that point.
  erased,
}

/// Makes the [AppState] available to the widgets below it and rebuilds them
/// when it changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// For callbacks, which act on the state but should not rebuild with it.
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
