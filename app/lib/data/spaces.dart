import 'package:flutter/foundation.dart';

import 'models.dart';
import 'place.dart';

/// The spaces the user is in, the public ones nearby, and what is said in
/// their channels.
///
/// Spaces are separate from one-to-one chats: nothing here ever appears on
/// the Chats tab, and joining a space gives nobody a way to message the
/// user directly.
abstract class SpaceBook extends ChangeNotifier {
  /// Tells the book who the user's contacts are. Pictures and voice
  /// messages come down by themselves only from them.
  set isContact(bool Function(String key) test) {}

  /// Tells the book how to find who is speaking in a voice room, where
  /// calls are built.
  set speakingIn(String? Function(String space, String channel) find) {}

  /// The spaces the user has joined, in the order of the rail.
  List<Space> get joined;

  /// The space shown on the Spaces tab, if the user is in any.
  String? get selectedId;
  void select(String id);

  /// Public spaces that devices nearby are sharing. Private spaces never
  /// appear here.
  List<Space> get discoverable;

  /// Invites from contacts that the user has not answered.
  List<SpaceInvite> get invites;

  /// Makes a space with the user as its owner. Returns its id, or null if
  /// it could not be made.
  String? create(String name, SpaceKind kind, {String description = ''});

  /// Joins a space the user was invited to, or a public one nearby.
  /// False if the core refused.
  bool join(String spaceId);

  /// Leaves a space, or turns down an invite to it. False if the core
  /// refused.
  bool leave(String spaceId);

  /// Invites a contact. The invite carries the space's key, so it is sealed
  /// to that one person. Returns false if they are not a contact.
  bool invite(String spaceId, String personId);

  /// An invite as text, for passing on by hand. Anyone who has it can
  /// join, for [lasts] if given (an hour to thirty days), or for good.
  String? inviteLink(String spaceId, {Duration? lasts});

  /// What an invite link is for and whether it has run out, or null if
  /// the text is not one.
  InviteCheck? checkLink(String link);

  /// Joins by a pasted invite. Returns the space's id, or null if the text
  /// is not an invite.
  String? joinByLink(String link);

  /// Someone seen in a space, who may not be a contact.
  Person? member(String id);
  List<Person> members(String spaceId);

  /// Whether the running of a space is built here.
  bool get canManage;

  /// What each member is in a space, by person id.
  Map<String, SpaceRole> roles(String spaceId);

  // Running a space. The core refuses each of these from anyone not
  // allowed to do it, and then nothing happens.

  /// Changes a space's name, its description, or both. Owner only.
  bool edit(String spaceId, {String? name, String? description});

  /// Adds a channel and returns its id. [info] makes one that only the
  /// owner and admins write in; [voice] makes a voice room. Owner only.
  String? addChannel(
    String spaceId,
    String name, {
    bool info = false,
    bool voice = false,
  });

  /// Mutes or deafens a member in the space's voice rooms, or with both
  /// false lets them be. Signed, like every other word of whoever runs the
  /// space. Owner and admins only.
  bool setVoiceRule(
    String spaceId,
    String memberId, {
    bool mute = false,
    bool deafen = false,
  }) => false;
  bool renameChannel(String spaceId, String channelId, String name);

  /// Sets the owner's rules for a channel. What is not given is left as it
  /// is. Owner only.
  bool setChannelRules(
    String spaceId,
    String channelId, {
    int? slowSeconds,
    bool? noLinks,
    bool? ownersOnly,
    int? disappearSeconds,
    int? maxLength,
    List<String>? writerRoles,
  });

  /// Makes a role and returns its id, or null if refused. Owner only.
  String? addRole(String spaceId, String name, Set<RolePower> may);

  /// Renames a role or changes what it may do. Owner only.
  bool editRole(
    String spaceId,
    String roleId, {
    String? name,
    Set<RolePower>? may,
  });

  /// Deletes a role. Owner only.
  bool removeRole(String spaceId, String roleId);

  /// Gives a member a role, or takes it back. Owner only.
  bool grantRole(
    String spaceId,
    String personId,
    String roleId, {
    required bool on,
  });

  /// Which roles each member holds, by person id.
  Map<String, List<String>> memberRoleIds(String spaceId);

  /// Sets the words and phrases members may not use anywhere in the
  /// space. Owner only.
  bool setBannedWords(String spaceId, List<String> words);

  /// Switches the word filter off, keeping the list, or on again. Owner
  /// and admins only.
  bool setWordFilter(String spaceId, bool on);
  bool removeChannel(String spaceId, String channelId);

  /// Tells a member to keep quiet for [seconds], or with 0 lets them
  /// speak again. The owner and admins can.
  bool timeOut(String spaceId, String personId, int seconds);

  /// Changes a private space's key so every invite link made before stops
  /// working. Nobody is removed. Owner only.
  bool resetInviteLinks(String spaceId);

  /// Sets what the user goes by in one space. Empty goes back to their
  /// usual name. False for a name that cannot be one.
  bool setMyName(String spaceId, String name);

  /// Deletes a space for everyone in it. Owner only.
  bool deleteSpace(String spaceId);

  /// Makes a member an admin, or no longer one. Owner only.
  bool setAdmin(String spaceId, String personId, {required bool admin});

  /// Puts someone out of a space. Owner only.
  bool removeMember(String spaceId, String personId);

  /// Gives the space to another member, who runs it from then on. The
  /// user becomes a member like any other and cannot take it back. Owner
  /// only. False if it was refused.
  bool handOver(String spaceId, String personId);

  /// Takes a message, a post or a comment down for everyone. Its writer
  /// can, and so can the owner and admins.
  void deleteMessage(String spaceId, String messageId);

  /// Remembers [channelId] as the open channel and clears its unread count.
  void openChannel(String spaceId, String channelId);

  List<ChannelMessage> messages(String channelId);

  /// What the owner has put at the top of a channel, and which message it
  /// is.
  String? pinned(String channelId);
  String? pinnedId(String channelId);

  /// Puts a message at the top of its channel, or takes it down. Only the
  /// space's owner can; for anyone else nothing happens.
  void setPinned(String channelId, String messageId, {required bool on});

  /// [replyTo] is the id of the message this answers, if any. Returns why
  /// it was refused, if one of the channel's rules refused it.
  Refused? sendText(String channelId, String text, {String? replyTo});

  /// Posts a file, a picture or a voice message in a channel. [caption]
  /// is any words with it. False if it was refused.
  bool sendFile(
    String channelId,
    String path, {
    required FileKind kind,
    int seconds = 0,
    String caption = '',
  });

  /// Passes on words the user read in another channel or a chat, marked
  /// as passed on. Nobody is called on by it. The channel's rules hold as
  /// for anything written there.
  Refused? forwardText(String channelId, String text) =>
      sendText(channelId, text);

  /// Posts where the user is. Not sent where places cannot be posted;
  /// [refused] says which of the channel's rules stopped it, if one did.
  ({bool sent, Refused? refused}) sendLocation(String channelId, Place place) =>
      (sent: false, refused: null);

  /// How each member of a space says they are, by person id. Anyone out
  /// of range, or invisible, is offline. The user is as they chose.
  Map<String, MemberStatus> statuses(String spaceId) => const {};

  /// The user is writing in [channelId]. Members in range are told, if
  /// the user switched that on, and not for every letter.
  void typingIn(String channelId) {}

  /// The person ids of whoever said a moment ago that they are writing
  /// in [channelId].
  List<String> typingNow(String channelId) => const [];

  /// Sets what the owner says to everyone who joins, the rules, or both.
  /// Empty takes one away. Owner only. False if it was refused.
  bool setWelcome(String spaceId, {String? welcome, String? rules}) => false;

  /// Sets the space's icon, a small picture or GIF, or with null takes it
  /// away. Members and people nearby are given it. Owner only. False if
  /// it was refused.
  bool setIcon(String spaceId, Uint8List? icon) => false;

  /// Sets what a member is called in this space, for everyone. Empty lets
  /// them go by their own name again. The owner and admins can; an admin
  /// not for the owner or another admin. False if it was refused.
  bool setNickname(String spaceId, String personId, String name) => false;

  /// Asks members in range for the file a message carries.
  void fetchFile(String channelId, String messageId);

  /// Copies the file a message carries to [dir]. Returns where it went.
  String? saveFile(String channelId, String messageId, String dir);

  /// Changes the words of a message the user wrote. Not a poll. The
  /// channel's rules hold as for a new message; [refused] says which one
  /// stood in the way, if it was one of them.
  ({bool changed, Refused? refused}) editText(
    String channelId,
    String messageId,
    String text,
  );
  void toggleReaction(String channelId, String messageId, ReactionKind kind);

  /// Whether a message can be given any emoji, not only the heart and
  /// agree.
  bool get anyEmojiReactions => false;

  /// Gives a message one emoji as a reaction, or takes it back.
  void toggleEmojiReaction(String channelId, String messageId, String emoji) {}

  /// Whether stickers can be posted in channels.
  bool get canSendStickers => false;

  /// Posts a sticker. Not sent where stickers cannot be posted; [refused]
  /// says which of the channel's rules stopped it, if one did.
  ({bool sent, Refused? refused}) sendSticker(
    String channelId,
    Sticker sticker,
  ) => (sent: false, refused: null);

  /// Posts a poll. False if it has no question or fewer than two choices.
  bool sendPoll(String channelId, String question, List<String> options);

  /// Chooses in a poll. Choosing again moves the vote.
  void votePoll(String channelId, String messageId, int option);

  /// The posts of a public channel. Only its owner writes them.
  List<OwnerPost> posts(String spaceId);
  void togglePostReaction(String spaceId, String postId, ReactionKind kind);

  /// Gives a public channel's post one emoji, or takes it back.
  void togglePostEmojiReaction(String spaceId, String postId, String emoji) {}

  /// What readers have said under a post, oldest first.
  List<ChannelMessage> comments(String spaceId, String postId);
  void sendComment(String spaceId, String postId, String text);

  /// Changes the words of a comment the user wrote.
  ({bool changed, Refused? refused}) editComment(
    String spaceId,
    String commentId,
    String text,
  );

  /// Whether the user can comment in this public channel. They can once
  /// they follow it.
  bool canComment(String spaceId);

  bool isMuted(String spaceId);
  void toggleMuted(String spaceId);

  /// The four words everyone in a voice room should see, or null when there
  /// is no call.
  List<String>? callWords(String channelId);

  /// Reads everything again from where it is kept.
  void refresh();

  /// Forgets everything, for Wipe.
  void reset();
}
