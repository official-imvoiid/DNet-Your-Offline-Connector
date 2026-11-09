import '../core/core_bridge.dart';
import '../design/tokens.dart';
import 'stickers.dart';

/// Who the user is on this device.
class Profile {
  const Profile({
    required this.name,
    required this.fingerprint,
    required this.spokenCode,
    required this.tone,
    this.id = '',
  });

  /// The user's signing key, which is what other people's devices know
  /// them by. Empty where there is no real key.
  final String id;

  final String name;

  /// The colour of the user's picture. Made from their key, so it is the
  /// colour other people see for them too.
  final AvatarTone tone;

  /// Sixteen hex digits in four groups. A label, not a proof.
  final String fingerprint;

  /// Two words and a number, for finding each other nearby.
  final String spokenCode;
}

/// What is kept on the device between runs: the identity and the switches.
///
/// Settings are named as the core names them: a group ("sharing", "device",
/// "links" or "photos") and a name inside it.
abstract class Store {
  /// Null until an identity has been made.
  Profile? get profile;

  /// The folder everything is kept in, or null if nothing is kept on
  /// disk.
  String? get folder => null;

  /// Makes the identity. Needs nothing but a name.
  Profile createIdentity(String name);

  /// Changes the name the user goes by. Returns what the core wants sent
  /// on, so contacts and spaces hear of it, or null if the name cannot be
  /// used.
  Object? rename(String name);

  /// Whether the name can be changed here.
  bool get canRename;

  bool setting(String group, String name);

  /// Returns what the core asks to have sent because of the change, if
  /// anything: a photo shown or taken back, for instance.
  Object? setSetting(String group, String name, bool value);

  /// A privacy choice that is not on or off, as the core names it:
  /// "requests_from" (everyone, spaces or nobody) or "auto_lock" (minutes).
  String choice(String name);
  void setChoice(String name, String value);

  /// Works for a moment on the stamp that proves work went into the
  /// user's key: the identity's, or the key made ahead of it before there
  /// is one. Returns how far along it is, from 0 to 1.
  double stampWork();

  /// Devices sharing this identity, this one included.
  int get linkedDevices;

  /// How many recovery contacts are set, out of how many are needed. Both
  /// are zero until recovery has been set up.
  (int set, int needed) get recoveryContacts;

  /// Whether an app lock passcode is set.
  bool get hasPasscode;

  /// Wrong passcodes in a row since the last right one.
  int get wrongPasscodes;

  /// Sets the passcode. If one is set already, [current] must be it.
  /// False if it is too short or [current] is wrong.
  bool setPasscode(String passcode, {String? current});

  /// Removes the passcode. False if [passcode] is not it.
  bool clearPasscode(String passcode);

  /// Tries a passcode. `erased` means the user had chosen to lose
  /// everything after ten wrong ones, and this was the tenth.
  ({bool ok, bool erased}) tryPasscode(String passcode);

  /// Deletes direct messages written before [time] from this device.
  void deleteMessagesBefore(DateTime time);

  /// Opens a new, empty store after everything was erased.
  Future<void> startAfresh();

  /// Erases everything and leaves the store as it was on first launch.
  Future<void> wipe();
}

/// Supplies the key that unlocks the vault, as 64 hex digits, or null on a
/// platform where the core guards the key itself. With [fresh], any old key
/// is thrown away and a new one made.
typedef MasterKeySource = Future<String?> Function({bool fresh});

/// The real store: the Rust core, which keeps everything encrypted on disk.
class CoreStore implements Store {
  CoreStore._(this._bridge, this._dir, this._masterKey);

  final CoreBridge _bridge;
  final String _dir;
  final MasterKeySource _masterKey;

  @override
  String? get folder => _dir;

  /// The user's own stickers, sealed in the vault with everything else.
  late final StickerVault stickers = CoreStickerVault(_bridge);

  Profile? _profile;
  Map<String, Object?> _settings = const {};

  /// Opens the vault in [dir], creating it on first launch.
  ///
  /// Throws a [CoreException] if the data cannot be opened: for example
  /// `wrong_key`, or `newer_version` when a newer app wrote it.
  static Future<CoreStore> open(
    CoreBridge bridge,
    String dir, {
    required MasterKeySource masterKey,
  }) async {
    final store = CoreStore._(bridge, dir, masterKey);
    await store._open(fresh: false);
    return store;
  }

  Future<void> _open({required bool fresh}) async {
    final key = await _masterKey(fresh: fresh);
    _bridge.call({'op': 'open', 'dir': _dir, 'master_key': ?key});
    _profile = _readProfile(_bridge.call({'op': 'profile'}));
    _settings = _bridge.call({'op': 'settings'})! as Map<String, Object?>;
  }

  static Profile? _readProfile(Object? reply) => switch (reply) {
    {
      'name': final String name,
      'fingerprint': final String fingerprint,
      'spoken_code': final String spokenCode,
      'signing_key': final String key,
    } =>
      Profile(
        name: name,
        fingerprint: fingerprint,
        spokenCode: spokenCode,
        tone: toneForKey(key),
        id: key,
      ),
    _ => null,
  };

  @override
  Profile? get profile => _profile;

  @override
  Profile createIdentity(String name) => _profile = _readProfile(
    _bridge.call({'op': 'create_identity', 'name': name}),
  )!;

  @override
  bool get canRename => true;

  @override
  Object? rename(String name) {
    final Object? reply;
    try {
      reply = _bridge.call({'op': 'set_name', 'name': name});
    } on CoreException {
      return null;
    }
    _profile = _readProfile(reply) ?? _profile;
    return reply;
  }

  @override
  bool setting(String group, String name) {
    // "photos" is one switch kept at the top level; the rest are grouped.
    if (group == 'photos') {
      return _settings['remove_location_from_photos'] as bool? ?? true;
    }
    final values = _settings[group] as Map<String, Object?>?;
    return values?[name] as bool? ?? false;
  }

  @override
  Object? setSetting(String group, String name, bool value) {
    final reply =
        _bridge.call({
              'op': 'set_setting',
              'group': group,
              'name': name,
              'value': value,
            })!
            as Map<String, Object?>;
    _settings = reply;
    return reply;
  }

  @override
  String choice(String name) => '${_settings[name] ?? _choices[name] ?? ''}';

  /// What the core starts each choice at.
  static const _choices = {'requests_from': 'everyone', 'auto_lock': 1};

  @override
  void setChoice(String name, String value) {
    _settings =
        _bridge.call({'op': 'set_choice', 'name': name, 'value': value})!
            as Map<String, Object?>;
  }

  @override
  double stampWork() {
    try {
      if (_bridge.call({'op': 'stamp_work'})
          case {'found': final int found, 'parts': final int parts}
          when parts > 0) {
        return found / parts;
      }
    } on CoreException {
      // Nothing to work on. Done, as far as anyone waiting is concerned.
    }
    return 1;
  }

  // Linking a second device and recovery contacts are not built yet, so
  // these say what is true today: one device, no recovery set up.
  @override
  int get linkedDevices => 1;

  @override
  (int, int) get recoveryContacts => (0, 0);

  ({bool set, int wrong}) get _lock =>
      switch (_bridge.call({'op': 'lock_state'})) {
        {'set': final bool set, 'wrong': final int wrong} => (
          set: set,
          wrong: wrong,
        ),
        _ => (set: false, wrong: 0),
      };

  @override
  bool get hasPasscode => _lock.set;

  @override
  int get wrongPasscodes => _lock.wrong;

  @override
  bool setPasscode(String passcode, {String? current}) {
    try {
      _bridge.call({
        'op': 'lock_set',
        'passcode': passcode,
        'current': ?current,
      });
      return true;
    } on CoreException {
      return false;
    }
  }

  @override
  bool clearPasscode(String passcode) {
    try {
      _bridge.call({'op': 'lock_clear', 'passcode': passcode});
      return true;
    } on CoreException {
      return false;
    }
  }

  @override
  ({bool ok, bool erased}) tryPasscode(String passcode) =>
      switch (_bridge.call({'op': 'lock_check', 'passcode': passcode})) {
        {'ok': final bool ok, 'erased': final bool erased} => (
          ok: ok,
          erased: erased,
        ),
        _ => (ok: false, erased: false),
      };

  @override
  void deleteMessagesBefore(DateTime time) {
    try {
      _bridge.call({
        'op': 'purge',
        'before': time.millisecondsSinceEpoch ~/ 1000,
      });
    } on CoreException {
      // No identity yet, so no messages either.
    }
  }

  @override
  Future<void> startAfresh() async {
    _profile = null;
    _settings = const {};
    // A new key, as on first launch.
    await _open(fresh: true);
  }

  @override
  Future<void> wipe() async {
    _bridge.call({'op': 'wipe'});
    await startAfresh();
  }
}
