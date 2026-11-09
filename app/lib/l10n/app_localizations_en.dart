// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'DNet';

  @override
  String get back => 'Back';

  @override
  String get cancel => 'Cancel';

  @override
  String get riskyFileWarning =>
      'This kind of file can run a program. Only open it if you trust who sent it and expected it.';

  @override
  String get linkCheckTitle => 'Before you open this link';

  @override
  String get linkGoesTo => 'This link really goes to';

  @override
  String linkTrackingRemoved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracking parts taken off',
      one: '1 tracking part taken off',
    );
    return '$_temp0';
  }

  @override
  String get linkWarnLookalike =>
      'The name uses letters from another alphabet that look like normal ones. It may be pretending to be a site you know.';

  @override
  String get linkWarnHiddenName =>
      'The words before the @ are not where it goes. It goes to the site shown above.';

  @override
  String get linkWarnNumbersOnly =>
      'The address is only numbers, with no name you can check.';

  @override
  String get linkWarnNotPrivate =>
      'It starts with http://, so what you send there is not private.';

  @override
  String get linkCheckNote =>
      'Only open links from people you trust. DNet never opens or previews links by itself. To visit it, copy it into your browser.';

  @override
  String get copyCleanLink => 'Copy the link';

  @override
  String get linkLeavesApp =>
      'Opening it leaves DNet. Your browser shows the page, and the site can see that you visited.';

  @override
  String linkWarnDisguised(String shown) {
    return 'The words \"$shown\" look like a different link. It really goes to the site shown above.';
  }

  @override
  String get linkOpenNote =>
      'Only open links from people you trust. DNet never opens or previews a link by itself.';

  @override
  String get openLink => 'Open in browser';

  @override
  String get linkNotOpened =>
      'The link could not be opened here. Copy it into your browser instead.';

  @override
  String get webLinkCopied => 'Link copied.';

  @override
  String get linksNotAllowedHere =>
      'Links cannot be sent here. The owner keeps links out of this channel.';

  @override
  String get writingPreview => 'Preview';

  @override
  String get formatHelp => 'Formatting help';

  @override
  String get formatHelpHint =>
      'You can use **bold**, lists, quotes and more. See how';

  @override
  String get formatHelpTitle => 'Formatting';

  @override
  String get formatHelpBody =>
      'Type these marks around your words. They change once sent.';

  @override
  String get formatSamples =>
      '**bold**\n*italic*\n~~struck out~~\n`code`\n||spoiler||\n# Heading\n- a list\n1. a numbered list\n> a quote\n[words](example.com)';

  @override
  String get formatSampleCode => 'a block of code';

  @override
  String get formatSafeNote =>
      'Marks never show pictures or open anything. A link still says where it goes before it opens.';

  @override
  String get awayMark => 'Away';

  @override
  String awayMarkWith(String note) {
    return 'Away: $note';
  }

  @override
  String awayNow(String note) {
    return 'You are away: $note. Anyone who calls on you or messages you is told.';
  }

  @override
  String get awayNowPlain =>
      'You are away. Anyone who calls on you or messages you is told.';

  @override
  String get awayNotSet => 'You could not be marked away.';

  @override
  String youAreAway(String note) {
    return 'You are away: $note';
  }

  @override
  String get youAreAwayPlain => 'You are away';

  @override
  String get imBack => 'I\'m back';

  @override
  String personAway(String name, String note) {
    return '$name is away: $note';
  }

  @override
  String personAwayPlain(String name) {
    return '$name is away';
  }

  @override
  String get mentionEveryoneDetail => 'Everyone here';

  @override
  String get mentionHereDetail => 'Everyone in range now';

  @override
  String get mentionRoleDetail => 'Role';

  @override
  String personTag(String tag) {
    return 'Tag $tag, from their key';
  }

  @override
  String get share => 'Share';

  @override
  String shareContactWarnTitle(String who, String to) {
    return 'Share $who\'s contact with $to?';
  }

  @override
  String shareContactWarnBody(String to) {
    return '$to will be able to ask them for a chat. Only share it if they would be happy with that.';
  }

  @override
  String get close => 'Close';

  @override
  String get verified => 'Verified';

  @override
  String get notVerified => 'Not verified';

  @override
  String get you => 'You';

  @override
  String get notBuiltYet => 'This part is not built yet.';

  @override
  String get startupFailedTitle => 'DNet could not open your data';

  @override
  String get startupNewerVersion =>
      'It was saved by a newer version of DNet. Update the app to open it. Nothing has been changed.';

  @override
  String get startupWrongKey =>
      'The key that protects it could not be read on this device. Nothing has been changed.';

  @override
  String get startupOtherFailure =>
      'Something went wrong while reading it. Nothing has been changed.';

  @override
  String get tabChats => 'Chats';

  @override
  String get tabSpaces => 'Spaces';

  @override
  String get tabNearby => 'Nearby';

  @override
  String get tabYou => 'You';

  @override
  String get mainNavigation => 'Main';

  @override
  String get welcomeTagline => 'Chat with people around you. No signal needed.';

  @override
  String get welcomePoint1Title => 'Works without internet';

  @override
  String welcomePoint1Body(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'Devices nearby pass messages along.',
      'other': 'Phones nearby pass messages along.',
    });
    return '$_temp0';
  }

  @override
  String get welcomePoint2Title => 'Private by default';

  @override
  String get welcomePoint2Body => 'No phone number. No account. Encrypted.';

  @override
  String get welcomePoint3Title => 'Sends big files fast';

  @override
  String welcomePoint3Body(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'Straight from device to device over Wi-Fi.',
      'other': 'Straight from phone to phone over Wi-Fi.',
    });
    return '$_temp0';
  }

  @override
  String get yourName => 'Your name';

  @override
  String get random => 'Random';

  @override
  String get getStarted => 'Get started';

  @override
  String get getStartedLocked => 'Do the quick check first.';

  @override
  String personCheckPrompt(String thing) {
    return 'Quick check that you are a person: tap the $thing';
  }

  @override
  String get personCheckWrong => 'Not that one. Try again.';

  @override
  String get personCheckDone => 'Checked. Thank you.';

  @override
  String get checkPadlock => 'padlock';

  @override
  String get checkCamera => 'camera';

  @override
  String get checkBookmark => 'bookmark';

  @override
  String get checkSpeechBubble => 'speech bubble';

  @override
  String welcomeFootnote(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'Your key is made on this PC and stays here.',
      'other': 'Your key is made on this phone and stays here.',
    });
    return '$_temp0';
  }

  @override
  String get search => 'Search';

  @override
  String get newChatRequest => 'New chat request';

  @override
  String chatRequestsBanner(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chat requests',
      one: '1 chat request',
    );
    return '$_temp0';
  }

  @override
  String get tapToAnswer => 'Tap to answer';

  @override
  String get savedMessages => 'Saved messages';

  @override
  String onlyOnThisPhone(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'Only on this PC',
      'other': 'Only on this phone',
    });
    return '$_temp0';
  }

  @override
  String get chatsFootnote => 'Only people you accepted can message you here.';

  @override
  String get chatsEmpty => 'No chats yet. Find someone nearby to start.';

  @override
  String get disappearingMessages => 'Disappearing messages';

  @override
  String unreadCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unread messages',
      one: '1 unread message',
    );
    return '$_temp0';
  }

  @override
  String get online => 'Online';

  @override
  String get chatRequestsTitle => 'Chat requests';

  @override
  String get requestsIntro => 'Nobody can message you until you accept.';

  @override
  String get accept => 'Accept';

  @override
  String get decline => 'Decline';

  @override
  String get block => 'Block';

  @override
  String alsoInSpace(String space) {
    return 'Also in $space';
  }

  @override
  String get noSpacesInCommon => 'No spaces in common';

  @override
  String get sentByYou => 'Sent by you';

  @override
  String get waitingForReply => 'Waiting for a reply';

  @override
  String get requestsFootnote =>
      'People you decline are not told, and must wait a while to ask again. People you block cannot ask again, even under a new name.';

  @override
  String get requestsEmpty => 'No chat requests waiting.';

  @override
  String blockConfirmTitle(String name) {
    return 'Block $name?';
  }

  @override
  String get blockConfirmBody =>
      'They will not be told, and they cannot ask again. You can unblock them later under Privacy.';

  @override
  String get newChatTitle => 'New chat';

  @override
  String get qrPlaceholder => '[Your QR code]';

  @override
  String get shareLink => 'Share link';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get scanTheirCode => 'Scan their code';

  @override
  String get scanTheirCodeDetail => 'Point your camera at their screen';

  @override
  String get findNearby => 'Find nearby';

  @override
  String get findNearbyDetail => 'Works with no internet';

  @override
  String get tapPhones => 'Tap phones together';

  @override
  String get tapPhonesDetail => 'Hold the two phones back to back';

  @override
  String get pasteInvite => 'Paste an invite link';

  @override
  String get pasteInviteDetail => 'For someone who is far away';

  @override
  String get newChatFootnote =>
      'They need to accept before either of you can send a message.';

  @override
  String verifyTitle(String name) {
    return 'Verify $name';
  }

  @override
  String verifyIntro(String name, String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'device',
      'other': 'phone',
    });
    return 'Compare these four words in person or on a call. If they match, this really is $name\'s $_temp0.';
  }

  @override
  String scanCodeInstead(String name) {
    return 'Scan $name\'s code instead';
  }

  @override
  String verifyWaiting(String name) {
    return 'Waiting for $name\'s device. You both need to be in range.';
  }

  @override
  String get wordsMatch => 'The words match';

  @override
  String get wordsDoNotMatch => 'They do not match';

  @override
  String verifyFootnote(String name) {
    return 'Until you verify, $name keeps a yellow \"Not verified\" tag.';
  }

  @override
  String get mismatchTitle => 'Do not trust this chat yet';

  @override
  String mismatchBody(String name, String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'device',
      'other': 'phone',
    });
    return 'The words did not match, so this may not be $name\'s $_temp0. $name stays not verified.';
  }

  @override
  String get ok => 'OK';

  @override
  String verifyPerson(String name) {
    return 'Not verified. Tap to verify $name.';
  }

  @override
  String callPerson(String name) {
    return 'Call $name';
  }

  @override
  String get moreOptions => 'More options';

  @override
  String get encryptedNote => 'Encrypted. Only you two can read this.';

  @override
  String get read => 'Read';

  @override
  String get playVoiceMessage => 'Play voice message';

  @override
  String get goneInOneDay => 'Gone in 1 day';

  @override
  String goneInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Gone in $days days',
      one: 'Gone in 1 day',
    );
    return '$_temp0';
  }

  @override
  String goneInHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'Gone in $hours hours',
      one: 'Gone in 1 hour',
    );
    return '$_temp0';
  }

  @override
  String goneInMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Gone in $minutes minutes',
      one: 'Gone in 1 minute',
    );
    return '$_temp0';
  }

  @override
  String get disappearingBody =>
      'What the two of you write here from now on is deleted from both devices after this long. Files, pictures and voice messages are not. It cannot stop someone copying a message first.';

  @override
  String get timerOff => 'Off: messages stay';

  @override
  String get timerHour => '1 hour';

  @override
  String get timerDay => '1 day';

  @override
  String get timerWeek => '1 week';

  @override
  String get attachOrShare => 'Attach or share';

  @override
  String get message => 'Message';

  @override
  String messagePerson(String name) {
    return 'Message $name';
  }

  @override
  String get recordVoiceMessage => 'Record a voice message';

  @override
  String get recordingVoice => 'Recording';

  @override
  String get sendVoice => 'Send';

  @override
  String get voiceMessage => 'Voice message';

  @override
  String get micUnavailable =>
      'The microphone cannot be used. Check that DNet is allowed to use it.';

  @override
  String get nearbyOnBluetooth => 'Nearby, on Bluetooth';

  @override
  String get nearbyOnWifi => 'Nearby, on Wi-Fi';

  @override
  String get typingNow => 'typing…';

  @override
  String reachedThroughHops(int count, String name) {
    return '$count hops, through $name';
  }

  @override
  String get outOfRange => 'Out of range';

  @override
  String get photo => 'Photo';

  @override
  String photoNamed(String name) {
    return 'Photo: $name';
  }

  @override
  String get photoCannotBeShown =>
      'This picture cannot be shown here. Open the file with another app.';

  @override
  String voiceMessagePreview(String duration) {
    return 'Voice message, $duration';
  }

  @override
  String get spacesNavigation => 'Spaces';

  @override
  String get findOrCreateSpace => 'Find or create a space';

  @override
  String get inviteSomeone => 'Invite someone';

  @override
  String get privateSpace => 'Private';

  @override
  String get publicSpace => 'Public';

  @override
  String membersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
    );
    return '$_temp0';
  }

  @override
  String get sectionInfo => 'Info';

  @override
  String get sectionText => 'Text';

  @override
  String get sectionVoice => 'Voice';

  @override
  String talkingCount(int count) {
    return '$count talking';
  }

  @override
  String spaceFootnote(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'Kept on members\' devices. No server.',
      'other': 'Kept on members\' phones. No server.',
    });
    return '$_temp0';
  }

  @override
  String get spacesEmpty => 'You are not in any space yet.';

  @override
  String get members => 'Members';

  @override
  String channelSubtitle(String space, int count) {
    return '$space, $count nearby';
  }

  @override
  String messageChannel(String channel) {
    return 'Message #$channel';
  }

  @override
  String heartReaction(int count) {
    return 'Heart reaction, $count';
  }

  @override
  String agreeReaction(int count) {
    return 'Agree reaction, $count';
  }

  @override
  String pollFooter(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count votes',
      one: '1 vote',
    );
    return '$_temp0. The app does not show who voted.';
  }

  @override
  String percent(int value) {
    return '$value%';
  }

  @override
  String get noMessagesYet => 'No messages yet.';

  @override
  String get pinnedMessage => 'Pinned message';

  @override
  String get shareTitle => 'Share';

  @override
  String get sharePhoto => 'Photo';

  @override
  String get shareFile => 'File';

  @override
  String get shareVoice => 'Voice';

  @override
  String get sharePoll => 'Poll';

  @override
  String get shareContact => 'Contact';

  @override
  String get contactCard => 'Contact';

  @override
  String chooseContactTitle(String name) {
    return 'Send $name a contact';
  }

  @override
  String get chooseContactBody =>
      'They get a card they can ask that person for a chat by. That person still has to say yes.';

  @override
  String get noOtherContacts =>
      'You have nobody else in your chats to pass on yet.';

  @override
  String get askToChat => 'Ask to chat';

  @override
  String get cardAsked => 'Asked. Waiting for their answer.';

  @override
  String get cardInChats => 'In your chats';

  @override
  String get cardIsYou => 'This is you';

  @override
  String get cardNotSent => 'That could not be sent.';

  @override
  String get shareLocation => 'Location';

  @override
  String get shareViewOnce => 'View once';

  @override
  String get viewOncePhoto => 'View once photo';

  @override
  String get viewOnceTapToOpen => 'Tap to open. It can be opened one time.';

  @override
  String get viewOnceNotOpened => 'Sent. Not opened yet.';

  @override
  String get viewOnceOpened => 'Opened';

  @override
  String get viewOnceWhileOpen =>
      'This picture is already deleted from this device. When you close it, it is gone. Nothing can stop someone photographing a screen.';

  @override
  String get viewOnceNotAPicture => 'View once is for pictures only.';

  @override
  String get shareCameraCode => 'Camera code';

  @override
  String get sendBigFile => 'Send a big file nearby';

  @override
  String get sendBigFileDetail => 'Goes direct at Wi-Fi speed, any size';

  @override
  String bigFileNeedsRange(String name) {
    return '$name is not in range. Big files go only when you are near each other.';
  }

  @override
  String get removeLocationFromPhotos => 'Remove location from photos';

  @override
  String get cannotCleanTitle => 'This picture may say where it was taken';

  @override
  String get cannotCleanBody =>
      'DNet can take the location out of JPEG and PNG pictures. This is another kind, so it would be sent with whatever the camera wrote into it.';

  @override
  String get sendAsItIs => 'Send as it is';

  @override
  String get sendingFile => 'Sending file';

  @override
  String fileSizeTo(String size, String name) {
    return '$size, to $name';
  }

  @override
  String megabytesPerSecond(int value) {
    return '$value MB/s';
  }

  @override
  String sentOfTotal(String sent, String total) {
    return '$sent of $total';
  }

  @override
  String aboutMinutesLeft(int minutes) {
    return 'About $minutes min left';
  }

  @override
  String stepFoundOver(String transport, String name) {
    String _temp0 = intl.Intl.selectLogic(transport, {
      'wifi': 'Found $name over Wi-Fi',
      'radio': 'Found $name over radio',
      'other': 'Found $name over Bluetooth',
    });
    return '$_temp0';
  }

  @override
  String get stepGoingOverWifi => 'Going over Wi-Fi';

  @override
  String get stepGoingOverRadio => 'Going over radio, which is slow';

  @override
  String get nearbyByRadio => 'Nearby, by radio';

  @override
  String get linkRadioChatOnly => 'Radio, chat only';

  @override
  String stepCheckedKey(String name) {
    return 'Checked $name\'s key';
  }

  @override
  String get stepSwitchedToWifi => 'Switched to Wi-Fi for speed';

  @override
  String get encryption => 'Encryption';

  @override
  String get aes256 => 'AES-256';

  @override
  String get ifTheLinkDrops => 'If the link drops';

  @override
  String get resumesByItself => 'Resumes by itself';

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Resume';

  @override
  String get paused => 'Paused';

  @override
  String voiceRoomSubtitle(String space) {
    return '$space voice room';
  }

  @override
  String get inviteToRoom => 'Invite to room';

  @override
  String get speaking => 'Speaking';

  @override
  String get listening => 'Listening';

  @override
  String get muted => 'Muted';

  @override
  String get callKey => 'Call key';

  @override
  String get callKeyNote =>
      'If everyone sees these words, nobody is listening in.';

  @override
  String get unmuteMicrophone => 'Unmute microphone';

  @override
  String get muteMicrophone => 'Mute microphone';

  @override
  String get speaker => 'Speaker';

  @override
  String get turnCameraOn => 'Turn camera on';

  @override
  String get leaveTheRoom => 'Leave the room';

  @override
  String get findSpaceTitle => 'Find a space';

  @override
  String get searchPublicSpaces => 'Search public spaces';

  @override
  String get publicAnyoneCanJoin => 'Public, anyone can join';

  @override
  String get spaceTypeChannel => 'Channel';

  @override
  String get spaceTypeCommunity => 'Community';

  @override
  String spaceTypeAndDescription(String type, String description) {
    return '$type. $description';
  }

  @override
  String get open => 'Open';

  @override
  String get join => 'Join';

  @override
  String findSpaceFootnote(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'Shared by devices around you. There is no central list.',
      'other': 'Shared by phones around you. There is no central list.',
    });
    return '$_temp0';
  }

  @override
  String get noSpacesFound => 'No public spaces match.';

  @override
  String get haveAnInvite => 'Have an invite?';

  @override
  String get privateSpacesHidden => 'Private spaces never show up in search.';

  @override
  String get pasteLink => 'Paste link';

  @override
  String get scanCode => 'Scan code';

  @override
  String get createSpace => 'Create a space';

  @override
  String get publicChannel => 'Public channel';

  @override
  String get signedByOwner => 'Signed by the owner';

  @override
  String commentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count comments',
      one: '1 comment',
    );
    return '$_temp0';
  }

  @override
  String get followFootnote =>
      'You follow privately. The owner cannot see who follows.';

  @override
  String get following => 'Following';

  @override
  String get follow => 'Follow';

  @override
  String get mute => 'Mute';

  @override
  String get scanACode => 'Scan a code';

  @override
  String peopleInRange(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'people in range',
      one: 'person in range',
    );
    return '$_temp0';
  }

  @override
  String get noInternetNeeded => 'No internet needed';

  @override
  String get linkWifiFast => 'Wi-Fi, fast';

  @override
  String get linkBluetoothChatOnly => 'Bluetooth, chat only';

  @override
  String get chat => 'Chat';

  @override
  String get request => 'Request';

  @override
  String get requested => 'Requested';

  @override
  String get nearbyEmpty => 'Nobody in range right now.';

  @override
  String get networkTitle => 'Network';

  @override
  String get connectedNearby => 'Connected nearby';

  @override
  String connectedNearbyDetail(int wifi, int bluetooth) {
    return 'Wi-Fi to $wifi people, Bluetooth to $bluetooth more.';
  }

  @override
  String get links => 'Links';

  @override
  String get bluetooth => 'Bluetooth';

  @override
  String get bluetoothDetail => 'Finds people and carries chat';

  @override
  String get wifiNearby => 'Wi-Fi nearby';

  @override
  String get wifiNearbyDetail =>
      'Fast link for big files, over Wi-Fi Direct or the same Wi-Fi';

  @override
  String get longRangeAddOn => 'Long-range add-on';

  @override
  String get longRangeAddOnDetail => 'Needs an extra radio';

  @override
  String get radio => 'Radio';

  @override
  String get radioSwitchDetail =>
      'Through a plugged-in LoRa radio. Slow, chat only.';

  @override
  String get radioTitle => 'Long-range radio';

  @override
  String radioIntro(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'this PC',
      'other': 'this phone',
    });
    return 'Chat with people far beyond Bluetooth range through a LoRa radio plugged into $_temp0, or reached over Bluetooth or Wi-Fi. Slow, text only, no internet.';
  }

  @override
  String get radioDevice => 'Device';

  @override
  String get radioNoDevice => 'No radio set up';

  @override
  String get radioChooseDevice => 'Choose a device';

  @override
  String get radioChangeDevice => 'Change device';

  @override
  String get radioOverUsb => 'USB';

  @override
  String radioOverUsbDetail(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'A USB cable',
      'other': 'A cable, or an OTG adapter on a phone',
    });
    return '$_temp0';
  }

  @override
  String get radioOverBluetooth => 'Bluetooth';

  @override
  String get radioOverBluetoothDetail => 'A Meshtastic device paired nearby';

  @override
  String get radioOverWifi => 'Wi-Fi';

  @override
  String get radioOverWifiDetail =>
      'A Meshtastic device on the same network, by its address';

  @override
  String radioNotOnThisDevice(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'this PC',
      'other': 'this phone',
    });
    return 'Not on $_temp0 in this release';
  }

  @override
  String get radioAddressLabel => 'Address on the network (numbers only)';

  @override
  String get radioPortLabel => 'Port';

  @override
  String get radioAddressNotUsable =>
      'That is not an address on the local network.';

  @override
  String get radioScan => 'Look for devices';

  @override
  String get radioScanning => 'Looking…';

  @override
  String get radioNoneFound =>
      'No radio found. Plug one in, or switch it on, and look again.';

  @override
  String get radioDriverLabel => 'Kind of device';

  @override
  String get radioDriverMeshtastic => 'Meshtastic device';

  @override
  String get radioDriverSerial => 'Bare LoRa module with DNet serial firmware';

  @override
  String get radioUseThis => 'Use this device';

  @override
  String get radioForget => 'Forget this radio';

  @override
  String radioSetUpFailed(String reason) {
    return 'The radio could not be set up: $reason';
  }

  @override
  String get radioSetUpDone =>
      'Radio set up. Switch Long-range on under Links to use it.';

  @override
  String get radioRegionTitle => 'Band';

  @override
  String get radioRegionWarning =>
      'You must choose the band that is legal where you are. Transmitting on another band is against the law and can be punished. In India the licence-free band is 865–867 MHz.';

  @override
  String get radioRegionNotSet =>
      'No band chosen. The radio keeps whatever it was set to until you choose.';

  @override
  String radioRegionLegalIn(String countries) {
    return 'Legal in: $countries';
  }

  @override
  String radioRegionDutyCycle(int percent) {
    return 'Airtime limit $percent%';
  }

  @override
  String get radioChooseRegion => 'Choose a band';

  @override
  String get radioStatusTitle => 'Link';

  @override
  String radioStatusConnected(String name) {
    return 'Connected to $name';
  }

  @override
  String get radioStatusConnecting => 'Connecting…';

  @override
  String get radioStatusReconnecting => 'Lost the radio. Trying again…';

  @override
  String get radioStatusOff => 'Off. Switch Long-range on under Links.';

  @override
  String radioStatusFailed(String reason) {
    return 'Could not use the radio: $reason';
  }

  @override
  String radioDeviceLine(String firmware, String preset, String region) {
    return '$firmware · $preset · $region';
  }

  @override
  String get radioSignalTitle => 'Signal';

  @override
  String radioSignalWords(String grade) {
    String _temp0 = intl.Intl.selectLogic(grade, {
      'strong': 'Strong',
      'good': 'Good',
      'weak': 'Weak',
      'faint': 'Faint',
      'other': 'Nothing heard yet',
    });
    return '$_temp0';
  }

  @override
  String radioSignalDetail(int rssi, String snr) {
    return '$rssi dBm, SNR $snr dB';
  }

  @override
  String radioPeers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count DNet devices heard',
      one: '1 DNet device heard',
      zero: 'No DNet devices heard',
    );
    return '$_temp0';
  }

  @override
  String radioCounts(int sent, int delivered, int failed, int received) {
    return 'Sent $sent · delivered $delivered · failed $failed · received $received';
  }

  @override
  String radioAirtime(int percent) {
    return 'Airtime used this hour: $percent%';
  }

  @override
  String radioMessageStatus(String status) {
    String _temp0 = intl.Intl.selectLogic(status, {
      'sent': 'via radio · sent',
      'relayed': 'via radio · relayed',
      'delivered': 'via radio · delivered',
      'failed': 'via radio · failed',
      'other': 'via radio',
    });
    return '$_temp0';
  }

  @override
  String radioHops(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hops',
      one: '1 hop',
      zero: 'direct',
    );
    return '$_temp0';
  }

  @override
  String get radioFilesNote =>
      'Files never go by radio: a LoRa packet carries a few hundred bytes a second. They wait for Bluetooth or Wi-Fi.';

  @override
  String get radioStepDevice => '1 · Device';

  @override
  String get radioStepBand => '2 · Band';

  @override
  String get radioStepTest => '3 · Test the link';

  @override
  String get radioAntennaWarning =>
      'Attach the antenna before the radio is powered: sending without one can burn out its output stage.';

  @override
  String get radioTestLink => 'Say hello on the air';

  @override
  String get radioTestDetail =>
      'Sends a short \"DNet is here\". Other DNet radios in range answer with their own and are counted below.';

  @override
  String get radioTestSent =>
      'Sent. An answer can take a minute or two across several hops.';

  @override
  String get radioTestNotUp =>
      'Set up a device and switch Long-range on under Links first.';

  @override
  String radioLastHeard(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Last heard $minutes minutes ago',
      one: 'Last heard a minute ago',
      zero: 'Last heard just now',
    );
    return '$_temp0';
  }

  @override
  String radioRoundTrip(String seconds) {
    return 'Round trip $seconds s';
  }

  @override
  String radioLastProblem(String reason) {
    return 'Last problem: $reason';
  }

  @override
  String radioDeviceSays(String message) {
    return 'The radio says: $message';
  }

  @override
  String radioAirtimeOfLimit(int percent) {
    return 'Airtime this hour: $percent% of what the band allows';
  }

  @override
  String get radioAirtimeNoLimit =>
      'No airtime limit on this band. DNet still sends only what it must.';

  @override
  String radioBandwidthTooWide(String width, int limit) {
    return 'The radio\'s signal is $width kHz wide; the rules here allow $limit kHz. Set it to LONG_MODERATE (125 kHz) in the Meshtastic app.';
  }

  @override
  String get radioRegionSearch => 'Find a country or band';

  @override
  String get radioRegionNoMatch => 'No band matches that.';

  @override
  String radioPortKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'usbNative': 'The board\'s own USB',
      'cp210x': 'USB bridge chip (CP210x)',
      'ch34x': 'USB bridge chip (CH340 or CH9102)',
      'ftdi': 'USB bridge chip (FTDI)',
      'bluetooth': 'Bluetooth serial port, rarely a radio',
      'other': 'Serial port',
    });
    return '$_temp0';
  }

  @override
  String radioHardwareLine(String hardware, String firmware) {
    return '$hardware · firmware $firmware';
  }

  @override
  String radioSettingsLine(String preset, String region) {
    return '$preset · band $region';
  }

  @override
  String radioQueueFree(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Room for $count more packets in the radio\'s queue',
      one: 'Room for 1 more packet in the radio\'s queue',
      zero: 'The radio\'s send queue is full',
    );
    return '$_temp0';
  }

  @override
  String radioViaKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'serial': 'By USB',
      'ble': 'By Bluetooth',
      'tcp': 'By Wi-Fi',
      'other': 'Pretend radio',
    });
    return '$_temp0';
  }

  @override
  String get internet => 'Internet';

  @override
  String get internetDetail => 'Optional. Reach friends far away.';

  @override
  String get keepsYouConnected => 'Keeps you connected';

  @override
  String get automatic => 'Automatic';

  @override
  String get protectBothRadios => 'Sends on both radios at once';

  @override
  String get protectChangesBand => 'Changes band when one is crowded';

  @override
  String get protectLongRange => 'Long-range mode for weak signal';

  @override
  String get protectRebuildsFiles => 'Rebuilds files from any pieces';

  @override
  String get protectHoldsMessages => 'Holds messages until a path opens';

  @override
  String get encryptionAlwaysOn => 'AES-256 with post-quantum keys. Always on.';

  @override
  String get linkNobodyInRange => 'Nobody in range';

  @override
  String linkRadioLine(String radio, String people, String waiting) {
    return '$radio: $people, $waiting';
  }

  @override
  String linkPeople(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '1 person',
      zero: 'nobody',
    );
    return '$_temp0';
  }

  @override
  String get linkNothingWaiting => 'nothing waiting';

  @override
  String linkMessagesWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages waiting',
      one: '1 message waiting',
    );
    return '$_temp0';
  }

  @override
  String linkFilesWaiting(String size) {
    return '$size of files waiting';
  }

  @override
  String linkMessagesAndFilesWaiting(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: '1 message',
    );
    return '$_temp0 and $size of files waiting';
  }

  @override
  String movedToTwoGhz(String names) {
    return 'Moved $names to 2.4 GHz Wi-Fi.';
  }

  @override
  String get linkTroubleTitle => 'Link trouble';

  @override
  String get strongInterference => 'Strong interference';

  @override
  String get strongInterferenceDetail =>
      'Links dropped together while people were still in range.';

  @override
  String get wifi24 => 'Wi-Fi 2.4 GHz';

  @override
  String get wifi5 => 'Wi-Fi 5 GHz';

  @override
  String get noSignal => 'No signal';

  @override
  String get working => 'Working';

  @override
  String signalGettingBetter(String name) {
    return 'Signal to $name: getting better';
  }

  @override
  String signalGettingWorse(String name) {
    return 'Signal to $name: getting worse';
  }

  @override
  String keepWalkingToward(String name) {
    return 'Keep walking toward $name.';
  }

  @override
  String signalStrength(int level) {
    return 'Signal strength, $level of 5';
  }

  @override
  String get whatAppIsDoing => 'What DNet is doing';

  @override
  String movedToFiveGhz(String names) {
    return 'Moved $names to 5 GHz Wi-Fi.';
  }

  @override
  String holdingMessages(int count, String names) {
    return 'Holding $count messages for $names. They send when a path opens.';
  }

  @override
  String holdingMessagesFor(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: '1 message',
    );
    return 'Holding $_temp0 for $name. They send when a path opens.';
  }

  @override
  String signalHolding(String name) {
    return 'Signal to $name: holding';
  }

  @override
  String walkBackToward(String name) {
    return 'Try walking back toward $name.';
  }

  @override
  String tryWalkingToward(String name) {
    return 'Walking toward $name may help.';
  }

  @override
  String get radiosRestarted => 'Radios stopped and started again.';

  @override
  String twoNames(String first, String second) {
    return '$first and $second';
  }

  @override
  String get passByCameraCode => 'Pass messages by camera code';

  @override
  String get tryAllRadiosAgain => 'Try all radios again';

  @override
  String get showMyCode => 'Show my code';

  @override
  String get noPhoneNumber => 'No phone number';

  @override
  String get noEmail => 'No email';

  @override
  String get namesInSpaces => 'Names in spaces';

  @override
  String get namesInSpacesBody =>
      'You can go by a different name in each space. In your chats, and in every other space, you stay who you are.';

  @override
  String get noSpacesForNames => 'You are not in any space yet.';

  @override
  String usualName(String name) {
    return '$name (your usual name)';
  }

  @override
  String nameInSpaceTitle(String space) {
    return 'Your name in $space';
  }

  @override
  String get nameInSpaceBody =>
      'Everyone in this space will see it. Leave it empty to go by your usual name.';

  @override
  String spacesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count spaces',
      one: '1 space',
    );
    return '$_temp0';
  }

  @override
  String get linkedDevices => 'Linked devices';

  @override
  String get recoveryContacts => 'Recovery contacts';

  @override
  String recoveryContactsSet(int set, int total) {
    return '$set of $total set';
  }

  @override
  String get privacyAndSecurity => 'Privacy and security';

  @override
  String get storage => 'Storage';

  @override
  String storageWhere(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'All of it is on this PC and nowhere else.',
      'other': 'All of it is on this phone and nowhere else.',
    });
    return '$_temp0';
  }

  @override
  String get storageChats => 'Chats, spaces and settings';

  @override
  String get storageChatsDetail => 'Kept sealed. Only this device can open it.';

  @override
  String get storageReceived => 'Files you received';

  @override
  String get storageReceivedDetail =>
      'Ordinary files, saved where your other apps can open them.';

  @override
  String get storageVoice => 'Voice messages';

  @override
  String get storageVoiceDetail => 'The ones you recorded.';

  @override
  String get storageCarried => 'Waiting for a path';

  @override
  String get storageCarriedDetail =>
      'Your own sealed messages, kept here until a path to the person opens. Other people\'s messages are passed on at once and never kept on this device.';

  @override
  String storageFilesAndSize(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files, $size',
      one: '1 file, $size',
      zero: 'None',
    );
    return '$_temp0';
  }

  @override
  String storageMessagesAndSize(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages, $size',
      one: '1 message, $size',
      zero: 'None',
    );
    return '$_temp0';
  }

  @override
  String get storageHowToClear =>
      'Old messages can be deleted by themselves: switch on auto-delete under Privacy. To remove everything at once, use Wipe everything there.';

  @override
  String onThisPhone(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'On this PC',
      'other': 'On this phone',
    });
    return '$_temp0';
  }

  @override
  String get aboutApp => 'About DNet';

  @override
  String get sharingLabel => 'Sharing. Off keeps you private.';

  @override
  String get showWhenOnline => 'Show when I am online';

  @override
  String get letStrangersFindMe => 'Let strangers find me by name';

  @override
  String get letStrangersAddMe => 'Let strangers add me to groups';

  @override
  String get showIpInCalls => 'Show my IP address in calls';

  @override
  String get sendReadReceipts => 'Send read receipts';

  @override
  String get showWhenTyping => 'Show when I am typing';

  @override
  String get allowScreenshots => 'Allow screenshots of chats';

  @override
  String get appLock => 'App lock with passcode';

  @override
  String get autoDelete => 'Auto-delete old messages';

  @override
  String get eraseAfterWrongPasscodes => 'Erase after 10 wrong passcodes';

  @override
  String get alwaysOn => 'Always on';

  @override
  String get cannotBeSwitchedOff => 'Cannot be switched off';

  @override
  String get chatEncryption => 'Chat encryption';

  @override
  String get postQuantumKeys => 'Post-quantum keys';

  @override
  String get encryptedStorage => 'Encrypted storage';

  @override
  String get keyChangeAlerts => 'Key-change alerts';

  @override
  String notYourContactTitle(String name) {
    return 'Not the $name in your chats';
  }

  @override
  String notYourContactBody(String name) {
    return 'Same name, different key, so this is a different device. If $name says they have a new one, check with them another way before you accept.';
  }

  @override
  String savedUntilWipe(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'Saved on this PC until you wipe it.',
      'other': 'Saved on this phone until you wipe it.',
    });
    return '$_temp0';
  }

  @override
  String get wipeEverythingNow => 'Wipe everything now';

  @override
  String get wipeConfirmTitle => 'Wipe everything?';

  @override
  String wipeConfirmBody(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'This erases your key, chats, spaces and files from this PC. It cannot be undone.',
      'other': 'This erases your key, chats, spaces and files from this phone. It cannot be undone.',
    });
    return '$_temp0';
  }

  @override
  String get wipeConfirmAction => 'Wipe';

  @override
  String get delivered => 'Delivered';

  @override
  String get waitingToDeliver => 'Waiting. It will go when they are in range.';

  @override
  String get spaceName => 'Name of the space';

  @override
  String get spaceAbout => 'What it is about (optional)';

  @override
  String get spaceNeedsName => 'Give the space a name first.';

  @override
  String get create => 'Create';

  @override
  String get kindPrivate => 'Private space';

  @override
  String get kindPrivateDetail => 'Invite only. People nearby cannot see it.';

  @override
  String get kindPublic => 'Public space';

  @override
  String get kindPublicDetail =>
      'Anyone nearby can find it and join. Nothing said in it is secret.';

  @override
  String get kindChannel => 'Public channel';

  @override
  String get kindChannelDetail => 'Anyone nearby can follow it. Only you post.';

  @override
  String get invitations => 'Invitations';

  @override
  String invitedBy(String name) {
    return '$name invited you';
  }

  @override
  String inviteToSpace(String space) {
    return 'Invite to $space';
  }

  @override
  String get copyInviteLink => 'Copy invite link';

  @override
  String get linkLasts => 'Link lets people in for';

  @override
  String get linkLastsForGood => 'Always';

  @override
  String get linkLastsHour => '1 hour';

  @override
  String get linkLastsDay => '1 day';

  @override
  String get linkLastsWeek => '1 week';

  @override
  String get linkRunsOutNote =>
      'After that, DNet will not join with it. The link holds the space\'s key, so a changed app that kept a copy could still use it. Resetting invite links in space settings stops that.';

  @override
  String get inviteRunOutTitle => 'This invite has run out';

  @override
  String get inviteRunOutBody => 'Ask whoever sent it for a new one.';

  @override
  String get inviteLinkCopied =>
      'Invite link copied. Anyone who has it can join.';

  @override
  String get yourContacts => 'Your contacts';

  @override
  String get invite => 'Invite';

  @override
  String get invited => 'Invited';

  @override
  String get noContactsToInvite =>
      'Nobody to invite by name yet. Copy the link, or add someone from Nearby first.';

  @override
  String get leaveSpace => 'Leave this space';

  @override
  String leaveSpaceConfirmTitle(String space) {
    return 'Leave $space?';
  }

  @override
  String leaveSpaceConfirmBody(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'It is removed from this PC. You need a new invite to come back.',
      'other':
          'It is removed from this phone. You need a new invite to come back.',
    });
    return '$_temp0';
  }

  @override
  String get leave => 'Leave';

  @override
  String get inviteNotValidTitle => 'That is not a DNet invite';

  @override
  String get inviteNotValidBody =>
      'Copy the whole invite, then press Paste link again.';

  @override
  String joinedSpace(String space) {
    return 'Joined $space';
  }

  @override
  String get spaceWaiting =>
      'Waiting to meet a member. This space fills in when someone who is in it comes into range.';

  @override
  String get onlyOwnerPosts => 'Only the owner and admins can post here.';

  @override
  String postToChannel(String name) {
    return 'Post to $name';
  }

  @override
  String get noPostsYet => 'No posts yet.';

  @override
  String get followToSeePosts => 'Follow to see what is posted here.';

  @override
  String get react => 'React';

  @override
  String get timeOutTen => 'Time out for 10 minutes';

  @override
  String get timeOutHour => 'Time out for 1 hour';

  @override
  String get timeOutDay => 'Time out for 1 day';

  @override
  String get endTimeOut => 'End time-out';

  @override
  String get resetInviteLinks => 'Reset invite links';

  @override
  String get resetInviteLinksBody =>
      'Every invite link made before now stops working. Everyone already in the space stays. Use this if a link went to the wrong person.';

  @override
  String get resetInviteLinksAction => 'Reset';

  @override
  String timedOutWait(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes more minutes',
      one: '1 more minute',
    );
    return 'You are timed out here for $_temp0.';
  }

  @override
  String get yourQrCode =>
      'Your code. Someone points their camera at it to add you.';

  @override
  String get scanHint =>
      'Point the camera at a DNet code on someone\'s screen.';

  @override
  String get scanVerified => 'Scanned. They are verified.';

  @override
  String get scanJoinedSpace => 'You joined the space.';

  @override
  String get scanNotACodeTitle => 'That is not a DNet code';

  @override
  String get scanNotACodeBody =>
      'Ask them to open DNet and show their code, then scan again.';

  @override
  String votesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count votes',
      one: '1 vote',
    );
    return '$_temp0';
  }

  @override
  String get channelRules => 'Rules';

  @override
  String channelRulesNamed(String name) {
    return 'Rules for $name';
  }

  @override
  String get channelRulesBody =>
      'Rules bind members. You and the admins are not bound. They apply to what is written from now on.';

  @override
  String get noLinksRule => 'No links from members';

  @override
  String get slowMode => 'Slow mode';

  @override
  String get slowModeDetail => 'How long a member waits between two messages';

  @override
  String get slowOff => 'Off';

  @override
  String get slowTen => '10 s';

  @override
  String get slowMinute => '1 min';

  @override
  String get slowFive => '5 min';

  @override
  String get slowHour => '1 hour';

  @override
  String slowSeconds(int seconds) {
    return '$seconds s';
  }

  @override
  String get linksNotAllowed => 'Links are not allowed in this channel.';

  @override
  String slowModeWait(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds seconds',
      one: '1 second',
    );
    return 'Slow mode is on here. Try again in $_temp0.';
  }

  @override
  String get rulesNoteNoLinks => 'No links here.';

  @override
  String rulesNoteLength(int count) {
    return 'Messages up to $count characters.';
  }

  @override
  String get rulesNoteBanned => 'Some words are not allowed in this space.';

  @override
  String get bannedWordRefused =>
      'That has a word the owner does not allow in this space.';

  @override
  String tooLongRefused(int count) {
    return 'Messages here can be up to $count characters.';
  }

  @override
  String get roles => 'Roles';

  @override
  String get rolesBody =>
      'A role lets the members you give it to do some of what admins do. Changing what a role may do counts for what its holders did before, too.';

  @override
  String get addRole => 'Add a role';

  @override
  String get roleName => 'Role name';

  @override
  String get roleMayNothing => 'Nothing beyond writing yet';

  @override
  String get roleNotUsable =>
      'A role needs a name of up to 32 characters. A space has up to 20 roles.';

  @override
  String get rolePowerPin => 'Pin messages';

  @override
  String get rolePowerAnnounce => 'Write in announcement channels';

  @override
  String get rolePowerDelete => 'Delete anyone\'s message';

  @override
  String get rolePowerTimeout => 'Time members out';

  @override
  String get deleteRole => 'Delete role';

  @override
  String deleteRoleConfirmTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get deleteRoleConfirmBody =>
      'Nobody holds it any more. Channels kept for it are open to everyone again, unless they are kept for another role too.';

  @override
  String giveRole(String name) {
    return 'Give $name';
  }

  @override
  String takeRole(String name) {
    return 'Take back $name';
  }

  @override
  String get whoCanWrite => 'Who can write here';

  @override
  String get whoCanWriteDetail => 'Everyone in the space can still read it.';

  @override
  String get everyone => 'Everyone';

  @override
  String onlyRolesWrite(String roles) {
    return 'Only $roles can write here.';
  }

  @override
  String get roleNeededRefused => 'Only some roles can write in this channel.';

  @override
  String get bannedWords => 'Words not allowed';

  @override
  String get bannedWordsBody =>
      'Members cannot use these anywhere in the space. Whole words only, and capitals do not matter. Put commas between them. Up to 50.';

  @override
  String get bannedWordsNone => 'No words are kept out.';

  @override
  String get wordFilterSwitch => 'Keep these words out';

  @override
  String bannedWordsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count words or phrases are kept out.',
      one: '1 word or phrase is kept out.',
    );
    return '$_temp0';
  }

  @override
  String get bannedWordsNotUsable =>
      'Up to 50 words, each up to 32 characters.';

  @override
  String get lengthRule => 'Longest message';

  @override
  String get lengthNoLimit => 'No limit';

  @override
  String lengthChoice(String count) {
    return '$count characters';
  }

  @override
  String rulesNoteDisappear(String time) {
    return 'Messages here disappear after $time.';
  }

  @override
  String get disappearRule => 'Messages disappear';

  @override
  String get disappearRuleDetail =>
      'What is written here from now on is deleted from every member\'s device after this long. It cannot stop someone copying a message first.';

  @override
  String rulesNoteSlow(String time) {
    return 'Slow mode: one message every $time.';
  }

  @override
  String get codeExplained =>
      'People see your name. The code words are made from your key and the time, so they change every 10 minutes. They help people tell your device from another with the same name. They do not prove who you are.';

  @override
  String get deleteSpace => 'Delete this space';

  @override
  String deleteSpaceConfirmTitle(String space) {
    return 'Delete $space?';
  }

  @override
  String get deleteSpaceConfirmBody =>
      'It is removed for everyone in it, with everything said there. Members out of range lose it when they next meet someone who has heard. This cannot be undone.';

  @override
  String get copyLink => 'Copy link';

  @override
  String get pasteAnyLink => 'Paste a link';

  @override
  String get pasteAnyLinkDetail =>
      'A person\'s link asks them to chat. A space\'s link joins it.';

  @override
  String get linkExplained =>
      'Copy or Share makes a new link each time. It works once, for a day, so it cannot be passed around.';

  @override
  String get checkFromAnywhere => 'Not together? Check from anywhere';

  @override
  String get checkFromAnywhereBody =>
      'Send your code by any other app, or read these words to each other on a call. If the code they send you is the same as yours, nobody is in between.';

  @override
  String get copyMyCode => 'Copy my code';

  @override
  String get pasteTheirCode => 'Paste their code';

  @override
  String get codeCopied => 'Code copied. Send it to them by another app.';

  @override
  String get codesDiffer => 'The codes are not the same';

  @override
  String get codesDifferBody =>
      'Do not rely on this chat until they match. Check that you copied the whole code and that it really came from them.';

  @override
  String get unblock => 'Unblock';

  @override
  String codesMatch(String name) {
    return 'The codes match. $name is verified.';
  }

  @override
  String blockedPeople(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count blocked people',
      one: '1 blocked person',
    );
    return '$_temp0';
  }

  @override
  String get nothingOpen =>
      'Choose a chat or a channel on the left to open it here.';

  @override
  String get keysFindChat => 'Ctrl+K';

  @override
  String get keysFindChatLabel => 'Find a chat';

  @override
  String get keysNewChat => 'Ctrl+N';

  @override
  String get keysNewChatLabel => 'Start a new chat';

  @override
  String get keysTabs => 'Ctrl+1–4';

  @override
  String get keysTabsLabel => 'Switch tabs';

  @override
  String get keysSearchHere => 'Ctrl+F';

  @override
  String get keysSearchHereLabel => 'Search in a channel';

  @override
  String get keysClose => 'Esc';

  @override
  String get keysCloseLabel => 'Go back or close';

  @override
  String get scrollToNewest => 'Go to the newest message';

  @override
  String jumpToNew(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new messages',
      one: '1 new message',
    );
    return '$_temp0';
  }

  @override
  String get showMemberList => 'Show members';

  @override
  String get hideMemberList => 'Hide members';

  @override
  String get messageMore => 'More for this message';

  @override
  String get send => 'Send';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get clear => 'Clear';

  @override
  String get deleteForMe => 'Delete for me';

  @override
  String get deleteForEveryone => 'Delete for everyone';

  @override
  String get deleteForEveryoneNote =>
      'Their copy is deleted when your devices next meet. If they have already read it or copied it, that cannot be undone.';

  @override
  String get deleteForEveryoneFailed =>
      'Only your own messages of the last two days can be deleted for everyone.';

  @override
  String get messageDeleted => 'This message was deleted';

  @override
  String get messageDeletedMine => 'You deleted this message';

  @override
  String get clearChat => 'Clear chat';

  @override
  String clearChatConfirmTitle(String name) {
    return 'Clear the chat with $name?';
  }

  @override
  String clearChatConfirmBody(String name) {
    return 'Every message in it is deleted from this device. $name keeps theirs.';
  }

  @override
  String get deleteChat => 'Delete chat';

  @override
  String deleteChatConfirmTitle(String name) {
    return 'Delete the chat with $name?';
  }

  @override
  String deleteChatConfirmBody(String name) {
    return 'It is cleared and taken off your chats until one of you writes again. $name stays a contact.';
  }

  @override
  String get remove => 'Remove';

  @override
  String get editName => 'Change your name';

  @override
  String get codeWordsLabel => 'Your code words';

  @override
  String get editNameBody =>
      'Your contacts and the spaces you are in will see the new name.';

  @override
  String get nameNotUsable =>
      'That name cannot be used. It needs 1 to 64 characters.';

  @override
  String get descriptionTooLong =>
      'That is too long. Keep it under 140 characters.';

  @override
  String get spaceSettings => 'Space settings';

  @override
  String get channelSettings => 'Channel settings';

  @override
  String get spaceAboutSection => 'About';

  @override
  String get spaceDescription => 'Description';

  @override
  String get noDescription => 'No description';

  @override
  String get renameSpace => 'Change the name';

  @override
  String get editDescription => 'Change the description';

  @override
  String get channels => 'Channels';

  @override
  String get addChannel => 'Add a channel';

  @override
  String get channelName => 'Channel name';

  @override
  String get channelForOwners => 'Only the owner and admins write here';

  @override
  String get channelForOwnersShort => 'Owner and admins write here';

  @override
  String get renameChannel => 'Rename channel';

  @override
  String get lastChannelStays => 'A space keeps at least one channel.';

  @override
  String get deleteChannelConfirmBody =>
      'What was said in it will no longer be shown to anyone.';

  @override
  String get roleOwner => 'Owner';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get makeAdmin => 'Make admin';

  @override
  String get removeAdmin => 'Remove as admin';

  @override
  String get removeFromSpace => 'Remove from space';

  @override
  String get makeOwner => 'Make owner';

  @override
  String get handOver => 'Hand over';

  @override
  String handOverConfirmTitle(String name) {
    return 'Make $name the owner?';
  }

  @override
  String get handOverConfirmBody =>
      'They will run this space from now on, and you will be a member. You cannot take it back; only they can give it to you again. Who is an admin, and who was removed, stays as it is.';

  @override
  String get removeMemberConfirmBodyPrivate =>
      'They keep what was said so far. They get nothing said from now on, and invite links made before now stop working.';

  @override
  String get removeMemberConfirmBodyPublic =>
      'This space is public, so they can still read it. Nothing they write will be shown to anyone.';

  @override
  String get rolesExplained =>
      'The owner changes the name and channels, chooses admins, removes people and can hand the space to someone else. Admins can pin, write in the info channels and delete messages.';

  @override
  String get stopFollowing => 'Stop following';

  @override
  String get deleteMessage => 'Delete for everyone';

  @override
  String get editMessage => 'Edit';

  @override
  String get editMessageTitle => 'Change your message';

  @override
  String get editNotDone => 'This message could not be changed.';

  @override
  String get messageEdited => 'edited';

  @override
  String get mentionsYou => 'mentions you';

  @override
  String mentionName(String name) {
    return 'Mention $name';
  }

  @override
  String mentionedYouCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages mention you',
      one: '1 message mentions you',
    );
    return '$_temp0';
  }

  @override
  String get deleteMessageConfirmTitle => 'Delete this for everyone?';

  @override
  String get deleteMessageConfirmBody =>
      'It is taken down on every device that has it.';

  @override
  String get chatOptions => 'Chat options';

  @override
  String get spaceOptions => 'Space options';

  @override
  String get unmute => 'Unmute';

  @override
  String get blockPerson => 'Block';

  @override
  String renameChannelNamed(String name) {
    return 'Rename $name';
  }

  @override
  String deleteChannelNamed(String name) {
    return 'Delete $name';
  }

  @override
  String deleteChannelConfirmTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String removeMemberConfirmTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String nameAndYou(String name) {
    return '$name (you)';
  }

  @override
  String manageMember(String name) {
    return 'Manage $name';
  }

  @override
  String get reply => 'Reply';

  @override
  String replyingTo(String name) {
    return 'Replying to $name';
  }

  @override
  String get cancelReply => 'Stop replying';

  @override
  String get pinMessage => 'Pin to the top';

  @override
  String get unpinMessage => 'Unpin';

  @override
  String get newPoll => 'New poll';

  @override
  String get pollQuestion => 'Question';

  @override
  String pollChoice(int number) {
    return 'Choice $number';
  }

  @override
  String get addChoice => 'Add a choice';

  @override
  String get sendPoll => 'Send poll';

  @override
  String get pollNeedsTwo =>
      'A poll needs a question and at least two choices.';

  @override
  String get comment => 'Comment';

  @override
  String get comments => 'Comments';

  @override
  String get noCommentsYet => 'No comments yet.';

  @override
  String get writeComment => 'Write a comment';

  @override
  String get commentNameShown =>
      'Comments can be read by anyone who follows this channel. Your name is shown with yours.';

  @override
  String get reactHeart => 'Heart';

  @override
  String get reactAgree => 'Agree';

  @override
  String filePreview(String name) {
    return 'File: $name';
  }

  @override
  String get fileAsked => 'Wants to send you this';

  @override
  String get fileWaitingForAnswer => 'Waiting for them to accept';

  @override
  String get fileSent => 'Sent';

  @override
  String get fileSaved => 'Received and saved';

  @override
  String get fileDeclined => 'Declined';

  @override
  String get fileCancelled => 'Cancelled';

  @override
  String get fileFailed => 'Did not arrive whole, so it was not kept';

  @override
  String get fileSavedAtTitle => 'Where it was saved';

  @override
  String get fileNotSent => 'That file could not be sent.';

  @override
  String get channelFileNotSent =>
      'That could not be posted. A file in a channel can be up to 25 MB.';

  @override
  String get radarDistanceNote =>
      'Nearer the middle is nearer you. Bluetooth cannot tell which way.';

  @override
  String get meshWifi => 'Wi-Fi';

  @override
  String meshInRange(int count) {
    return '$count in range';
  }

  @override
  String meshThroughOthers(int count) {
    return '$count through others';
  }

  @override
  String meshMapLabel(String radio, int inRange, int through) {
    return '$radio map: $inRange in range, $through through others';
  }

  @override
  String get meshDirect => 'Direct';

  @override
  String meshHops(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hops',
      one: '1 hop',
    );
    return '$_temp0';
  }

  @override
  String meshThroughPath(String path) {
    return 'through $path';
  }

  @override
  String get signalStrong => 'Strong signal';

  @override
  String get signalFair => 'Fair signal';

  @override
  String get signalWeak => 'Weak signal';

  @override
  String get meshOpenMap => 'Open the map';

  @override
  String meshNobodyOn(String radio) {
    return 'Nobody on $radio right now.';
  }

  @override
  String get download => 'Download';

  @override
  String get saveACopy => 'Save a copy';

  @override
  String get fileNotSaved => 'That file could not be saved.';

  @override
  String get fileWaitingForHolder => 'Waiting for someone in range who has it';

  @override
  String fileComing(int percent) {
    return 'Getting it: $percent%';
  }

  @override
  String get receivingFile => 'Receiving file';

  @override
  String fileSizeFrom(String size, String name) {
    return '$size, from $name';
  }

  @override
  String kilobytesPerSecond(int value) {
    return '$value KB/s';
  }

  @override
  String get stepStayingOnBluetooth =>
      'Going over Bluetooth, which is slow for big files';

  @override
  String get sendBigFileDetailBluetooth =>
      'Goes over Bluetooth for now. Slow for big files.';

  @override
  String get linkNoticeTitle => 'DNet is on';

  @override
  String get linkNoticeText => 'Finding people nearby over Bluetooth.';

  @override
  String get linkCopied =>
      'Link copied. It works once, for a day. Send it any way you like.';

  @override
  String get linkRequestSent =>
      'Request sent. It reaches them when a path opens.';

  @override
  String get personLinkRunOutTitle => 'This link has run out';

  @override
  String get personLinkRunOutBody =>
      'Each DNet link works once, for a day. Ask them to send a new one.';

  @override
  String get linkAlreadyContact => 'You already chat with this person.';

  @override
  String get linkIsYours => 'That is your own link.';

  @override
  String get linkNotValidTitle => 'That is not a DNet link';

  @override
  String get linkNotValidBody => 'Copy the whole link, then press Paste again.';

  @override
  String get searchChats => 'Search chats';

  @override
  String get noChatsFound => 'No chats match.';

  @override
  String get lockedTitle => 'DNet is locked';

  @override
  String get passcode => 'Passcode';

  @override
  String get passcodeAgain => 'Passcode again';

  @override
  String get unlock => 'Unlock';

  @override
  String get wrongPasscode => 'That is not the passcode.';

  @override
  String triesLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tries left before everything is erased.',
      one: '1 try left before everything is erased.',
    );
    return '$_temp0';
  }

  @override
  String get setPasscodeTitle => 'Choose a passcode';

  @override
  String get setPasscodeBody =>
      'DNet asks for it each time it opens. Use at least 4 characters. If you forget it, the only way back in is to wipe everything.';

  @override
  String get setPasscode => 'Set passcode';

  @override
  String get passcodeTooShort => 'Use at least 4 characters.';

  @override
  String get passcodesDiffer => 'The two do not match.';

  @override
  String get removePasscodeTitle => 'Switch off the app lock';

  @override
  String get removePasscodeBody => 'Enter your passcode to switch it off.';

  @override
  String get switchOff => 'Switch off';

  @override
  String get needPasscodeFirst => 'Switch on the app lock first.';

  @override
  String get autoDeleteConfirmTitle => 'Delete old messages?';

  @override
  String autoDeleteConfirmBody(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'PC',
      'other': 'phone',
    });
    return 'Chat messages older than 30 days are deleted from this $_temp0, now and from now on. Notes to self, spaces and files are kept.';
  }

  @override
  String get autoDeleteConfirmAction => 'Delete old messages';

  @override
  String get notBuiltTag => 'Coming soon';

  @override
  String get notSetUp => 'Not set up';

  @override
  String get nothingBeingSent => 'Nothing is being sent right now.';

  @override
  String get linksAreWorking => 'Your links are working.';

  @override
  String get radioBluetoothOffTitle => 'Bluetooth is off';

  @override
  String get radioBluetoothOffBody =>
      'DNet finds people nearby over Bluetooth. Switch it on to see who is around.';

  @override
  String get radioBluetoothOffAction => 'Switch on Bluetooth';

  @override
  String get radioNoPermissionTitle => 'DNet may not use Bluetooth yet';

  @override
  String get radioNoPermissionBody =>
      'DNet needs your permission to use Bluetooth, to find people near you and carry your chats. Your device may call this Nearby devices or Location. DNet never reads where you are.';

  @override
  String get radioNoPermissionAction => 'Allow Bluetooth';

  @override
  String get radioLocationOffTitle => 'Location is off';

  @override
  String get radioLocationOffBody =>
      'On this version of Android, apps can only find Bluetooth devices while Location is on. DNet never reads where you are.';

  @override
  String get radioLocationOffAction => 'Open settings';

  @override
  String get radioUnsupportedTitle => 'No Bluetooth here';

  @override
  String get radioUnsupportedBody =>
      'DNet could not find a Bluetooth radio it can use on this device, so it cannot find people nearby.';

  @override
  String get radioSwitchedOffTitle => 'The Bluetooth link is switched off';

  @override
  String get radioSwitchedOffBody =>
      'You switched it off in Network. Switch it on again to find people nearby.';

  @override
  String get radioSwitchedOffAction => 'Open Network';

  @override
  String keyChangedTitle(String name) {
    return '$name\'s key has changed';
  }

  @override
  String keyChangedBody(String name) {
    return 'This is not the key you had for $name. It may be a new device, or someone pretending to be them. They are not verified. Compare words before you share anything private.';
  }

  @override
  String get acceptAnyway => 'Accept anyway';

  @override
  String get voiceCall => 'Voice call';

  @override
  String get videoCall => 'Video call';

  @override
  String soonLabel(String what, String soon) {
    return '$what · $soon';
  }

  @override
  String get callCalling => 'Calling';

  @override
  String get callRinging => 'Ringing';

  @override
  String get callSettingUpWifi => 'Setting up Wi-Fi';

  @override
  String callIsCalling(String name) {
    return '$name is calling';
  }

  @override
  String get callAnswer => 'Answer';

  @override
  String get callHangUp => 'Hang up';

  @override
  String get callEnded => 'Call ended';

  @override
  String callDeclined(String name) {
    return '$name turned the call down';
  }

  @override
  String callBusy(String name) {
    return '$name is in another call';
  }

  @override
  String get callNoAnswer => 'No answer';

  @override
  String callNeedsWifi(String name) {
    return 'Calls need Wi-Fi. Bluetooth is too slow for live sound, and no Wi-Fi link could be set up with $name.';
  }

  @override
  String callLost(String name) {
    return 'The link to $name was lost';
  }

  @override
  String get callFailed => 'The call could not be set up safely';

  @override
  String callNotInRange(String name) {
    return '$name is not in range. Calls work only with someone nearby.';
  }

  @override
  String get callAlreadyIn => 'You are already in a call';

  @override
  String get callRefused => 'This call could not be made';

  @override
  String get callReconnecting => 'Wi-Fi link lost. Trying to get it back';

  @override
  String get callMicMissing =>
      'Your microphone can\'t be used, so they can\'t hear you. Check that DNet is allowed to use it.';

  @override
  String callTheyMuted(String name) {
    return '$name is muted';
  }

  @override
  String get callLoudspeakerOn => 'Turn the loudspeaker on';

  @override
  String get callLoudspeakerOff => 'Turn the loudspeaker off';

  @override
  String get turnCameraOff => 'Turn camera off';

  @override
  String get callMinimise => 'Back to the app';

  @override
  String get callReturn => 'Return to the call';

  @override
  String callBarPerson(String name) {
    return 'In a call with $name';
  }

  @override
  String callBarRoom(String room) {
    return 'In $room';
  }

  @override
  String get callOverWifi => 'Over Wi-Fi, end-to-end encrypted';

  @override
  String get callKeyNoteTwo =>
      'If you both see these words, nobody is listening in.';

  @override
  String callTheirCameraOff(String name) {
    return '$name\'s camera is off';
  }

  @override
  String get roomJoining => 'Joining';

  @override
  String get soundOff => 'Turn sound off';

  @override
  String get soundOn => 'Turn sound back on';

  @override
  String get roomSoundOff => 'Sound off';

  @override
  String get roomNoWifi => 'No Wi-Fi link';

  @override
  String get roomOwnerMuted => 'Muted by an admin';

  @override
  String get roomOwnerDeafened => 'Can\'t hear';

  @override
  String get roomYouOwnerMuted =>
      'An admin has muted you in this space\'s voice rooms.';

  @override
  String get roomYouOwnerDeafened =>
      'An admin has deafened you in this space\'s voice rooms.';

  @override
  String roomMuteFor(String name) {
    return 'Mute $name for everyone';
  }

  @override
  String roomUnmuteFor(String name) {
    return 'Let $name speak';
  }

  @override
  String roomDeafen(String name) {
    return 'Deafen $name';
  }

  @override
  String roomUndeafen(String name) {
    return 'Let $name hear';
  }

  @override
  String get roomRuleNotSet => 'That could not be changed.';

  @override
  String get roomCannotJoin => 'This voice room can\'t be joined.';

  @override
  String get roomEmpty => 'Nobody else is here yet.';

  @override
  String get voiceRoomKind => 'Voice room';

  @override
  String get tapHoldTitle => 'Hold your phones back to back';

  @override
  String get tapHoldBody =>
      'Keep this screen open on both phones. It takes a second or two.';

  @override
  String get tapNfcOffTitle => 'NFC is off';

  @override
  String get tapNfcOffBody => 'Switch on NFC to tap phones together.';

  @override
  String get tapOpenSettings => 'Open NFC settings';

  @override
  String get tapGotTheirs => 'Got their code. Chat request sent.';

  @override
  String get tapGaveMine => 'They have your code.';

  @override
  String get fromStranger => 'From someone you have not accepted';

  @override
  String get tapToShow => 'Tap to show';

  @override
  String get spoiler => 'Spoiler, tap to show';

  @override
  String get statusTitle => 'Status';

  @override
  String get statusBody =>
      'Only members of your spaces who are in range are told. Nobody else is.';

  @override
  String get statusOnline => 'Online';

  @override
  String get statusIdle => 'Idle';

  @override
  String get statusDnd => 'Do not disturb';

  @override
  String get statusInvisible => 'Invisible';

  @override
  String get statusOffline => 'Offline';

  @override
  String get statusOnlineDetail =>
      'Members in range see you are here. Being in range already shows them that.';

  @override
  String get statusIdleDetail => 'Members in range see you are away for now.';

  @override
  String get statusDndDetail =>
      'Members in range see you would rather not be disturbed. Alerts still come.';

  @override
  String get statusInvisibleDetail =>
      'Nothing is sent: members see you as offline and are not told when you type. Devices in range still pass messages on, so someone nearby may tell you are there.';

  @override
  String get statusNotChanged => 'Your status could not be changed.';

  @override
  String get everyoneNotAllowed =>
      'Only the owner, admins and roles allowed to can call on @everyone.';

  @override
  String get rolePowerMentionEveryone => 'Call on @everyone';

  @override
  String get forwardMessage => 'Forward';

  @override
  String get forwardTitle => 'Forward to';

  @override
  String get forwardBody =>
      'It goes as your own message, marked as forwarded. Where it came from and who wrote it are not said.';

  @override
  String get nowhereToForward =>
      'There is nowhere to forward this yet: no channel you can write in and no contacts.';

  @override
  String get forwardChannels => 'Channels';

  @override
  String get forwardContacts => 'Contacts';

  @override
  String forwardToChannel(String channel, String space) {
    return 'Forward to $channel in $space';
  }

  @override
  String forwardToContact(String name) {
    return 'Forward to $name';
  }

  @override
  String get forwarded => 'Forwarded';

  @override
  String get forwardFailed =>
      'Could not forward it. They may no longer be a contact.';

  @override
  String get messageForwarded => 'forwarded';

  @override
  String typingOne(String name) {
    return '$name is typing…';
  }

  @override
  String typingTwo(String first, String second) {
    return '$first and $second are typing…';
  }

  @override
  String get typingMany => 'Several people are typing…';

  @override
  String get searchChannel => 'Search this channel';

  @override
  String searchChannelHint(String channel) {
    return 'Search #$channel';
  }

  @override
  String get noSearchMatches => 'Nothing here matches.';

  @override
  String get newMessages => 'New messages';

  @override
  String get spaceRules => 'Rules';

  @override
  String spaceRulesOf(String space) {
    return 'Rules of $space';
  }

  @override
  String get noRulesYet => 'No rules written yet.';

  @override
  String get rulesSignedNote =>
      'Written and signed by the owner. Every member\'s app checks the signature.';

  @override
  String get spaceRulesBody =>
      'Shown to everyone in the space. Up to 2000 characters.';

  @override
  String get rulesTooLong => 'Rules can be up to 2000 characters.';

  @override
  String get editRules => 'Edit the rules';

  @override
  String welcomeTo(String space) {
    return 'Welcome to $space';
  }

  @override
  String get readTheRules => 'Read the rules';

  @override
  String get welcomeMessage => 'Welcome message';

  @override
  String get welcomeMessageBody =>
      'Shown at the top of the space to everyone who joins. Up to 500 characters.';

  @override
  String get welcomeTooLong => 'A welcome can be up to 500 characters.';

  @override
  String get noWelcomeYet => 'No welcome message yet.';

  @override
  String get editWelcome => 'Edit the welcome message';

  @override
  String get changeNickname => 'Change nickname';

  @override
  String changeNicknameOf(String name) {
    return 'Change $name\'s nickname';
  }

  @override
  String get changeNicknameBody =>
      'Everyone in this space sees them by this name. Leave it empty to give them back their own.';

  @override
  String get nickname => 'Nickname';

  @override
  String get scanNotInRangeTitle => 'They are not in range';

  @override
  String get scanNotInRangeBody =>
      'A code works when you are near each other. Open DNet on both and come closer, or send them a link instead.';

  @override
  String get profilePhoto => 'Profile photo';

  @override
  String get profilePhotoBody =>
      'A picture or a GIF. It is made small on this device first. Your contacts and the members of your spaces see it. You can stop showing it under Privacy.';

  @override
  String get choosePhoto => 'Choose a picture or GIF';

  @override
  String get removePhoto => 'Remove photo';

  @override
  String get photoSet => 'Your photo is set.';

  @override
  String get photoNotUsable =>
      'That picture could not be used. Try a JPEG, PNG or a shorter GIF.';

  @override
  String get showMyPhoto => 'Show my profile photo';

  @override
  String get spaceIcon => 'Space icon';

  @override
  String get spaceIconNone => 'No icon yet. Its initials are shown.';

  @override
  String get spaceIconChosen => 'A picture or GIF you chose.';

  @override
  String get changeSpaceIcon => 'Change the space icon';

  @override
  String get spaceIconBody =>
      'A picture or a GIF. It is made small on this device first. Everyone in this space sees it.';

  @override
  String get spaceIconBodyPublic =>
      'A picture or a GIF. It is made small on this device first. Everyone in this space sees it, and so does anyone nearby who can find it.';

  @override
  String get removeSpaceIcon => 'Remove icon';

  @override
  String get spaceIconSet => 'The space icon is set.';

  @override
  String get codeWordsNote =>
      'These words change every 10 minutes. They help people nearby tell you apart from someone with the same name. They do not prove who you are.';

  @override
  String scanUnavailable(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'This PC has no camera DNet can use.',
      'other': 'This phone has no camera DNet can use.',
    });
    return '$_temp0 Use Find nearby or a link instead.';
  }

  @override
  String tapUnavailable(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'This PC has no NFC.',
      'other': 'This phone has no NFC.',
    });
    return '$_temp0 Use Find nearby or a link instead.';
  }

  @override
  String get findingLocation => 'Finding where you are…';

  @override
  String get shareLocationWarnTitle => 'Send your exact location?';

  @override
  String shareLocationWarnBody(String to, String where) {
    return 'Your exact location will be sent to $to: $where. Only send it if you are happy for them to know where you are.';
  }

  @override
  String shareLocationWarnBodyChannel(String where) {
    return 'Your exact location will be posted in this channel: $where. Everyone who can read it will know where you are.';
  }

  @override
  String placeWithin(String place, int metres) {
    return '$place, to within about $metres m';
  }

  @override
  String get locationNotSent => 'Your location was not sent.';

  @override
  String get locationDeniedTitle => 'DNet can\'t see where you are';

  @override
  String locationDeniedBody(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'Windows has not let DNet know where this PC is. In Settings, under Privacy & security, Location, let desktop apps see your location, then try again.',
      'other': 'Allow DNet to use your location in Settings, then try again.',
    });
    return '$_temp0';
  }

  @override
  String get locationOffTitle => 'Location is off';

  @override
  String locationOffBody(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'Turn on location services in Settings, under Privacy & security, Location, then try again.',
      'other': 'Turn on location for this phone, then try again.',
    });
    return '$_temp0';
  }

  @override
  String get locationUnknownTitle => 'Couldn\'t find where you are';

  @override
  String locationUnknownBody(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'Windows could not tell where this PC is. A PC without GPS works it out from Wi-Fi networks nearby, which needs the internet.',
      'other': 'Your phone could not tell in time. GPS finds you more easily outside or near a window.',
    });
    return '$_temp0';
  }

  @override
  String get openLocationSettings => 'Open Settings';

  @override
  String get locationCard => 'Location';

  @override
  String locationWithin(int metres) {
    return 'Within about $metres m';
  }

  @override
  String locationCardLabel(String place) {
    return 'Location: $place';
  }

  @override
  String get locationCopied => 'Location copied';

  @override
  String get openInMaps => 'Open in maps';

  @override
  String get openMapWarnTitle => 'Open this place in a map?';

  @override
  String openMapWarnBody(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'This opens openstreetmap.org in your browser. That site will learn this place and your internet address.',
      'other': 'Your map app will be shown this place. It may look it up online, which tells its maker about this place.',
    });
    return '$_temp0';
  }

  @override
  String get noMapApp => 'There is no map app to open it in.';

  @override
  String get cameraStarting => 'Starting the camera…';

  @override
  String get cameraUnavailableTitle => 'The camera could not be opened';

  @override
  String get cameraUnavailableBody =>
      'Another app may be using it, or Windows may not let desktop apps use the camera. Check Settings, under Privacy & security, Camera, then try again.';

  @override
  String get emojiAndStickers => 'Emoji and stickers';

  @override
  String get showKeyboard => 'Keyboard';

  @override
  String get emojiTab => 'Emoji';

  @override
  String get stickersTab => 'Stickers';

  @override
  String emojiGroup(String group) {
    String _temp0 = intl.Intl.selectLogic(group, {
      'recent': 'Recent',
      'smileys': 'Smileys',
      'people': 'People',
      'nature': 'Animals and nature',
      'food': 'Food and drink',
      'activities': 'Activities',
      'travel': 'Travel and places',
      'objects': 'Objects',
      'symbols': 'Symbols',
      'flags': 'Flags',
      'other': 'Emoji',
    });
    return '$_temp0';
  }

  @override
  String get noRecentEmoji => 'Emoji you use show up here.';

  @override
  String get stickerPackTitle => 'DNet stickers';

  @override
  String get myStickersTitle => 'Your stickers';

  @override
  String get noStickersYet =>
      'Open a picture or GIF someone sent you and choose Save as sticker to keep it here.';

  @override
  String get stickerPreview => 'Sticker';

  @override
  String stickerLabel(String name) {
    String _temp0 = intl.Intl.selectLogic(name, {
      'hello': 'Sticker: Hi!',
      'thanks': 'Sticker: Thanks!',
      'lol': 'Sticker: laughing',
      'love': 'Sticker: in love',
      'wow': 'Sticker: wow',
      'sad': 'Sticker: sad',
      'angry': 'Sticker: angry',
      'cool': 'Sticker: cool',
      'sleepy': 'Sticker: sleepy',
      'party': 'Sticker: party',
      'ok': 'Sticker: OK!',
      'cat': 'Sticker: cat',
      'other': 'Sticker',
    });
    return '$_temp0';
  }

  @override
  String get stickerUnknown => 'A sticker this version of DNet does not have';

  @override
  String get stickerNotSent => 'The sticker was not sent.';

  @override
  String get saveAsSticker => 'Save as sticker';

  @override
  String get stickerSaved => 'Saved to your stickers.';

  @override
  String get stickerNotMade => 'This picture can\'t be made into a sticker.';

  @override
  String get stickerAlreadyKept => 'It is in your stickers.';

  @override
  String get removeSticker => 'Remove from your stickers';

  @override
  String get stickerRemoved => 'Removed from your stickers.';

  @override
  String get moreEmoji => 'More emoji';

  @override
  String reactWithEmoji(String emoji) {
    return 'React with $emoji';
  }

  @override
  String emojiReaction(String emoji, int count) {
    return '$emoji reaction, $count';
  }

  @override
  String get chooseReaction => 'Choose a reaction';

  @override
  String get shareVideo => 'Video';

  @override
  String videoNamed(String name) {
    return 'Video: $name';
  }

  @override
  String videoLength(String length) {
    return '$length long';
  }

  @override
  String get playVideo => 'Play video';

  @override
  String get pauseVideo => 'Pause video';

  @override
  String get videoFullScreen => 'Full screen';

  @override
  String videoCannotPlay(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'This PC can\'t play this video. Windows plays the kinds of video it has codecs for.',
      'other': 'This phone can\'t play this video.',
    });
    return '$_temp0';
  }

  @override
  String get videoNotHere => 'Not on this device yet';

  @override
  String get videosSentAsTheyAre =>
      'Only photos have their location taken out. Videos are sent as they are, with anything the camera noted.';

  @override
  String videoPosition(String position, String length) {
    return '$position of $length';
  }

  @override
  String videoCallPerson(String name) {
    return 'Video call $name';
  }

  @override
  String get timerOffShort => 'Off';

  @override
  String get shareCamera => 'Camera';

  @override
  String get cameraTitle => 'Take a photo';

  @override
  String get takePhoto => 'Take photo';

  @override
  String get retakePhoto => 'Retake';

  @override
  String get usePhoto => 'Use photo';

  @override
  String get photoNotTaken => 'The photo could not be saved. Try again.';

  @override
  String get cameraDeniedTitle => 'DNet may not use the camera';

  @override
  String cameraDeniedBody(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'To take a photo here, allow the camera for DNet in Windows Settings, under Privacy & security, Camera, then try again.',
      'other': 'To take a photo here, allow the camera for DNet in your phone\'s settings, then try again.',
    });
    return '$_temp0';
  }

  @override
  String noCameraApp(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'This PC has no camera DNet can use.',
      'other': 'This phone has no camera app DNet can use.',
    });
    return '$_temp0';
  }

  @override
  String get transferOwnership => 'Transfer ownership';

  @override
  String get transferOwnershipDetail => 'Hand this space to another member';

  @override
  String transferOwnershipBody(String space) {
    return 'Choose who runs $space from now on.';
  }

  @override
  String get transferOwnershipNobody =>
      'Nobody else is in this space yet. Invite someone, then hand it over.';

  @override
  String transferConfirmBody(String name, String space) {
    return '$name will own $space. You will be a member, and can no longer change its name, channels, rules or roles, manage its members, or delete it. Who is an admin, and who was removed, stays as it is.\n\nYou cannot undo this yourself. Only $name can give it back.';
  }

  @override
  String get transfer => 'Transfer';

  @override
  String transferDone(String name, String space) {
    return '$name now owns $space.';
  }

  @override
  String get videoPreview => 'Video';

  @override
  String videoPreviewLength(String length) {
    return 'Video · $length';
  }

  @override
  String get videoPreviewReading => 'Video · reading…';

  @override
  String get videoPreviewNotHere => 'Video · not here yet';

  @override
  String get videoPreviewCannotRead => 'Video · cannot be played here';

  @override
  String locationPreview(String place) {
    return 'Location · $place';
  }

  @override
  String get locationPreviewGone => 'Location';

  @override
  String locationAccuracy(int metres) {
    return '±$metres m';
  }

  @override
  String pollPreview(String question) {
    return 'Poll · $question';
  }

  @override
  String pollOptionVotes(String option, int votes) {
    return '$option $votes';
  }

  @override
  String get pollNoVotesYet => 'No votes yet';

  @override
  String get tryAgain => 'Try again';

  @override
  String get couldNotChangeSpace => 'That change could not be made.';

  @override
  String get couldNotRemoveIcon => 'The icon could not be removed.';

  @override
  String get couldNotResetLinks => 'The invite links could not be reset.';

  @override
  String get inviteLinksReset => 'Invite links reset.';

  @override
  String get couldNotDeleteSpace => 'The space could not be deleted.';

  @override
  String get couldNotLeaveSpace => 'You could not leave just now.';

  @override
  String get couldNotJoinSpace => 'The space could not be joined.';

  @override
  String get couldNotSetRule => 'The rule could not be set.';

  @override
  String couldNotRemoveRole(String name) {
    return 'The role \"$name\" could not be deleted.';
  }

  @override
  String couldNotGiveRole(String name) {
    return 'The role could not be changed for $name.';
  }

  @override
  String couldNotChangeAdmin(String name) {
    return '$name\'s role could not be changed.';
  }

  @override
  String couldNotTimeOut(String name) {
    return '$name could not be timed out.';
  }

  @override
  String couldNotRemoveMember(String name) {
    return '$name could not be removed.';
  }

  @override
  String transferFailed(String name) {
    return '$name could not be made the owner. They may have left the space.';
  }

  @override
  String get verifyByHand => 'Or check by hand';

  @override
  String verifyDoneTitle(String name) {
    return '$name is verified';
  }

  @override
  String verifiedHowTap(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Verified by a tap on $dateString. The key came from their own device.';
  }

  @override
  String verifiedHowQr(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'You scanned the code on their screen on $dateString. The key came from their own device.';
  }

  @override
  String verifiedHowWords(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'You compared the four words on $dateString.';
  }

  @override
  String verifiedHowCode(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'You swapped the long code on $dateString.';
  }

  @override
  String get verifiedHowUnknown => 'Verified before DNet noted how.';

  @override
  String get verifyAutoNotYet => 'Not verified yet';

  @override
  String get verifyAutoBody =>
      'Scan the code on their screen, or tap the two together if both have NFC. DNet checks the key came from their own device and verifies them by itself.';

  @override
  String get verifyAutoOff =>
      'Verifying automatically is off in Privacy and security. Scanning their code here still verifies them.';

  @override
  String verifyAutoNoWays(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'This PC',
      'other': 'This phone',
    });
    return '$_temp0 cannot scan a code or tap phones. Check by hand below.';
  }

  @override
  String get verifyTogetherTitle => 'Together: compare four words';

  @override
  String verifyTogetherBody(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'devices',
      'other': 'phones',
    });
    return 'Read them to each other, in person or on a call. Both $_temp0 must show the same four.';
  }

  @override
  String verifyKeyChangeNote(String name) {
    return 'If $name\'s key ever changes, they go back to not verified and you are told.';
  }

  @override
  String get verifyDoneAction => 'Done';

  @override
  String verifiedToast(String name) {
    return '$name is verified.';
  }

  @override
  String get tapVerified => 'Verified. The key came from their own device.';

  @override
  String get personCheckOtherWay => 'Cannot see the pictures? Type instead';

  @override
  String get personCheckPicturesInstead => 'Use the pictures instead';

  @override
  String personCheckTypePrompt(String numbers) {
    return 'Quick check that you are a person: type these numbers as digits. $numbers';
  }

  @override
  String get personCheckTypeLabel => 'The numbers, as digits';

  @override
  String get personCheckTypeCheck => 'Check';

  @override
  String get personCheckWait =>
      'Too many wrong answers. Try again in a few seconds.';

  @override
  String get numberWords => 'zero,one,two,three,four,five,six,seven,eight,nine';

  @override
  String get makingKeyTitle => 'Making your key';

  @override
  String makingKeyBody(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'PC',
      'other': 'phone',
    });
    return 'A few seconds of work on this $_temp0. It shows other devices that a person made this identity, not a program making thousands.';
  }

  @override
  String makingKeyProgress(int percent) {
    return '$percent% done';
  }

  @override
  String get welcomePoint4Title => 'Groups without a server';

  @override
  String get welcomePoint4Body =>
      'Spaces with channels and voice rooms live on members\' devices.';

  @override
  String get welcomeCreateTitle => 'Create your identity';

  @override
  String get welcomeCreateBody =>
      'All it takes is a name. No number, no email, no account.';

  @override
  String welcomeOpenSource(String version) {
    return 'Open source · MIT License · Version $version';
  }

  @override
  String get termsOfUse => 'Terms of Use';

  @override
  String get termsDocTitle => 'Terms of Use and Disclaimer';

  @override
  String termsDocVersion(int version, DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Version $version · last changed $dateString';
  }

  @override
  String get termsGateIntro =>
      'Before you start, please read the terms of use to the end and accept them. DNet opens only after you do.';

  @override
  String get termsGateChanged =>
      'The terms have changed since you last accepted them. Please read and accept the new version to keep using DNet.';

  @override
  String get termsInShort => 'In short';

  @override
  String get termsShortAsIs =>
      'DNet is given as it is, with no warranty. You use it at your own risk.';

  @override
  String get termsShortLawful =>
      'You alone are responsible for using it lawfully, including radio bands, power and licences.';

  @override
  String get termsShortEmergency =>
      'It is not for emergencies. Messages may not arrive, and may not stay private.';

  @override
  String get termsShortEarly =>
      'It is early software, not independently audited and not yet verified on devices.';

  @override
  String get termsShortNoServers =>
      'The authors run no servers and collect nothing. Your data stays on devices.';

  @override
  String get termsInShortNote =>
      'This summary only helps you read. The full terms below are what you agree to.';

  @override
  String get termsContents => 'Contents';

  @override
  String get termsReadToEnd => 'Read to the end to accept';

  @override
  String get termsReachedEnd => 'You\'ve reached the end';

  @override
  String termsReadProgress(int percent) {
    return '$percent% read';
  }

  @override
  String get termsAgreeBox =>
      'I have read and agree to the Terms of Use and Disclaimer';

  @override
  String get termsAccept => 'Accept';

  @override
  String get termsDecline => 'Decline';

  @override
  String get termsDeclinedTitle => 'DNet stays closed';

  @override
  String get termsDeclinedBody =>
      'You declined the Terms of Use, so DNet won\'t start. Nothing has been opened, sent or changed. You can read the terms again, or quit.';

  @override
  String get termsReadAgain => 'Read the terms again';

  @override
  String get termsQuit => 'Quit DNet';

  @override
  String termsAcceptedOn(int version, DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'You accepted version $version on $dateString.';
  }

  @override
  String get termsDocIntro =>
      'These Terms of Use and Disclaimer (\"terms\") are an agreement between you and the authors and contributors of DNet (together, \"the authors\"). They apply to your use of the DNet app and of everything it does on your device (\"DNet\"). Please read all of them. They limit the authors\' responsibility to you, and they make you responsible for how you use DNet.\n\nYou must accept these terms before DNet can be used. If you do not agree with them, choose Decline and do not use DNet.';

  @override
  String get termsDoc1Title => 'What DNet is';

  @override
  String get termsDoc1Body =>
      'DNet is free, open-source software for sending messages, calls and files directly between devices without the internet. Devices reach each other over Bluetooth, over Wi-Fi on the same local network, over Wi-Fi Direct and, if you connect one, through an external LoRa radio. When the person you want is out of range, encrypted messages may be passed along by other DNet devices.\n\nThe authors do not run any server, network or messaging service for DNet. They do not carry, store, see, check or control any message, call, file, name, location or other content sent with it, and they cannot do so. DNet is a tool that runs on your device and on the devices of the people you talk to.';

  @override
  String get termsDoc2Title => 'Accepting these terms';

  @override
  String get termsDoc2Body =>
      'By ticking \"I have read and agree\" and choosing Accept, you confirm that you have read and understood these terms and agree to be bound by them. DNet keeps a record on your device of which version of the terms you accepted, and when. If you do not accept them, DNet will not open.\n\nIf you use DNet for or on behalf of an organisation, you confirm that you have the authority to accept these terms for it, and \"you\" then includes that organisation.';

  @override
  String get termsDoc3Title => 'Who may use DNet';

  @override
  String get termsDoc3Body =>
      'You may use DNet only if you are old enough, under the law that applies to you, to use communication services like it and to accept these terms yourself. If you are below that age, you may use DNet only with the permission and supervision of a parent or legal guardian, who accepts these terms for you and is responsible for your use.\n\nYou may not use DNet where the law that applies to you forbids it, or if you have been barred from using software like it.';

  @override
  String get termsDoc4Title => 'You are responsible for lawful use';

  @override
  String get termsDoc4Body =>
      'You alone are responsible for how you use DNet, and for making sure that your use is lawful where you are and wherever your messages or radio signals reach. Laws differ from country to country and change over time. Among other things, you are responsible for following the laws and rules on:\n• Encryption: some countries restrict the use, import or export of encryption software.\n• Radio: if you connect a LoRa or other radio, you must choose only a frequency band that is allowed where you are, and keep to its rules on transmit power, antennas, duty cycle or airtime, channel use, and any licence, registration or certification. DNet\'s region choices and airtime limits are only an aid. They are not legal advice and may be wrong, incomplete or out of date.\n• Bluetooth, Wi-Fi and Wi-Fi Direct: where and when wireless devices may be used, including on aircraft, in hospitals and at secure or restricted sites.\n• Recording and capture: recording, saving or sharing calls, voices, screens, screenshots, photos or the location of other people may need their consent and may be restricted.\n• Content: everything you send, share or publish with DNet, including in spaces and public channels, and any rights that others have in it.\n• Privacy and data protection: any duties you have when you collect, keep or share information about other people.\n\nNothing in DNet, its documentation or these terms is legal advice. If you are unsure whether something is allowed where you are, find out before you do it.';

  @override
  String get termsDoc5Title => 'Things you must not do';

  @override
  String get termsDoc5Body =>
      'You agree not to use DNet, or help or allow anyone else to use it, to:\n• break any law or regulation, or encourage or help anyone else to break one;\n• create, send, keep or share illegal content, including content that sexually exploits or endangers children, incites violence, hatred or terrorism, or is fraudulent;\n• harass, threaten, stalk, bully, intimidate, impersonate or deceive anyone, or send unwanted messages in bulk;\n• infringe anyone\'s copyright, trademark, privacy, publicity or other rights, or share another person\'s private information or images without the right to;\n• track, watch or locate a person without their knowledge and consent;\n• interfere with, disrupt or overload any network, device, service or radio frequency, including by transmitting where, when, at a power or for longer than is allowed, or by deliberately causing interference to other radio users;\n• get into any device, account or data without permission, or spread malware;\n• make identities in bulk, or get around DNet\'s protections, such as the identity stamp, chat requests, blocking or the app lock, to reach or harm other people;\n• plan or carry out anything that could cause death, injury, or damage to property or the environment.\n\nThe authors cannot see how DNet is used and do not monitor it, but none of these uses is allowed.';

  @override
  String get termsDoc6Title => 'Not for emergencies or critical use';

  @override
  String get termsDoc6Body =>
      'DNet is not an emergency service and cannot contact emergency services. Do not rely on it for emergency, life-safety or other critical communication: not as your only way to call for help, not to coordinate rescue or medical care, and not for anything where a failure, delay or loss of a message could lead to death, injury, or serious damage to property or the environment. This includes medical, aviation, maritime, vehicle, industrial-control and disaster-response use. Always keep another way to reach help.';

  @override
  String get termsDoc7Title =>
      'No promise that messages arrive or stay private';

  @override
  String get termsDoc7Body =>
      'DNet works only when other devices are within range and the links between them happen to work. Messages, calls and files may be delayed, arrive out of order, arrive more than once, arrive incomplete or not arrive at all, and DNet may not be able to tell you which. A message shown as sent, relayed or delivered may still not have been read.\n\nDNet is designed to protect what you send with end-to-end encryption, but no software is perfect. The authors do not promise that DNet is secure, that it will keep your messages, calls, files, identity or location private, or that it will hide the fact that you use it. People near you may be able to tell that your device is sending radio signals, and anyone listening on a LoRa band can see that two DNet radios are talking, when, and how much. Known limits are listed in SECURITY.md in the source code.\n\nOnce you send something, the people who receive it can keep, copy, record, photograph or pass it on, and neither you nor the authors can take it back. Disappearing messages, view-once media and deleting a message depend on the other person\'s device, and cannot stop them from keeping a copy.';

  @override
  String get termsDoc8Title => 'Early software, not independently audited';

  @override
  String get termsDoc8Body =>
      'DNet is early-stage software. It has had an internal security review but no independent security audit, and its Bluetooth, Wi-Fi Direct, mesh relay, NFC, screen sharing and LoRa radio features have not yet been verified between real devices. It may have bugs and security flaws. It may lose or damage data, use a lot of battery or other resources, behave differently on different devices, and change or stop working without notice. Do not rely on it to protect anyone, and keep your own copies of anything important.';

  @override
  String get termsDoc9Title => 'Your data stays with you';

  @override
  String get termsDoc9Body =>
      'The authors run no servers and collect no data. DNet has no accounts, analytics, advertising or tracking, and it sends nothing to the authors. Your identity, messages, contacts and settings are kept encrypted on your device, together with the record of the terms you accepted.\n\nUsing DNet means your device exchanges information with other devices, directly or through other DNet devices: for example the name you choose, your public key, and, when you choose to send them, messages, files, photos, your status or your location. Your device may also pass on other people\'s sealed messages, which it cannot read; you can turn this off in Privacy. What other people receive is on their devices, outside your control and outside the authors\' control.\n\nYou are responsible for your device and its security, for keeping DNet and your system up to date, for your app lock passcode, and for keeping copies of anything you need. If you lose your device, forget your passcode or wipe DNet, your data may be gone for good: the authors hold no copy and cannot recover it.';

  @override
  String get termsDoc10Title => 'Other people, devices and links';

  @override
  String get termsDoc10Body =>
      'DNet puts you in touch with people the authors do not know. The authors are not responsible for other users, their content or their conduct, or for what they do with what you send them. Content you receive may be false, offensive, harmful or illegal, and the authors do not review it. Think before you accept a chat request or verify someone, and use Decline and Block when you need to.\n\nRadios, boards, firmware and other hardware or software made by others, such as Meshtastic devices, are not made or supported by the authors. Their makers\' terms, and the law where you use them, apply to them.\n\nDNet never opens a link by itself. If you choose to open a link, it opens in your own browser, outside DNet, and the authors are not responsible for the site or for what happens there.';

  @override
  String get termsDoc11Title => 'No warranty';

  @override
  String get termsDoc11Body =>
      'DNET IS PROVIDED \"AS IS\" AND \"AS AVAILABLE\", WITH ALL FAULTS AND WITHOUT WARRANTY OF ANY KIND. To the fullest extent the law allows, the authors disclaim all warranties, conditions and terms, whether express, implied or statutory, including any of merchantability, satisfactory quality, fitness for a particular purpose, title, non-infringement, accuracy, security, availability and quiet enjoyment, and any arising from a course of dealing or usage of trade.\n\nThe authors do not warrant that DNet will meet your needs, that it will work without interruption or error, that it is secure or free of harmful components, that defects will be fixed, or that it will work with any particular device, radio or operating system. No advice or information, spoken or written, that you get from the authors or from anywhere else creates any warranty. You use DNet entirely at your own risk.';

  @override
  String get termsDoc12Title => 'Limitation of liability';

  @override
  String get termsDoc12Body =>
      'TO THE FULLEST EXTENT THE LAW ALLOWS, IN NO EVENT WILL THE AUTHORS, CONTRIBUTORS OR COPYRIGHT HOLDERS BE LIABLE to you or to anyone else for any direct, indirect, incidental, special, consequential, exemplary or punitive damages, or for any loss of data, messages, privacy, profits, revenue, goodwill, business or opportunity, any damage to devices or equipment, any personal injury or death, or the cost of any substitute service, arising out of or in connection with DNet or these terms, however caused and on any theory of liability, whether in contract, tort (including negligence), strict liability or otherwise, even if they were told that such damage was possible. This includes anything done, sent or not done by other people using DNet.\n\nWhere the law does not allow liability to be excluded completely, the authors\' total liability is limited to the smallest amount the law allows. DNet is given away free of charge, and you agree that these limits are a fair basis for that.\n\nSome places do not allow certain warranties to be excluded or certain liability to be limited, such as liability for death or personal injury caused by negligence, or for fraud. There, the exclusions and limits in these terms apply only as far as the law allows, and nothing in these terms takes away any right you have that cannot be changed by agreement.';

  @override
  String get termsDoc13Title => 'Indemnity';

  @override
  String get termsDoc13Body =>
      'To the fullest extent the law allows, you agree to defend, indemnify and hold harmless the authors and contributors against any claim, demand, action, loss, liability, damage, fine, penalty, cost or expense, including reasonable legal fees, that arises from or relates to: your use of DNet; anything you send, share or publish with it; your breach of these terms; your breach of any law or regulation, including rules on radio and encryption; or your infringement of anyone else\'s rights.';

  @override
  String get termsDoc14Title => 'The open-source licence';

  @override
  String get termsDoc14Body =>
      'DNet\'s source code is published under the MIT License, which you can read in the app under About and in the LICENSE file of the source code. These terms cover your use of DNet. They do not take away any right that the licence gives you to use, copy, change or share the source code, and the licence\'s own disclaimer of warranty and limitation of liability apply as well as these terms.\n\nIf you change DNet or share a copy of it, changed or not, you are responsible for that copy, and you must not suggest that the authors made, checked or approve of your version. Software and fonts that DNet includes from others come under their own licences, listed in About under Open-source licences.';

  @override
  String get termsDoc15Title => 'Changes to DNet and to these terms';

  @override
  String get termsDoc15Body =>
      'The authors may change, pause or stop work on DNet at any time without notice, and they have no obligation to provide updates, fixes or support.\n\nThe authors may change these terms. When a later version of DNet comes with changed terms, it asks you to read and accept them before you can go on using it. If you do not accept the changed terms, stop using DNet. The version of the terms you accepted, and when, is kept on your device and shown in About.';

  @override
  String get termsDoc16Title => 'Stopping use';

  @override
  String get termsDoc16Body =>
      'You can stop using DNet at any time: wipe its data from Privacy and remove the app. If you break these terms, you are no longer allowed to use DNet. The sections on lawful use, things you must not do, no warranty, limitation of liability and indemnity, and these general terms, keep applying to anything that happened before you stopped.';

  @override
  String get termsDoc17Title => 'General terms';

  @override
  String get termsDoc17Body =>
      'If any part of these terms is found invalid or unenforceable, it is limited or changed only as far as needed to make it enforceable, and the rest of the terms remain in full force.\n\nIf the authors do not enforce any part of these terms, that does not mean they give up the right to do so later.\n\nThese terms, together with the open-source licence, are the whole agreement between you and the authors about DNet, and they replace anything said before. Every author and contributor may rely on them. You may not transfer your rights or duties under them to anyone else.\n\nHeadings are there to help you read. They do not change what the terms mean.\n\nQuestions about DNet or these terms can be raised on the project\'s GitHub page, linked from About. Security problems should be reported privately, as SECURITY.md in the source code describes.';

  @override
  String get termsDocClosing =>
      'By ticking \"I have read and agree\" and choosing Accept, you confirm that you have read these terms to the end, that you understand them, that you are allowed to accept them, and that you agree to them.';

  @override
  String get aboutTagline => 'Your offline connector';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get aboutVersionCopied => 'Version copied';

  @override
  String get aboutCopyVersion => 'Copy the version, for a bug report';

  @override
  String get aboutPurposeTitle => 'What it\'s for';

  @override
  String get aboutPurposeBody =>
      'DNet lets you chat, call and share files with the people around you when there is no internet, no signal and no server, or when you would rather not use them. There is no account, no number and no email: your identity is a key made on your device, and all it needs is a name.';

  @override
  String get aboutAimTitle => 'What it aims for';

  @override
  String get aboutAimBody =>
      'To keep people in touch when networks fail, are switched off or can\'t be trusted: at events, while travelling, in remote places and during outages. Private by default, owned by nobody, and open for anyone to check.';

  @override
  String get aboutHowTitle => 'How it works';

  @override
  String get aboutHowNearbyTitle => 'Finds people nearby';

  @override
  String get aboutHowNearbyBody =>
      'Devices find each other over Bluetooth and Wi-Fi, with no internet.';

  @override
  String get aboutHowMeshTitle => 'Passes messages along';

  @override
  String get aboutHowMeshBody =>
      'Out of range? Sealed messages hop through other DNet devices, which can\'t read them.';

  @override
  String get aboutHowSealedTitle => 'Encrypted end to end';

  @override
  String get aboutHowSealedBody =>
      'Each message is sealed on your device for the one person it\'s for.';

  @override
  String get aboutHowSpacesTitle => 'Spaces for groups';

  @override
  String get aboutHowSpacesBody =>
      'Channels and voice rooms, kept on members\' devices. No server.';

  @override
  String get aboutHowRadioTitle => 'Long range by radio';

  @override
  String get aboutHowRadioBody =>
      'Plug in a LoRa radio to send text for kilometres, on the band that is legal where you are.';

  @override
  String get aboutStatusTitle => 'Where it stands';

  @override
  String get aboutStatusBody =>
      'This is an early build. It has had an internal security review but has not had an independent security review, and its Bluetooth, Wi-Fi Direct, mesh and LoRa links have not yet been verified on devices. Don\'t rely on it to protect anyone, or in an emergency.';

  @override
  String get aboutLinksTitle => 'Source code and help';

  @override
  String get aboutGithub => 'Source code on GitHub';

  @override
  String get aboutGithubDetail =>
      'See how DNet works, build it yourself, help out';

  @override
  String get aboutIssues => 'Report a bug or ask for a feature';

  @override
  String get aboutIssuesDetail =>
      'Issues on GitHub. Report security problems privately, as SECURITY.md says.';

  @override
  String get aboutLegalTitle => 'Legal';

  @override
  String get aboutTermsDetail => 'What you agreed to before using DNet';

  @override
  String get aboutLicence => 'MIT License';

  @override
  String get aboutLicenceDetail =>
      'Free to use, change and share. No warranty.';

  @override
  String get aboutOpenSource => 'Open-source licences';

  @override
  String get aboutOpenSourceDetail =>
      'The software and fonts DNet is built with';

  @override
  String get aboutFooter =>
      'Made in the open by the DNet authors. No servers, no tracking, no ads.';

  @override
  String get privacyWhoCanReach => 'Who can reach me';

  @override
  String get privacyWhatOthersSee => 'What others see. Off keeps you private.';

  @override
  String get privacySafety => 'Safety';

  @override
  String get requestsFromTitle => 'Who can send me chat requests';

  @override
  String get requestsFromEveryone => 'Everyone nearby';

  @override
  String get requestsFromSpaces => 'People in my spaces';

  @override
  String get requestsFromNobody => 'Nobody';

  @override
  String get requestsFromNote =>
      'Someone you send your own link to can always ask.';

  @override
  String get autoVerifySwitch => 'Verify people automatically';

  @override
  String get autoVerifyDetail =>
      'When you scan the code on their screen, or tap with NFC';

  @override
  String get relaySwitch => 'Pass on messages for others';

  @override
  String get relayDetail => 'Sealed, so this device cannot read them';

  @override
  String get verifiedFilesOnlySwitch =>
      'Ask before saving files from people not verified';

  @override
  String get lockAfterTitle => 'Lock after leaving the app';

  @override
  String lockAfterChoice(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes min',
      zero: 'At once',
    );
    return '$_temp0';
  }

  @override
  String get lockAfterHour => '1 hour';

  @override
  String get emojiSearch => 'Search emoji';

  @override
  String get emojiNoMatch => 'No emoji match that.';

  @override
  String get skinTone => 'Skin tone';

  @override
  String skinToneName(String tone) {
    String _temp0 = intl.Intl.selectLogic(tone, {
      '0': 'No skin tone',
      '1': 'Light',
      '2': 'Medium light',
      '3': 'Medium',
      '4': 'Medium dark',
      '5': 'Dark',
      'other': 'Skin tone',
    });
    return '$_temp0';
  }

  @override
  String chooseSkinTone(String emoji) {
    return 'Choose a skin tone for $emoji';
  }

  @override
  String emojiInTone(String emoji, String tone) {
    return '$emoji, $tone';
  }

  @override
  String get favouriteStickers => 'Favourites';

  @override
  String get noFavouriteStickers => 'Press and hold a sticker to add it here.';

  @override
  String get newSticker => 'New sticker';

  @override
  String get stickerPacksTitle => 'Your sticker packs';

  @override
  String get arrangeStickers => 'Arrange stickers';

  @override
  String get addToFavourites => 'Add to favourites';

  @override
  String get removeFromFavourites => 'Remove from favourites';

  @override
  String get moveToPack => 'Move to another pack';

  @override
  String get saveToPack => 'Save to a pack';

  @override
  String get chooseStickerPack => 'Which pack?';

  @override
  String get newStickerPack => 'New pack';

  @override
  String get stickerPackName => 'Pack name';

  @override
  String get renameStickerPack => 'Rename pack';

  @override
  String get deleteStickerPack => 'Delete pack';

  @override
  String deleteStickerPackBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Its $count stickers are deleted from this device.',
      one: 'Its 1 sticker is deleted from this device.',
      zero: 'The pack is empty.',
    );
    return '$_temp0';
  }

  @override
  String get stickerPackDeleted => 'Pack deleted.';

  @override
  String get stickerPackFull => 'No more packs can be made.';

  @override
  String stickerPackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stickers',
      one: '1 sticker',
      zero: 'No stickers yet',
    );
    return '$_temp0';
  }

  @override
  String get stickerPackEmpty => 'No stickers in this pack yet.';

  @override
  String get noStickerPacks =>
      'Make a sticker from a photo, or save one someone sent you, and it goes in a pack here.';

  @override
  String get moveUp => 'Move up';

  @override
  String get moveDown => 'Move down';

  @override
  String get moveEarlier => 'Move earlier';

  @override
  String get moveLater => 'Move later';

  @override
  String get stickerMoved => 'Moved.';

  @override
  String get stickerFromPhoto => 'Choose a photo';

  @override
  String get stickerFromCamera => 'Take a photo';

  @override
  String get stickerEditorTitle => 'New sticker';

  @override
  String get stickerShape => 'Shape';

  @override
  String get stickerShapeFree => 'As cut';

  @override
  String get stickerShapeRounded => 'Rounded';

  @override
  String get stickerShapeCircle => 'Circle';

  @override
  String get stickerCropHint =>
      'Drag the frame, or its corners, to choose what goes in the sticker.';

  @override
  String get stickerCutOut => 'Remove the background';

  @override
  String get stickerCutOutDetail =>
      'Works best on a plain background. Done on this device.';

  @override
  String get stickerCutOutFailed =>
      'The background could not be told apart here. Try a plainer one.';

  @override
  String get stickerWords => 'Words on the sticker';

  @override
  String get stickerWordsHint => 'Optional';

  @override
  String get stickerSaveTo => 'Save to';

  @override
  String get saveSticker => 'Save sticker';

  @override
  String get stickerMade => 'Sticker saved.';

  @override
  String get stickerPhotoUnreadable => 'This photo can\'t be opened.';

  @override
  String get stickerCropFrame => 'Crop frame';

  @override
  String packMenuLabel(String name) {
    return 'More for $name';
  }

  @override
  String get screenShare => 'Share screen';

  @override
  String get screenShareStop => 'Stop sharing';

  @override
  String get screenShareYouAre => 'You\'re sharing your screen';

  @override
  String screenShareYouAreWindow(String name) {
    return 'You\'re sharing $name';
  }

  @override
  String get screenShareStopShort => 'Stop';

  @override
  String get screenSharePickTitle => 'Share your screen';

  @override
  String get screenSharePickNote =>
      'Only what you pick is shared, and only while you\'re in this call.';

  @override
  String get screenShareWhole => 'Whole screen';

  @override
  String screenShareNumber(int number) {
    return 'Screen $number';
  }

  @override
  String get screenShareMain => 'Main screen';

  @override
  String get screenShareWindows => 'One window';

  @override
  String get screenShareNothing => 'There is nothing to share right now.';

  @override
  String get screenShareNeedsWifi =>
      'Sharing a screen needs Wi-Fi nearby. Bluetooth is too slow for it.';

  @override
  String get screenShareNeedsWifiShort => 'Share screen: needs Wi-Fi nearby';

  @override
  String get screenShareFailed => 'Your screen was not shared.';

  @override
  String get screenShareEnded => 'Screen sharing stopped.';

  @override
  String screenShareTheirs(String name) {
    return '$name\'s screen';
  }

  @override
  String get screenShareSharing => 'Sharing screen';

  @override
  String get screenShareEnlarge => 'Enlarge';

  @override
  String get screenShareShrink => 'Make smaller';

  @override
  String get screenShareWaiting => 'Waiting for the screen';

  @override
  String get screenShareNoticeTitle => 'Sharing your screen';

  @override
  String get screenShareNoticeText =>
      'Everyone in the call can see it. Open DNet to stop.';

  @override
  String get noticeChannelMessages => 'Messages';

  @override
  String get noticeChannelCalls => 'Calls';

  @override
  String noticeNewMessages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new messages',
      one: 'New message',
    );
    return '$_temp0';
  }

  @override
  String get noticeRequestTitle => 'Chat request';

  @override
  String noticeRequestText(String name) {
    return '$name wants to chat with you';
  }

  @override
  String get noticeRequestHidden => 'Someone wants to chat with you';

  @override
  String noticeMention(String channel) {
    return 'You were mentioned in #$channel';
  }

  @override
  String get noticeMentionHidden => 'You were mentioned in a space';

  @override
  String get noticeCallTitle => 'Incoming call';

  @override
  String noticeCallText(String name) {
    return '$name is calling';
  }

  @override
  String get noticeCallHidden => 'Someone is calling';

  @override
  String get trayOpen => 'Open DNet';

  @override
  String get trayQuit => 'Quit DNet';

  @override
  String get trayStillRunningTitle => 'DNet is still running';

  @override
  String get trayStillRunningText =>
      'It keeps finding people and taking messages. Quit from the tray icon.';

  @override
  String get notificationsHeading => 'Notifications and background';

  @override
  String get notificationsSwitch => 'Notifications';

  @override
  String notificationsDetail(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'Messages, chat requests, mentions and calls while DNet\'s window is not in front.',
      'other': 'Messages, chat requests, mentions and calls while DNet is not on screen.',
    });
    return '$_temp0';
  }

  @override
  String get notifyTextSwitch => 'Show what was said';

  @override
  String get notifyTextDetail =>
      'Off: only who it is from. With an app lock, a notification never shows who or what.';

  @override
  String get backgroundSwitch => 'Keep running in the background';

  @override
  String backgroundDetail(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'Closing the window keeps DNet in the tray, finding people and taking messages. Quit from the tray icon.',
      'other': 'DNet goes on finding people and taking messages after you leave it, with a notice that says so.',
    });
    return '$_temp0';
  }

  @override
  String notificationsBlocked(String device) {
    String _temp0 = intl.Intl.selectLogic(device, {
      'pc': 'Windows has notifications for DNet turned off. Turn them on in Windows Settings.',
      'other': 'Notifications for DNet are turned off. Turn them on in the phone\'s settings.',
    });
    return '$_temp0';
  }
}
