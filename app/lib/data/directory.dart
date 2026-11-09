import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../calls/call_engine.dart';
import '../radio/link_traffic.dart';
import '../radio/lora/byte_link.dart';
import '../radio/lora/lora_radio.dart';
import '../radio/lora/radio_settings.dart';
import '../radio/lora/radio_transport.dart';
import '../radio/radio.dart';
import 'mesh.dart';
import 'models.dart';
import 'place.dart';

/// The people the user knows or can reach, and what has passed between
/// them: chat requests, direct messages and verification.
///
/// In the app this is `LiveDirectory`, backed by the Rust core and a radio.
abstract class Directory extends ChangeNotifier {
  /// Sends on whatever the core asked to have sent in [reply], to the
  /// devices in range. For things the core does that are not this
  /// directory's own, such as telling contacts of a new name.
  void sendOn(Object? reply);

  /// Null if nobody with this id is known.
  Person? find(String id);

  /// Someone's three code words for the ten minutes [at] falls in, the
  /// user's own included, and when they change next. Every device works
  /// out the same words from the key and the time. Null where there is
  /// no real key.
  ({String words, DateTime until})? codeWords(String id, DateTime at) => null;

  List<IncomingRequest> get incomingRequests;
  List<Person> get outgoingRequests;
  bool isBlocked(String id);

  /// Accepting is the only way a direct chat can start.
  void acceptRequest(String id);

  /// The other person is not told.
  void declineRequest(String id);

  /// Declines, ends any chat, and stops this person asking again.
  void blockPerson(String id);

  /// Everyone the user has blocked.
  List<Person> get blockedPeople;

  /// Lets someone blocked ask again. It does not make them a contact.
  void unblockPerson(String id);

  /// The code the user and a contact can compare from anywhere, as text to
  /// send and as words to read out. Null if they are not a contact.
  ({String code, List<String> words})? checkCode(String id);

  /// Compares a code the contact sent with this device's own. If they are
  /// the same, the contact is marked verified.
  bool checkPastedCode(String id, String pasted);

  /// Asks a nearby person for a chat. Does not open one.
  void sendRequest(String id);

  /// The user's own link: text that lets someone who is not nearby send
  /// them a chat request. It holds their public identity and nothing
  /// secret. Null before there is an identity.
  String? get myLink;

  /// A new link for sending by message: signed, good once and for a day.
  /// Every call makes a different one. Null before there is an identity.
  String? newInviteLink();

  /// Sends a chat request to whoever [link] belongs to. Like every other
  /// way in, it asks; it never opens a chat.
  /// [scanned] says the link was read off the other person's own screen
  /// with the camera, which verifies them once they accept.
  LinkRequest requestByLink(
    String link, {
    bool scanned = false,
    String? knownAs,
  });

  /// Passes one contact on to another as a card. False if either is not
  /// a contact, or they are the same person.
  bool sendCard(String chatId, String contactId);

  /// The user scanned the code of someone who is already a contact. They
  /// are verified if it is the identity held for them. Returns whether.
  bool verifyScanned(String link);
  void cancelOutgoingRequest(String id);

  List<ChatSummary> get chats;
  List<DirectItem> thread(String chatId);

  /// The user's own profile photo or GIF, if they set one.
  Uint8List? get myPhoto => null;

  /// Sets the user's profile photo, already made small. False if refused.
  bool setMyPhoto(Uint8List photo) => false;

  /// Takes the user's profile photo away, for everyone who had it.
  void clearMyPhoto() {}

  /// Asks someone to chat whose short code the user scanned. They were
  /// met over the radio, so their identity is known; once they accept,
  /// they count as verified, as the code came off their own screen. With
  /// [verify] false, they are asked like anyone and not verified.
  LinkRequest requestScanned(String id, {bool verify = true}) =>
      LinkRequest.notALink;

  /// Marks a contact verified from their key, read off their screen.
  /// False if they are not a contact.
  bool verifyKey(String id) => false;

  /// Asks the owner of a link read off their phone by tapping the two
  /// together. Once they accept they are verified, noted as by a tap.
  LinkRequest requestTapped(String link) => requestByLink(link, scanned: true);

  /// Verifies a contact from their link, read off their phone by tapping.
  /// False if it is not the identity held for them.
  bool verifyTapped(String link) => verifyScanned(link);

  /// Returns false, and sends nothing, unless the person is a contact.
  bool sendDirectText(String chatId, String text);

  /// Passes on words the user read in a channel or another chat, as a
  /// new message of theirs marked as passed on. Where they came from and
  /// who wrote them first is not said. False, and nothing sent, unless
  /// the person is a contact.
  bool forwardText(String chatId, String text) => sendDirectText(chatId, text);

  /// Sends where the user is to a contact. False, and nothing sent, where
  /// places cannot be sent or the person is not a contact.
  bool sendLocation(String chatId, Place place) => false;

  /// Sends a sticker to a contact. False where stickers cannot be sent,
  /// or the core refused.
  bool sendSticker(String chatId, Sticker sticker) => false;

  /// How the user tells fellow members of their spaces, in range, they
  /// are. Never [MemberStatus.offline].
  MemberStatus get myStatus => MemberStatus.online;

  /// Changes it. With [MemberStatus.invisible] nothing is sent at all.
  /// False if it could not be changed.
  bool setMyStatus(MemberStatus status) => false;

  /// Why the user said they are away, as with ".afk lunch", while they
  /// are. Empty when they gave no reason; null when they are not away.
  String? get myAway => null;

  /// Says the user is away, and why, or with null that they are back.
  /// Contacts are told, and fellow members in range. False if it could
  /// not be said.
  bool setAway(String? away) => false;

  /// Writes a copy of the picture at [path] into [folder] with what the
  /// camera noted about it taken out: where, when, and on what. Returns
  /// the copy's path, or null if it is not a kind of picture that can be
  /// cleaned. The original is not changed.
  String? cleanPhoto(String path, String folder) => null;

  /// Where files the user receives are saved, if anywhere.
  String? get receivedDir => null;

  /// How many of the user's own sealed messages are waiting here for a
  /// path to their person, and how many bytes they come to. Nothing of
  /// anyone else's is ever kept.
  (int, int) get carrying => (0, 0);

  /// How long messages in this chat live, in seconds. Nought: for good.
  int timerFor(String chatId);

  /// Sets how long what is written in this chat from now on lives, on
  /// both devices. False for a time the app does not offer.
  bool setTimer(String chatId, int seconds);

  /// Sends a poll to a contact. False if it has no question or fewer than
  /// two choices.
  bool sendDirectPoll(String chatId, String question, List<String> options);

  /// Chooses in a poll in a chat. Choosing again moves the vote.
  void voteDirectPoll(String chatId, String messageId, int option);
  void markChatRead(String id);

  /// Offers the file at [path] to a contact. Returns false, and offers
  /// nothing, if they are not a contact or the file cannot be read.
  /// With [once], it is a picture the receiver may open one time.
  bool sendFile(String chatId, String path, {bool once = false});

  /// The user has opened a picture sent to be seen once. It is deleted
  /// from this device and the sender is told.
  void viewedOnce(String id);

  /// Says yes or no to a file someone offered.
  void answerFile(String id, {required bool accept});
  void cancelFile(String id);
  void pauseFile(String id, {required bool paused});

  /// The file on its way right now, if any.
  Transfer? get transfer;

  /// If [id] goes by the same name as a different contact, that
  /// contact's id. A person is their key, so this is someone else: a
  /// contact's new device with a new key, or someone passing themselves
  /// off as them.
  String? sameNameAs(String id);

  /// The user is writing to [chatId]. The other person is told, if the
  /// user switched that on, and not for every letter.
  void typing(String chatId);

  /// Whether [id] said a moment ago that they are writing to the user.
  bool isTyping(String id);

  /// Whether the user has the app on screen. Contacts in range are told,
  /// if the user switched that on. Called again from time to time while
  /// it stays open, since what was said is only believed for a while.
  void here({required bool active});

  /// Whether a fast link for big files exists on this device. Until it
  /// does, files go over Bluetooth and the app says so.
  bool get hasFastLink;

  /// Whether a setting or protection the screens show really does
  /// something yet. [feature] is a [SharingSetting], [DeviceSetting],
  /// [LinkSetting], [LinkProtection] or [AlwaysOn]. The design shows more
  /// than is built, and the app must not claim what it does not do.
  bool works(Object feature);

  /// Calls and voice rooms, on a device that has a microphone and speaker
  /// the app can use. Null where there are none.
  CallEngine? get calls => null;

  /// People in range first, then contacts who are not.
  List<Person> get nearbyPeople;

  /// Where to draw someone on the radar, as the top-left corner of their
  /// dot on a 176 px square. Null leaves them off it.
  Offset? radarPosition(String id);

  /// Roughly how near someone in range is, from how strongly their device
  /// is heard. Null when nothing has been heard yet.
  Nearness? nearness(String id) => null;

  /// Whether the radar places anyone by distance, rather than at a steady
  /// spot.
  bool get radarByDistance => false;

  /// The mesh as this device knows it, for the Nearby maps: whom it hears
  /// itself, and whom those devices said they hear.
  Mesh get mesh => Mesh.fromPeople(nearbyPeople, nearness: nearness);

  /// Deletes messages in a chat from this device only.
  void deleteForMe(String chatId, List<String> ids) {}

  /// Deletes the user's own recent messages for everyone. False if none
  /// of them could be.
  bool deleteForEveryone(String chatId, List<String> ids) => false;

  /// Empties a chat on this device. The person stays a contact.
  void clearChat(String chatId) {}

  /// Empties a chat and takes it off the list until a new message comes.
  void deleteChat(String chatId) {}

  /// Contacts whose chat the user deleted: off the list, still contacts.
  List<String> get hiddenChats => const [];

  /// What the app can see when someone's link keeps dropping while they
  /// keep coming back. Null when links are holding.
  LinkTroubleReport? get linkTrouble => null;

  /// Who each radio reaches and what is waiting on it, as it changes.
  /// Null where there are no radios.
  ValueListenable<LinkTraffic>? get linkTraffic => null;

  /// Whether the radios can be stopped and started again from Link
  /// trouble.
  bool get canRestartRadios => false;

  /// Stops every radio and starts them again.
  void restartRadios() {}

  /// Begins the word comparison with a contact. Both devices must be in
  /// range, because the words are worked out between them.
  void startVerify(String id);

  /// The four words to compare, or null while they are not ready.
  List<String>? verifyWords(String id);

  /// Records the user's answer. Only "they match" verifies the person.
  void confirmVerify(String id, {required bool matched});

  /// The LoRa radio, where one is set up. Null elsewhere.
  LoRaRadio? get lora => null;

  /// What the user chose for the LoRa radio: which device, which band.
  RadioSettings get radioSettings => const RadioSettings();

  /// Whether this build can be given a LoRa radio at all.
  bool get canSetUpRadio => false;

  /// Sets the LoRa radio up on [endpoint], on [region], and keeps the
  /// choice. With null, forgets the radio. Returns what went wrong, or
  /// null if the device is now in place (it may still be connecting).
  Future<String?> setUpRadio(
    RadioEndpoint? endpoint, {
    RadioRegion? region,
  }) async => 'no radio can be set up here';

  /// Whether the radio that finds people nearby is working, and if not,
  /// why not.
  RadioState get radioState;

  /// Asks the user to let the app use the radio, where the device has such
  /// a question to ask.
  Future<void> allowRadio();

  /// Tries the radio again if it is not working. The user may have just
  /// switched Bluetooth on outside the app.
  void retryRadio();

  /// Looks again at who the user is and which links are switched on. Called
  /// after the identity is made and after a link switch changes.
  void refresh();

  /// Forgets everything, for Wipe.
  void reset();
}
