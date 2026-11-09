import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'DNet'**
  String get appName;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @riskyFileWarning.
  ///
  /// In en, this message translates to:
  /// **'This kind of file can run a program. Only open it if you trust who sent it and expected it.'**
  String get riskyFileWarning;

  /// No description provided for @linkCheckTitle.
  ///
  /// In en, this message translates to:
  /// **'Before you open this link'**
  String get linkCheckTitle;

  /// No description provided for @linkGoesTo.
  ///
  /// In en, this message translates to:
  /// **'This link really goes to'**
  String get linkGoesTo;

  /// No description provided for @linkTrackingRemoved.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 tracking part taken off} other{{count} tracking parts taken off}}'**
  String linkTrackingRemoved(int count);

  /// No description provided for @linkWarnLookalike.
  ///
  /// In en, this message translates to:
  /// **'The name uses letters from another alphabet that look like normal ones. It may be pretending to be a site you know.'**
  String get linkWarnLookalike;

  /// No description provided for @linkWarnHiddenName.
  ///
  /// In en, this message translates to:
  /// **'The words before the @ are not where it goes. It goes to the site shown above.'**
  String get linkWarnHiddenName;

  /// No description provided for @linkWarnNumbersOnly.
  ///
  /// In en, this message translates to:
  /// **'The address is only numbers, with no name you can check.'**
  String get linkWarnNumbersOnly;

  /// No description provided for @linkWarnNotPrivate.
  ///
  /// In en, this message translates to:
  /// **'It starts with http://, so what you send there is not private.'**
  String get linkWarnNotPrivate;

  /// No description provided for @linkCheckNote.
  ///
  /// In en, this message translates to:
  /// **'Only open links from people you trust. DNet never opens or previews links by itself. To visit it, copy it into your browser.'**
  String get linkCheckNote;

  /// No description provided for @copyCleanLink.
  ///
  /// In en, this message translates to:
  /// **'Copy the link'**
  String get copyCleanLink;

  /// No description provided for @linkLeavesApp.
  ///
  /// In en, this message translates to:
  /// **'Opening it leaves DNet. Your browser shows the page, and the site can see that you visited.'**
  String get linkLeavesApp;

  /// No description provided for @linkWarnDisguised.
  ///
  /// In en, this message translates to:
  /// **'The words \"{shown}\" look like a different link. It really goes to the site shown above.'**
  String linkWarnDisguised(String shown);

  /// No description provided for @linkOpenNote.
  ///
  /// In en, this message translates to:
  /// **'Only open links from people you trust. DNet never opens or previews a link by itself.'**
  String get linkOpenNote;

  /// No description provided for @openLink.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get openLink;

  /// No description provided for @linkNotOpened.
  ///
  /// In en, this message translates to:
  /// **'The link could not be opened here. Copy it into your browser instead.'**
  String get linkNotOpened;

  /// No description provided for @webLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied.'**
  String get webLinkCopied;

  /// No description provided for @linksNotAllowedHere.
  ///
  /// In en, this message translates to:
  /// **'Links cannot be sent here. The owner keeps links out of this channel.'**
  String get linksNotAllowedHere;

  /// No description provided for @writingPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get writingPreview;

  /// No description provided for @formatHelp.
  ///
  /// In en, this message translates to:
  /// **'Formatting help'**
  String get formatHelp;

  /// No description provided for @formatHelpHint.
  ///
  /// In en, this message translates to:
  /// **'You can use **bold**, lists, quotes and more. See how'**
  String get formatHelpHint;

  /// No description provided for @formatHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'Formatting'**
  String get formatHelpTitle;

  /// No description provided for @formatHelpBody.
  ///
  /// In en, this message translates to:
  /// **'Type these marks around your words. They change once sent.'**
  String get formatHelpBody;

  /// No description provided for @formatSamples.
  ///
  /// In en, this message translates to:
  /// **'**bold**\n*italic*\n~~struck out~~\n`code`\n||spoiler||\n# Heading\n- a list\n1. a numbered list\n> a quote\n[words](example.com)'**
  String get formatSamples;

  /// No description provided for @formatSampleCode.
  ///
  /// In en, this message translates to:
  /// **'a block of code'**
  String get formatSampleCode;

  /// No description provided for @formatSafeNote.
  ///
  /// In en, this message translates to:
  /// **'Marks never show pictures or open anything. A link still says where it goes before it opens.'**
  String get formatSafeNote;

  /// No description provided for @awayMark.
  ///
  /// In en, this message translates to:
  /// **'Away'**
  String get awayMark;

  /// No description provided for @awayMarkWith.
  ///
  /// In en, this message translates to:
  /// **'Away: {note}'**
  String awayMarkWith(String note);

  /// No description provided for @awayNow.
  ///
  /// In en, this message translates to:
  /// **'You are away: {note}. Anyone who calls on you or messages you is told.'**
  String awayNow(String note);

  /// No description provided for @awayNowPlain.
  ///
  /// In en, this message translates to:
  /// **'You are away. Anyone who calls on you or messages you is told.'**
  String get awayNowPlain;

  /// No description provided for @awayNotSet.
  ///
  /// In en, this message translates to:
  /// **'You could not be marked away.'**
  String get awayNotSet;

  /// No description provided for @youAreAway.
  ///
  /// In en, this message translates to:
  /// **'You are away: {note}'**
  String youAreAway(String note);

  /// No description provided for @youAreAwayPlain.
  ///
  /// In en, this message translates to:
  /// **'You are away'**
  String get youAreAwayPlain;

  /// No description provided for @imBack.
  ///
  /// In en, this message translates to:
  /// **'I\'m back'**
  String get imBack;

  /// No description provided for @personAway.
  ///
  /// In en, this message translates to:
  /// **'{name} is away: {note}'**
  String personAway(String name, String note);

  /// No description provided for @personAwayPlain.
  ///
  /// In en, this message translates to:
  /// **'{name} is away'**
  String personAwayPlain(String name);

  /// No description provided for @mentionEveryoneDetail.
  ///
  /// In en, this message translates to:
  /// **'Everyone here'**
  String get mentionEveryoneDetail;

  /// No description provided for @mentionHereDetail.
  ///
  /// In en, this message translates to:
  /// **'Everyone in range now'**
  String get mentionHereDetail;

  /// No description provided for @mentionRoleDetail.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get mentionRoleDetail;

  /// No description provided for @personTag.
  ///
  /// In en, this message translates to:
  /// **'Tag {tag}, from their key'**
  String personTag(String tag);

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @shareContactWarnTitle.
  ///
  /// In en, this message translates to:
  /// **'Share {who}\'s contact with {to}?'**
  String shareContactWarnTitle(String who, String to);

  /// No description provided for @shareContactWarnBody.
  ///
  /// In en, this message translates to:
  /// **'{to} will be able to ask them for a chat. Only share it if they would be happy with that.'**
  String shareContactWarnBody(String to);

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @verified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get verified;

  /// No description provided for @notVerified.
  ///
  /// In en, this message translates to:
  /// **'Not verified'**
  String get notVerified;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @notBuiltYet.
  ///
  /// In en, this message translates to:
  /// **'This part is not built yet.'**
  String get notBuiltYet;

  /// No description provided for @startupFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'DNet could not open your data'**
  String get startupFailedTitle;

  /// No description provided for @startupNewerVersion.
  ///
  /// In en, this message translates to:
  /// **'It was saved by a newer version of DNet. Update the app to open it. Nothing has been changed.'**
  String get startupNewerVersion;

  /// No description provided for @startupWrongKey.
  ///
  /// In en, this message translates to:
  /// **'The key that protects it could not be read on this device. Nothing has been changed.'**
  String get startupWrongKey;

  /// No description provided for @startupOtherFailure.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while reading it. Nothing has been changed.'**
  String get startupOtherFailure;

  /// No description provided for @tabChats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get tabChats;

  /// No description provided for @tabSpaces.
  ///
  /// In en, this message translates to:
  /// **'Spaces'**
  String get tabSpaces;

  /// No description provided for @tabNearby.
  ///
  /// In en, this message translates to:
  /// **'Nearby'**
  String get tabNearby;

  /// No description provided for @tabYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get tabYou;

  /// No description provided for @mainNavigation.
  ///
  /// In en, this message translates to:
  /// **'Main'**
  String get mainNavigation;

  /// No description provided for @welcomeTagline.
  ///
  /// In en, this message translates to:
  /// **'Chat with people around you. No signal needed.'**
  String get welcomeTagline;

  /// No description provided for @welcomePoint1Title.
  ///
  /// In en, this message translates to:
  /// **'Works without internet'**
  String get welcomePoint1Title;

  /// No description provided for @welcomePoint1Body.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{Devices nearby pass messages along.} other{Phones nearby pass messages along.}}'**
  String welcomePoint1Body(String device);

  /// No description provided for @welcomePoint2Title.
  ///
  /// In en, this message translates to:
  /// **'Private by default'**
  String get welcomePoint2Title;

  /// No description provided for @welcomePoint2Body.
  ///
  /// In en, this message translates to:
  /// **'No phone number. No account. Encrypted.'**
  String get welcomePoint2Body;

  /// No description provided for @welcomePoint3Title.
  ///
  /// In en, this message translates to:
  /// **'Sends big files fast'**
  String get welcomePoint3Title;

  /// No description provided for @welcomePoint3Body.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{Straight from device to device over Wi-Fi.} other{Straight from phone to phone over Wi-Fi.}}'**
  String welcomePoint3Body(String device);

  /// No description provided for @yourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get yourName;

  /// No description provided for @random.
  ///
  /// In en, this message translates to:
  /// **'Random'**
  String get random;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get getStarted;

  /// No description provided for @getStartedLocked.
  ///
  /// In en, this message translates to:
  /// **'Do the quick check first.'**
  String get getStartedLocked;

  /// No description provided for @personCheckPrompt.
  ///
  /// In en, this message translates to:
  /// **'Quick check that you are a person: tap the {thing}'**
  String personCheckPrompt(String thing);

  /// No description provided for @personCheckWrong.
  ///
  /// In en, this message translates to:
  /// **'Not that one. Try again.'**
  String get personCheckWrong;

  /// No description provided for @personCheckDone.
  ///
  /// In en, this message translates to:
  /// **'Checked. Thank you.'**
  String get personCheckDone;

  /// No description provided for @checkPadlock.
  ///
  /// In en, this message translates to:
  /// **'padlock'**
  String get checkPadlock;

  /// No description provided for @checkCamera.
  ///
  /// In en, this message translates to:
  /// **'camera'**
  String get checkCamera;

  /// No description provided for @checkBookmark.
  ///
  /// In en, this message translates to:
  /// **'bookmark'**
  String get checkBookmark;

  /// No description provided for @checkSpeechBubble.
  ///
  /// In en, this message translates to:
  /// **'speech bubble'**
  String get checkSpeechBubble;

  /// No description provided for @welcomeFootnote.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{Your key is made on this PC and stays here.} other{Your key is made on this phone and stays here.}}'**
  String welcomeFootnote(String device);

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @newChatRequest.
  ///
  /// In en, this message translates to:
  /// **'New chat request'**
  String get newChatRequest;

  /// No description provided for @chatRequestsBanner.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 chat request} other{{count} chat requests}}'**
  String chatRequestsBanner(int count);

  /// No description provided for @tapToAnswer.
  ///
  /// In en, this message translates to:
  /// **'Tap to answer'**
  String get tapToAnswer;

  /// No description provided for @savedMessages.
  ///
  /// In en, this message translates to:
  /// **'Saved messages'**
  String get savedMessages;

  /// No description provided for @onlyOnThisPhone.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{Only on this PC} other{Only on this phone}}'**
  String onlyOnThisPhone(String device);

  /// No description provided for @chatsFootnote.
  ///
  /// In en, this message translates to:
  /// **'Only people you accepted can message you here.'**
  String get chatsFootnote;

  /// No description provided for @chatsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No chats yet. Find someone nearby to start.'**
  String get chatsEmpty;

  /// No description provided for @disappearingMessages.
  ///
  /// In en, this message translates to:
  /// **'Disappearing messages'**
  String get disappearingMessages;

  /// No description provided for @unreadCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unread message} other{{count} unread messages}}'**
  String unreadCount(int count);

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @chatRequestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat requests'**
  String get chatRequestsTitle;

  /// No description provided for @requestsIntro.
  ///
  /// In en, this message translates to:
  /// **'Nobody can message you until you accept.'**
  String get requestsIntro;

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @decline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get decline;

  /// No description provided for @block.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// No description provided for @alsoInSpace.
  ///
  /// In en, this message translates to:
  /// **'Also in {space}'**
  String alsoInSpace(String space);

  /// No description provided for @noSpacesInCommon.
  ///
  /// In en, this message translates to:
  /// **'No spaces in common'**
  String get noSpacesInCommon;

  /// No description provided for @sentByYou.
  ///
  /// In en, this message translates to:
  /// **'Sent by you'**
  String get sentByYou;

  /// No description provided for @waitingForReply.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a reply'**
  String get waitingForReply;

  /// No description provided for @requestsFootnote.
  ///
  /// In en, this message translates to:
  /// **'People you decline are not told, and must wait a while to ask again. People you block cannot ask again, even under a new name.'**
  String get requestsFootnote;

  /// No description provided for @requestsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No chat requests waiting.'**
  String get requestsEmpty;

  /// No description provided for @blockConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Block {name}?'**
  String blockConfirmTitle(String name);

  /// No description provided for @blockConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'They will not be told, and they cannot ask again. You can unblock them later under Privacy.'**
  String get blockConfirmBody;

  /// No description provided for @newChatTitle.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get newChatTitle;

  /// No description provided for @qrPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'[Your QR code]'**
  String get qrPlaceholder;

  /// No description provided for @shareLink.
  ///
  /// In en, this message translates to:
  /// **'Share link'**
  String get shareLink;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @scanTheirCode.
  ///
  /// In en, this message translates to:
  /// **'Scan their code'**
  String get scanTheirCode;

  /// No description provided for @scanTheirCodeDetail.
  ///
  /// In en, this message translates to:
  /// **'Point your camera at their screen'**
  String get scanTheirCodeDetail;

  /// No description provided for @findNearby.
  ///
  /// In en, this message translates to:
  /// **'Find nearby'**
  String get findNearby;

  /// No description provided for @findNearbyDetail.
  ///
  /// In en, this message translates to:
  /// **'Works with no internet'**
  String get findNearbyDetail;

  /// No description provided for @tapPhones.
  ///
  /// In en, this message translates to:
  /// **'Tap phones together'**
  String get tapPhones;

  /// No description provided for @tapPhonesDetail.
  ///
  /// In en, this message translates to:
  /// **'Hold the two phones back to back'**
  String get tapPhonesDetail;

  /// No description provided for @pasteInvite.
  ///
  /// In en, this message translates to:
  /// **'Paste an invite link'**
  String get pasteInvite;

  /// No description provided for @pasteInviteDetail.
  ///
  /// In en, this message translates to:
  /// **'For someone who is far away'**
  String get pasteInviteDetail;

  /// No description provided for @newChatFootnote.
  ///
  /// In en, this message translates to:
  /// **'They need to accept before either of you can send a message.'**
  String get newChatFootnote;

  /// No description provided for @verifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify {name}'**
  String verifyTitle(String name);

  /// No description provided for @verifyIntro.
  ///
  /// In en, this message translates to:
  /// **'Compare these four words in person or on a call. If they match, this really is {name}\'s {device, select, pc{device} other{phone}}.'**
  String verifyIntro(String name, String device);

  /// No description provided for @scanCodeInstead.
  ///
  /// In en, this message translates to:
  /// **'Scan {name}\'s code instead'**
  String scanCodeInstead(String name);

  /// No description provided for @verifyWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {name}\'s device. You both need to be in range.'**
  String verifyWaiting(String name);

  /// No description provided for @wordsMatch.
  ///
  /// In en, this message translates to:
  /// **'The words match'**
  String get wordsMatch;

  /// No description provided for @wordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'They do not match'**
  String get wordsDoNotMatch;

  /// No description provided for @verifyFootnote.
  ///
  /// In en, this message translates to:
  /// **'Until you verify, {name} keeps a yellow \"Not verified\" tag.'**
  String verifyFootnote(String name);

  /// No description provided for @mismatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Do not trust this chat yet'**
  String get mismatchTitle;

  /// No description provided for @mismatchBody.
  ///
  /// In en, this message translates to:
  /// **'The words did not match, so this may not be {name}\'s {device, select, pc{device} other{phone}}. {name} stays not verified.'**
  String mismatchBody(String name, String device);

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @verifyPerson.
  ///
  /// In en, this message translates to:
  /// **'Not verified. Tap to verify {name}.'**
  String verifyPerson(String name);

  /// No description provided for @callPerson.
  ///
  /// In en, this message translates to:
  /// **'Call {name}'**
  String callPerson(String name);

  /// No description provided for @moreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// No description provided for @encryptedNote.
  ///
  /// In en, this message translates to:
  /// **'Encrypted. Only you two can read this.'**
  String get encryptedNote;

  /// No description provided for @read.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get read;

  /// No description provided for @playVoiceMessage.
  ///
  /// In en, this message translates to:
  /// **'Play voice message'**
  String get playVoiceMessage;

  /// No description provided for @goneInOneDay.
  ///
  /// In en, this message translates to:
  /// **'Gone in 1 day'**
  String get goneInOneDay;

  /// No description provided for @goneInDays.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{Gone in 1 day} other{Gone in {days} days}}'**
  String goneInDays(int days);

  /// No description provided for @goneInHours.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, =1{Gone in 1 hour} other{Gone in {hours} hours}}'**
  String goneInHours(int hours);

  /// No description provided for @goneInMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{Gone in 1 minute} other{Gone in {minutes} minutes}}'**
  String goneInMinutes(int minutes);

  /// No description provided for @disappearingBody.
  ///
  /// In en, this message translates to:
  /// **'What the two of you write here from now on is deleted from both devices after this long. Files, pictures and voice messages are not. It cannot stop someone copying a message first.'**
  String get disappearingBody;

  /// No description provided for @timerOff.
  ///
  /// In en, this message translates to:
  /// **'Off: messages stay'**
  String get timerOff;

  /// No description provided for @timerHour.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get timerHour;

  /// No description provided for @timerDay.
  ///
  /// In en, this message translates to:
  /// **'1 day'**
  String get timerDay;

  /// No description provided for @timerWeek.
  ///
  /// In en, this message translates to:
  /// **'1 week'**
  String get timerWeek;

  /// No description provided for @attachOrShare.
  ///
  /// In en, this message translates to:
  /// **'Attach or share'**
  String get attachOrShare;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @messagePerson.
  ///
  /// In en, this message translates to:
  /// **'Message {name}'**
  String messagePerson(String name);

  /// No description provided for @recordVoiceMessage.
  ///
  /// In en, this message translates to:
  /// **'Record a voice message'**
  String get recordVoiceMessage;

  /// No description provided for @recordingVoice.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get recordingVoice;

  /// No description provided for @sendVoice.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get sendVoice;

  /// No description provided for @voiceMessage.
  ///
  /// In en, this message translates to:
  /// **'Voice message'**
  String get voiceMessage;

  /// No description provided for @micUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The microphone cannot be used. Check that DNet is allowed to use it.'**
  String get micUnavailable;

  /// No description provided for @nearbyOnBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Nearby, on Bluetooth'**
  String get nearbyOnBluetooth;

  /// No description provided for @nearbyOnWifi.
  ///
  /// In en, this message translates to:
  /// **'Nearby, on Wi-Fi'**
  String get nearbyOnWifi;

  /// No description provided for @typingNow.
  ///
  /// In en, this message translates to:
  /// **'typing…'**
  String get typingNow;

  /// No description provided for @reachedThroughHops.
  ///
  /// In en, this message translates to:
  /// **'{count} hops, through {name}'**
  String reachedThroughHops(int count, String name);

  /// No description provided for @outOfRange.
  ///
  /// In en, this message translates to:
  /// **'Out of range'**
  String get outOfRange;

  /// No description provided for @photo.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get photo;

  /// No description provided for @photoNamed.
  ///
  /// In en, this message translates to:
  /// **'Photo: {name}'**
  String photoNamed(String name);

  /// No description provided for @photoCannotBeShown.
  ///
  /// In en, this message translates to:
  /// **'This picture cannot be shown here. Open the file with another app.'**
  String get photoCannotBeShown;

  /// No description provided for @voiceMessagePreview.
  ///
  /// In en, this message translates to:
  /// **'Voice message, {duration}'**
  String voiceMessagePreview(String duration);

  /// No description provided for @spacesNavigation.
  ///
  /// In en, this message translates to:
  /// **'Spaces'**
  String get spacesNavigation;

  /// No description provided for @findOrCreateSpace.
  ///
  /// In en, this message translates to:
  /// **'Find or create a space'**
  String get findOrCreateSpace;

  /// No description provided for @inviteSomeone.
  ///
  /// In en, this message translates to:
  /// **'Invite someone'**
  String get inviteSomeone;

  /// No description provided for @privateSpace.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get privateSpace;

  /// No description provided for @publicSpace.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get publicSpace;

  /// No description provided for @membersCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 member} other{{count} members}}'**
  String membersCount(int count);

  /// No description provided for @sectionInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get sectionInfo;

  /// No description provided for @sectionText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get sectionText;

  /// No description provided for @sectionVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get sectionVoice;

  /// No description provided for @talkingCount.
  ///
  /// In en, this message translates to:
  /// **'{count} talking'**
  String talkingCount(int count);

  /// No description provided for @spaceFootnote.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{Kept on members\' devices. No server.} other{Kept on members\' phones. No server.}}'**
  String spaceFootnote(String device);

  /// No description provided for @spacesEmpty.
  ///
  /// In en, this message translates to:
  /// **'You are not in any space yet.'**
  String get spacesEmpty;

  /// No description provided for @members.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get members;

  /// No description provided for @channelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{space}, {count} nearby'**
  String channelSubtitle(String space, int count);

  /// No description provided for @messageChannel.
  ///
  /// In en, this message translates to:
  /// **'Message #{channel}'**
  String messageChannel(String channel);

  /// No description provided for @heartReaction.
  ///
  /// In en, this message translates to:
  /// **'Heart reaction, {count}'**
  String heartReaction(int count);

  /// No description provided for @agreeReaction.
  ///
  /// In en, this message translates to:
  /// **'Agree reaction, {count}'**
  String agreeReaction(int count);

  /// No description provided for @pollFooter.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 vote} other{{count} votes}}. The app does not show who voted.'**
  String pollFooter(int count);

  /// No description provided for @percent.
  ///
  /// In en, this message translates to:
  /// **'{value}%'**
  String percent(int value);

  /// No description provided for @noMessagesYet.
  ///
  /// In en, this message translates to:
  /// **'No messages yet.'**
  String get noMessagesYet;

  /// No description provided for @pinnedMessage.
  ///
  /// In en, this message translates to:
  /// **'Pinned message'**
  String get pinnedMessage;

  /// No description provided for @shareTitle.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareTitle;

  /// No description provided for @sharePhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get sharePhoto;

  /// No description provided for @shareFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get shareFile;

  /// No description provided for @shareVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get shareVoice;

  /// No description provided for @sharePoll.
  ///
  /// In en, this message translates to:
  /// **'Poll'**
  String get sharePoll;

  /// No description provided for @shareContact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get shareContact;

  /// No description provided for @contactCard.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get contactCard;

  /// No description provided for @chooseContactTitle.
  ///
  /// In en, this message translates to:
  /// **'Send {name} a contact'**
  String chooseContactTitle(String name);

  /// No description provided for @chooseContactBody.
  ///
  /// In en, this message translates to:
  /// **'They get a card they can ask that person for a chat by. That person still has to say yes.'**
  String get chooseContactBody;

  /// No description provided for @noOtherContacts.
  ///
  /// In en, this message translates to:
  /// **'You have nobody else in your chats to pass on yet.'**
  String get noOtherContacts;

  /// No description provided for @askToChat.
  ///
  /// In en, this message translates to:
  /// **'Ask to chat'**
  String get askToChat;

  /// No description provided for @cardAsked.
  ///
  /// In en, this message translates to:
  /// **'Asked. Waiting for their answer.'**
  String get cardAsked;

  /// No description provided for @cardInChats.
  ///
  /// In en, this message translates to:
  /// **'In your chats'**
  String get cardInChats;

  /// No description provided for @cardIsYou.
  ///
  /// In en, this message translates to:
  /// **'This is you'**
  String get cardIsYou;

  /// No description provided for @cardNotSent.
  ///
  /// In en, this message translates to:
  /// **'That could not be sent.'**
  String get cardNotSent;

  /// No description provided for @shareLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get shareLocation;

  /// No description provided for @shareViewOnce.
  ///
  /// In en, this message translates to:
  /// **'View once'**
  String get shareViewOnce;

  /// No description provided for @viewOncePhoto.
  ///
  /// In en, this message translates to:
  /// **'View once photo'**
  String get viewOncePhoto;

  /// No description provided for @viewOnceTapToOpen.
  ///
  /// In en, this message translates to:
  /// **'Tap to open. It can be opened one time.'**
  String get viewOnceTapToOpen;

  /// No description provided for @viewOnceNotOpened.
  ///
  /// In en, this message translates to:
  /// **'Sent. Not opened yet.'**
  String get viewOnceNotOpened;

  /// No description provided for @viewOnceOpened.
  ///
  /// In en, this message translates to:
  /// **'Opened'**
  String get viewOnceOpened;

  /// No description provided for @viewOnceWhileOpen.
  ///
  /// In en, this message translates to:
  /// **'This picture is already deleted from this device. When you close it, it is gone. Nothing can stop someone photographing a screen.'**
  String get viewOnceWhileOpen;

  /// No description provided for @viewOnceNotAPicture.
  ///
  /// In en, this message translates to:
  /// **'View once is for pictures only.'**
  String get viewOnceNotAPicture;

  /// No description provided for @shareCameraCode.
  ///
  /// In en, this message translates to:
  /// **'Camera code'**
  String get shareCameraCode;

  /// No description provided for @sendBigFile.
  ///
  /// In en, this message translates to:
  /// **'Send a big file nearby'**
  String get sendBigFile;

  /// No description provided for @sendBigFileDetail.
  ///
  /// In en, this message translates to:
  /// **'Goes direct at Wi-Fi speed, any size'**
  String get sendBigFileDetail;

  /// No description provided for @bigFileNeedsRange.
  ///
  /// In en, this message translates to:
  /// **'{name} is not in range. Big files go only when you are near each other.'**
  String bigFileNeedsRange(String name);

  /// No description provided for @removeLocationFromPhotos.
  ///
  /// In en, this message translates to:
  /// **'Remove location from photos'**
  String get removeLocationFromPhotos;

  /// No description provided for @cannotCleanTitle.
  ///
  /// In en, this message translates to:
  /// **'This picture may say where it was taken'**
  String get cannotCleanTitle;

  /// No description provided for @cannotCleanBody.
  ///
  /// In en, this message translates to:
  /// **'DNet can take the location out of JPEG and PNG pictures. This is another kind, so it would be sent with whatever the camera wrote into it.'**
  String get cannotCleanBody;

  /// No description provided for @sendAsItIs.
  ///
  /// In en, this message translates to:
  /// **'Send as it is'**
  String get sendAsItIs;

  /// No description provided for @sendingFile.
  ///
  /// In en, this message translates to:
  /// **'Sending file'**
  String get sendingFile;

  /// No description provided for @fileSizeTo.
  ///
  /// In en, this message translates to:
  /// **'{size}, to {name}'**
  String fileSizeTo(String size, String name);

  /// No description provided for @megabytesPerSecond.
  ///
  /// In en, this message translates to:
  /// **'{value} MB/s'**
  String megabytesPerSecond(int value);

  /// No description provided for @sentOfTotal.
  ///
  /// In en, this message translates to:
  /// **'{sent} of {total}'**
  String sentOfTotal(String sent, String total);

  /// No description provided for @aboutMinutesLeft.
  ///
  /// In en, this message translates to:
  /// **'About {minutes} min left'**
  String aboutMinutesLeft(int minutes);

  /// No description provided for @stepFoundOver.
  ///
  /// In en, this message translates to:
  /// **'{transport, select, wifi{Found {name} over Wi-Fi} radio{Found {name} over radio} other{Found {name} over Bluetooth}}'**
  String stepFoundOver(String transport, String name);

  /// No description provided for @stepGoingOverWifi.
  ///
  /// In en, this message translates to:
  /// **'Going over Wi-Fi'**
  String get stepGoingOverWifi;

  /// No description provided for @stepGoingOverRadio.
  ///
  /// In en, this message translates to:
  /// **'Going over radio, which is slow'**
  String get stepGoingOverRadio;

  /// No description provided for @nearbyByRadio.
  ///
  /// In en, this message translates to:
  /// **'Nearby, by radio'**
  String get nearbyByRadio;

  /// No description provided for @linkRadioChatOnly.
  ///
  /// In en, this message translates to:
  /// **'Radio, chat only'**
  String get linkRadioChatOnly;

  /// No description provided for @stepCheckedKey.
  ///
  /// In en, this message translates to:
  /// **'Checked {name}\'s key'**
  String stepCheckedKey(String name);

  /// No description provided for @stepSwitchedToWifi.
  ///
  /// In en, this message translates to:
  /// **'Switched to Wi-Fi for speed'**
  String get stepSwitchedToWifi;

  /// No description provided for @encryption.
  ///
  /// In en, this message translates to:
  /// **'Encryption'**
  String get encryption;

  /// No description provided for @aes256.
  ///
  /// In en, this message translates to:
  /// **'AES-256'**
  String get aes256;

  /// No description provided for @ifTheLinkDrops.
  ///
  /// In en, this message translates to:
  /// **'If the link drops'**
  String get ifTheLinkDrops;

  /// No description provided for @resumesByItself.
  ///
  /// In en, this message translates to:
  /// **'Resumes by itself'**
  String get resumesByItself;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get paused;

  /// No description provided for @voiceRoomSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{space} voice room'**
  String voiceRoomSubtitle(String space);

  /// No description provided for @inviteToRoom.
  ///
  /// In en, this message translates to:
  /// **'Invite to room'**
  String get inviteToRoom;

  /// No description provided for @speaking.
  ///
  /// In en, this message translates to:
  /// **'Speaking'**
  String get speaking;

  /// No description provided for @listening.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get listening;

  /// No description provided for @muted.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get muted;

  /// No description provided for @callKey.
  ///
  /// In en, this message translates to:
  /// **'Call key'**
  String get callKey;

  /// No description provided for @callKeyNote.
  ///
  /// In en, this message translates to:
  /// **'If everyone sees these words, nobody is listening in.'**
  String get callKeyNote;

  /// No description provided for @unmuteMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Unmute microphone'**
  String get unmuteMicrophone;

  /// No description provided for @muteMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Mute microphone'**
  String get muteMicrophone;

  /// No description provided for @speaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get speaker;

  /// No description provided for @turnCameraOn.
  ///
  /// In en, this message translates to:
  /// **'Turn camera on'**
  String get turnCameraOn;

  /// No description provided for @leaveTheRoom.
  ///
  /// In en, this message translates to:
  /// **'Leave the room'**
  String get leaveTheRoom;

  /// No description provided for @findSpaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Find a space'**
  String get findSpaceTitle;

  /// No description provided for @searchPublicSpaces.
  ///
  /// In en, this message translates to:
  /// **'Search public spaces'**
  String get searchPublicSpaces;

  /// No description provided for @publicAnyoneCanJoin.
  ///
  /// In en, this message translates to:
  /// **'Public, anyone can join'**
  String get publicAnyoneCanJoin;

  /// No description provided for @spaceTypeChannel.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get spaceTypeChannel;

  /// No description provided for @spaceTypeCommunity.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get spaceTypeCommunity;

  /// No description provided for @spaceTypeAndDescription.
  ///
  /// In en, this message translates to:
  /// **'{type}. {description}'**
  String spaceTypeAndDescription(String type, String description);

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @join.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get join;

  /// No description provided for @findSpaceFootnote.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{Shared by devices around you. There is no central list.} other{Shared by phones around you. There is no central list.}}'**
  String findSpaceFootnote(String device);

  /// No description provided for @noSpacesFound.
  ///
  /// In en, this message translates to:
  /// **'No public spaces match.'**
  String get noSpacesFound;

  /// No description provided for @haveAnInvite.
  ///
  /// In en, this message translates to:
  /// **'Have an invite?'**
  String get haveAnInvite;

  /// No description provided for @privateSpacesHidden.
  ///
  /// In en, this message translates to:
  /// **'Private spaces never show up in search.'**
  String get privateSpacesHidden;

  /// No description provided for @pasteLink.
  ///
  /// In en, this message translates to:
  /// **'Paste link'**
  String get pasteLink;

  /// No description provided for @scanCode.
  ///
  /// In en, this message translates to:
  /// **'Scan code'**
  String get scanCode;

  /// No description provided for @createSpace.
  ///
  /// In en, this message translates to:
  /// **'Create a space'**
  String get createSpace;

  /// No description provided for @publicChannel.
  ///
  /// In en, this message translates to:
  /// **'Public channel'**
  String get publicChannel;

  /// No description provided for @signedByOwner.
  ///
  /// In en, this message translates to:
  /// **'Signed by the owner'**
  String get signedByOwner;

  /// No description provided for @commentsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 comment} other{{count} comments}}'**
  String commentsCount(int count);

  /// No description provided for @followFootnote.
  ///
  /// In en, this message translates to:
  /// **'You follow privately. The owner cannot see who follows.'**
  String get followFootnote;

  /// No description provided for @following.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get following;

  /// No description provided for @follow.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get follow;

  /// No description provided for @mute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get mute;

  /// No description provided for @scanACode.
  ///
  /// In en, this message translates to:
  /// **'Scan a code'**
  String get scanACode;

  /// No description provided for @peopleInRange.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{person in range} other{people in range}}'**
  String peopleInRange(int count);

  /// No description provided for @noInternetNeeded.
  ///
  /// In en, this message translates to:
  /// **'No internet needed'**
  String get noInternetNeeded;

  /// No description provided for @linkWifiFast.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi, fast'**
  String get linkWifiFast;

  /// No description provided for @linkBluetoothChatOnly.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth, chat only'**
  String get linkBluetoothChatOnly;

  /// No description provided for @chat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chat;

  /// No description provided for @request.
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get request;

  /// No description provided for @requested.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get requested;

  /// No description provided for @nearbyEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nobody in range right now.'**
  String get nearbyEmpty;

  /// No description provided for @networkTitle.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get networkTitle;

  /// No description provided for @connectedNearby.
  ///
  /// In en, this message translates to:
  /// **'Connected nearby'**
  String get connectedNearby;

  /// No description provided for @connectedNearbyDetail.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi to {wifi} people, Bluetooth to {bluetooth} more.'**
  String connectedNearbyDetail(int wifi, int bluetooth);

  /// No description provided for @links.
  ///
  /// In en, this message translates to:
  /// **'Links'**
  String get links;

  /// No description provided for @bluetooth.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get bluetooth;

  /// No description provided for @bluetoothDetail.
  ///
  /// In en, this message translates to:
  /// **'Finds people and carries chat'**
  String get bluetoothDetail;

  /// No description provided for @wifiNearby.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi nearby'**
  String get wifiNearby;

  /// No description provided for @wifiNearbyDetail.
  ///
  /// In en, this message translates to:
  /// **'Fast link for big files, over Wi-Fi Direct or the same Wi-Fi'**
  String get wifiNearbyDetail;

  /// No description provided for @longRangeAddOn.
  ///
  /// In en, this message translates to:
  /// **'Long-range add-on'**
  String get longRangeAddOn;

  /// No description provided for @longRangeAddOnDetail.
  ///
  /// In en, this message translates to:
  /// **'Needs an extra radio'**
  String get longRangeAddOnDetail;

  /// No description provided for @radio.
  ///
  /// In en, this message translates to:
  /// **'Radio'**
  String get radio;

  /// No description provided for @radioSwitchDetail.
  ///
  /// In en, this message translates to:
  /// **'Through a plugged-in LoRa radio. Slow, chat only.'**
  String get radioSwitchDetail;

  /// No description provided for @radioTitle.
  ///
  /// In en, this message translates to:
  /// **'Long-range radio'**
  String get radioTitle;

  /// No description provided for @radioIntro.
  ///
  /// In en, this message translates to:
  /// **'Chat with people far beyond Bluetooth range through a LoRa radio plugged into {device, select, pc{this PC} other{this phone}}, or reached over Bluetooth or Wi-Fi. Slow, text only, no internet.'**
  String radioIntro(String device);

  /// No description provided for @radioDevice.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get radioDevice;

  /// No description provided for @radioNoDevice.
  ///
  /// In en, this message translates to:
  /// **'No radio set up'**
  String get radioNoDevice;

  /// No description provided for @radioChooseDevice.
  ///
  /// In en, this message translates to:
  /// **'Choose a device'**
  String get radioChooseDevice;

  /// No description provided for @radioChangeDevice.
  ///
  /// In en, this message translates to:
  /// **'Change device'**
  String get radioChangeDevice;

  /// No description provided for @radioOverUsb.
  ///
  /// In en, this message translates to:
  /// **'USB'**
  String get radioOverUsb;

  /// No description provided for @radioOverUsbDetail.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{A USB cable} other{A cable, or an OTG adapter on a phone}}'**
  String radioOverUsbDetail(String device);

  /// No description provided for @radioOverBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get radioOverBluetooth;

  /// No description provided for @radioOverBluetoothDetail.
  ///
  /// In en, this message translates to:
  /// **'A Meshtastic device paired nearby'**
  String get radioOverBluetoothDetail;

  /// No description provided for @radioOverWifi.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi'**
  String get radioOverWifi;

  /// No description provided for @radioOverWifiDetail.
  ///
  /// In en, this message translates to:
  /// **'A Meshtastic device on the same network, by its address'**
  String get radioOverWifiDetail;

  /// No description provided for @radioNotOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Not on {device, select, pc{this PC} other{this phone}} in this release'**
  String radioNotOnThisDevice(String device);

  /// No description provided for @radioAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Address on the network (numbers only)'**
  String get radioAddressLabel;

  /// No description provided for @radioPortLabel.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get radioPortLabel;

  /// No description provided for @radioAddressNotUsable.
  ///
  /// In en, this message translates to:
  /// **'That is not an address on the local network.'**
  String get radioAddressNotUsable;

  /// No description provided for @radioScan.
  ///
  /// In en, this message translates to:
  /// **'Look for devices'**
  String get radioScan;

  /// No description provided for @radioScanning.
  ///
  /// In en, this message translates to:
  /// **'Looking…'**
  String get radioScanning;

  /// No description provided for @radioNoneFound.
  ///
  /// In en, this message translates to:
  /// **'No radio found. Plug one in, or switch it on, and look again.'**
  String get radioNoneFound;

  /// No description provided for @radioDriverLabel.
  ///
  /// In en, this message translates to:
  /// **'Kind of device'**
  String get radioDriverLabel;

  /// No description provided for @radioDriverMeshtastic.
  ///
  /// In en, this message translates to:
  /// **'Meshtastic device'**
  String get radioDriverMeshtastic;

  /// No description provided for @radioDriverSerial.
  ///
  /// In en, this message translates to:
  /// **'Bare LoRa module with DNet serial firmware'**
  String get radioDriverSerial;

  /// No description provided for @radioUseThis.
  ///
  /// In en, this message translates to:
  /// **'Use this device'**
  String get radioUseThis;

  /// No description provided for @radioForget.
  ///
  /// In en, this message translates to:
  /// **'Forget this radio'**
  String get radioForget;

  /// No description provided for @radioSetUpFailed.
  ///
  /// In en, this message translates to:
  /// **'The radio could not be set up: {reason}'**
  String radioSetUpFailed(String reason);

  /// No description provided for @radioSetUpDone.
  ///
  /// In en, this message translates to:
  /// **'Radio set up. Switch Long-range on under Links to use it.'**
  String get radioSetUpDone;

  /// No description provided for @radioRegionTitle.
  ///
  /// In en, this message translates to:
  /// **'Band'**
  String get radioRegionTitle;

  /// No description provided for @radioRegionWarning.
  ///
  /// In en, this message translates to:
  /// **'You must choose the band that is legal where you are. Transmitting on another band is against the law and can be punished. In India the licence-free band is 865–867 MHz.'**
  String get radioRegionWarning;

  /// No description provided for @radioRegionNotSet.
  ///
  /// In en, this message translates to:
  /// **'No band chosen. The radio keeps whatever it was set to until you choose.'**
  String get radioRegionNotSet;

  /// No description provided for @radioRegionLegalIn.
  ///
  /// In en, this message translates to:
  /// **'Legal in: {countries}'**
  String radioRegionLegalIn(String countries);

  /// No description provided for @radioRegionDutyCycle.
  ///
  /// In en, this message translates to:
  /// **'Airtime limit {percent}%'**
  String radioRegionDutyCycle(int percent);

  /// No description provided for @radioChooseRegion.
  ///
  /// In en, this message translates to:
  /// **'Choose a band'**
  String get radioChooseRegion;

  /// No description provided for @radioStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get radioStatusTitle;

  /// No description provided for @radioStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected to {name}'**
  String radioStatusConnected(String name);

  /// No description provided for @radioStatusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get radioStatusConnecting;

  /// No description provided for @radioStatusReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Lost the radio. Trying again…'**
  String get radioStatusReconnecting;

  /// No description provided for @radioStatusOff.
  ///
  /// In en, this message translates to:
  /// **'Off. Switch Long-range on under Links.'**
  String get radioStatusOff;

  /// No description provided for @radioStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not use the radio: {reason}'**
  String radioStatusFailed(String reason);

  /// No description provided for @radioDeviceLine.
  ///
  /// In en, this message translates to:
  /// **'{firmware} · {preset} · {region}'**
  String radioDeviceLine(String firmware, String preset, String region);

  /// No description provided for @radioSignalTitle.
  ///
  /// In en, this message translates to:
  /// **'Signal'**
  String get radioSignalTitle;

  /// No description provided for @radioSignalWords.
  ///
  /// In en, this message translates to:
  /// **'{grade, select, strong{Strong} good{Good} weak{Weak} faint{Faint} other{Nothing heard yet}}'**
  String radioSignalWords(String grade);

  /// No description provided for @radioSignalDetail.
  ///
  /// In en, this message translates to:
  /// **'{rssi} dBm, SNR {snr} dB'**
  String radioSignalDetail(int rssi, String snr);

  /// No description provided for @radioPeers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No DNet devices heard} =1{1 DNet device heard} other{{count} DNet devices heard}}'**
  String radioPeers(int count);

  /// No description provided for @radioCounts.
  ///
  /// In en, this message translates to:
  /// **'Sent {sent} · delivered {delivered} · failed {failed} · received {received}'**
  String radioCounts(int sent, int delivered, int failed, int received);

  /// No description provided for @radioAirtime.
  ///
  /// In en, this message translates to:
  /// **'Airtime used this hour: {percent}%'**
  String radioAirtime(int percent);

  /// No description provided for @radioMessageStatus.
  ///
  /// In en, this message translates to:
  /// **'{status, select, sent{via radio · sent} relayed{via radio · relayed} delivered{via radio · delivered} failed{via radio · failed} other{via radio}}'**
  String radioMessageStatus(String status);

  /// No description provided for @radioHops.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{direct} =1{1 hop} other{{count} hops}}'**
  String radioHops(int count);

  /// No description provided for @radioFilesNote.
  ///
  /// In en, this message translates to:
  /// **'Files never go by radio: a LoRa packet carries a few hundred bytes a second. They wait for Bluetooth or Wi-Fi.'**
  String get radioFilesNote;

  /// No description provided for @radioStepDevice.
  ///
  /// In en, this message translates to:
  /// **'1 · Device'**
  String get radioStepDevice;

  /// No description provided for @radioStepBand.
  ///
  /// In en, this message translates to:
  /// **'2 · Band'**
  String get radioStepBand;

  /// No description provided for @radioStepTest.
  ///
  /// In en, this message translates to:
  /// **'3 · Test the link'**
  String get radioStepTest;

  /// No description provided for @radioAntennaWarning.
  ///
  /// In en, this message translates to:
  /// **'Attach the antenna before the radio is powered: sending without one can burn out its output stage.'**
  String get radioAntennaWarning;

  /// No description provided for @radioTestLink.
  ///
  /// In en, this message translates to:
  /// **'Say hello on the air'**
  String get radioTestLink;

  /// No description provided for @radioTestDetail.
  ///
  /// In en, this message translates to:
  /// **'Sends a short \"DNet is here\". Other DNet radios in range answer with their own and are counted below.'**
  String get radioTestDetail;

  /// No description provided for @radioTestSent.
  ///
  /// In en, this message translates to:
  /// **'Sent. An answer can take a minute or two across several hops.'**
  String get radioTestSent;

  /// No description provided for @radioTestNotUp.
  ///
  /// In en, this message translates to:
  /// **'Set up a device and switch Long-range on under Links first.'**
  String get radioTestNotUp;

  /// No description provided for @radioLastHeard.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =0{Last heard just now} =1{Last heard a minute ago} other{Last heard {minutes} minutes ago}}'**
  String radioLastHeard(int minutes);

  /// No description provided for @radioRoundTrip.
  ///
  /// In en, this message translates to:
  /// **'Round trip {seconds} s'**
  String radioRoundTrip(String seconds);

  /// No description provided for @radioLastProblem.
  ///
  /// In en, this message translates to:
  /// **'Last problem: {reason}'**
  String radioLastProblem(String reason);

  /// No description provided for @radioDeviceSays.
  ///
  /// In en, this message translates to:
  /// **'The radio says: {message}'**
  String radioDeviceSays(String message);

  /// No description provided for @radioAirtimeOfLimit.
  ///
  /// In en, this message translates to:
  /// **'Airtime this hour: {percent}% of what the band allows'**
  String radioAirtimeOfLimit(int percent);

  /// No description provided for @radioAirtimeNoLimit.
  ///
  /// In en, this message translates to:
  /// **'No airtime limit on this band. DNet still sends only what it must.'**
  String get radioAirtimeNoLimit;

  /// No description provided for @radioBandwidthTooWide.
  ///
  /// In en, this message translates to:
  /// **'The radio\'s signal is {width} kHz wide; the rules here allow {limit} kHz. Set it to LONG_MODERATE (125 kHz) in the Meshtastic app.'**
  String radioBandwidthTooWide(String width, int limit);

  /// No description provided for @radioRegionSearch.
  ///
  /// In en, this message translates to:
  /// **'Find a country or band'**
  String get radioRegionSearch;

  /// No description provided for @radioRegionNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No band matches that.'**
  String get radioRegionNoMatch;

  /// No description provided for @radioPortKind.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, usbNative{The board\'s own USB} cp210x{USB bridge chip (CP210x)} ch34x{USB bridge chip (CH340 or CH9102)} ftdi{USB bridge chip (FTDI)} bluetooth{Bluetooth serial port, rarely a radio} other{Serial port}}'**
  String radioPortKind(String kind);

  /// No description provided for @radioHardwareLine.
  ///
  /// In en, this message translates to:
  /// **'{hardware} · firmware {firmware}'**
  String radioHardwareLine(String hardware, String firmware);

  /// No description provided for @radioSettingsLine.
  ///
  /// In en, this message translates to:
  /// **'{preset} · band {region}'**
  String radioSettingsLine(String preset, String region);

  /// No description provided for @radioQueueFree.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{The radio\'s send queue is full} =1{Room for 1 more packet in the radio\'s queue} other{Room for {count} more packets in the radio\'s queue}}'**
  String radioQueueFree(int count);

  /// No description provided for @radioViaKind.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, serial{By USB} ble{By Bluetooth} tcp{By Wi-Fi} other{Pretend radio}}'**
  String radioViaKind(String kind);

  /// No description provided for @internet.
  ///
  /// In en, this message translates to:
  /// **'Internet'**
  String get internet;

  /// No description provided for @internetDetail.
  ///
  /// In en, this message translates to:
  /// **'Optional. Reach friends far away.'**
  String get internetDetail;

  /// No description provided for @keepsYouConnected.
  ///
  /// In en, this message translates to:
  /// **'Keeps you connected'**
  String get keepsYouConnected;

  /// No description provided for @automatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get automatic;

  /// No description provided for @protectBothRadios.
  ///
  /// In en, this message translates to:
  /// **'Sends on both radios at once'**
  String get protectBothRadios;

  /// No description provided for @protectChangesBand.
  ///
  /// In en, this message translates to:
  /// **'Changes band when one is crowded'**
  String get protectChangesBand;

  /// No description provided for @protectLongRange.
  ///
  /// In en, this message translates to:
  /// **'Long-range mode for weak signal'**
  String get protectLongRange;

  /// No description provided for @protectRebuildsFiles.
  ///
  /// In en, this message translates to:
  /// **'Rebuilds files from any pieces'**
  String get protectRebuildsFiles;

  /// No description provided for @protectHoldsMessages.
  ///
  /// In en, this message translates to:
  /// **'Holds messages until a path opens'**
  String get protectHoldsMessages;

  /// No description provided for @encryptionAlwaysOn.
  ///
  /// In en, this message translates to:
  /// **'AES-256 with post-quantum keys. Always on.'**
  String get encryptionAlwaysOn;

  /// No description provided for @linkNobodyInRange.
  ///
  /// In en, this message translates to:
  /// **'Nobody in range'**
  String get linkNobodyInRange;

  /// No description provided for @linkRadioLine.
  ///
  /// In en, this message translates to:
  /// **'{radio}: {people}, {waiting}'**
  String linkRadioLine(String radio, String people, String waiting);

  /// No description provided for @linkPeople.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{nobody} =1{1 person} other{{count} people}}'**
  String linkPeople(int count);

  /// No description provided for @linkNothingWaiting.
  ///
  /// In en, this message translates to:
  /// **'nothing waiting'**
  String get linkNothingWaiting;

  /// No description provided for @linkMessagesWaiting.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message waiting} other{{count} messages waiting}}'**
  String linkMessagesWaiting(int count);

  /// No description provided for @linkFilesWaiting.
  ///
  /// In en, this message translates to:
  /// **'{size} of files waiting'**
  String linkFilesWaiting(String size);

  /// No description provided for @linkMessagesAndFilesWaiting.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message} other{{count} messages}} and {size} of files waiting'**
  String linkMessagesAndFilesWaiting(int count, String size);

  /// No description provided for @movedToTwoGhz.
  ///
  /// In en, this message translates to:
  /// **'Moved {names} to 2.4 GHz Wi-Fi.'**
  String movedToTwoGhz(String names);

  /// No description provided for @linkTroubleTitle.
  ///
  /// In en, this message translates to:
  /// **'Link trouble'**
  String get linkTroubleTitle;

  /// No description provided for @strongInterference.
  ///
  /// In en, this message translates to:
  /// **'Strong interference'**
  String get strongInterference;

  /// No description provided for @strongInterferenceDetail.
  ///
  /// In en, this message translates to:
  /// **'Links dropped together while people were still in range.'**
  String get strongInterferenceDetail;

  /// No description provided for @wifi24.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi 2.4 GHz'**
  String get wifi24;

  /// No description provided for @wifi5.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi 5 GHz'**
  String get wifi5;

  /// No description provided for @noSignal.
  ///
  /// In en, this message translates to:
  /// **'No signal'**
  String get noSignal;

  /// No description provided for @working.
  ///
  /// In en, this message translates to:
  /// **'Working'**
  String get working;

  /// No description provided for @signalGettingBetter.
  ///
  /// In en, this message translates to:
  /// **'Signal to {name}: getting better'**
  String signalGettingBetter(String name);

  /// No description provided for @signalGettingWorse.
  ///
  /// In en, this message translates to:
  /// **'Signal to {name}: getting worse'**
  String signalGettingWorse(String name);

  /// No description provided for @keepWalkingToward.
  ///
  /// In en, this message translates to:
  /// **'Keep walking toward {name}.'**
  String keepWalkingToward(String name);

  /// No description provided for @signalStrength.
  ///
  /// In en, this message translates to:
  /// **'Signal strength, {level} of 5'**
  String signalStrength(int level);

  /// No description provided for @whatAppIsDoing.
  ///
  /// In en, this message translates to:
  /// **'What DNet is doing'**
  String get whatAppIsDoing;

  /// No description provided for @movedToFiveGhz.
  ///
  /// In en, this message translates to:
  /// **'Moved {names} to 5 GHz Wi-Fi.'**
  String movedToFiveGhz(String names);

  /// No description provided for @holdingMessages.
  ///
  /// In en, this message translates to:
  /// **'Holding {count} messages for {names}. They send when a path opens.'**
  String holdingMessages(int count, String names);

  /// No description provided for @holdingMessagesFor.
  ///
  /// In en, this message translates to:
  /// **'Holding {count, plural, =1{1 message} other{{count} messages}} for {name}. They send when a path opens.'**
  String holdingMessagesFor(int count, String name);

  /// No description provided for @signalHolding.
  ///
  /// In en, this message translates to:
  /// **'Signal to {name}: holding'**
  String signalHolding(String name);

  /// No description provided for @walkBackToward.
  ///
  /// In en, this message translates to:
  /// **'Try walking back toward {name}.'**
  String walkBackToward(String name);

  /// No description provided for @tryWalkingToward.
  ///
  /// In en, this message translates to:
  /// **'Walking toward {name} may help.'**
  String tryWalkingToward(String name);

  /// No description provided for @radiosRestarted.
  ///
  /// In en, this message translates to:
  /// **'Radios stopped and started again.'**
  String get radiosRestarted;

  /// No description provided for @twoNames.
  ///
  /// In en, this message translates to:
  /// **'{first} and {second}'**
  String twoNames(String first, String second);

  /// No description provided for @passByCameraCode.
  ///
  /// In en, this message translates to:
  /// **'Pass messages by camera code'**
  String get passByCameraCode;

  /// No description provided for @tryAllRadiosAgain.
  ///
  /// In en, this message translates to:
  /// **'Try all radios again'**
  String get tryAllRadiosAgain;

  /// No description provided for @showMyCode.
  ///
  /// In en, this message translates to:
  /// **'Show my code'**
  String get showMyCode;

  /// No description provided for @noPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'No phone number'**
  String get noPhoneNumber;

  /// No description provided for @noEmail.
  ///
  /// In en, this message translates to:
  /// **'No email'**
  String get noEmail;

  /// No description provided for @namesInSpaces.
  ///
  /// In en, this message translates to:
  /// **'Names in spaces'**
  String get namesInSpaces;

  /// No description provided for @namesInSpacesBody.
  ///
  /// In en, this message translates to:
  /// **'You can go by a different name in each space. In your chats, and in every other space, you stay who you are.'**
  String get namesInSpacesBody;

  /// No description provided for @noSpacesForNames.
  ///
  /// In en, this message translates to:
  /// **'You are not in any space yet.'**
  String get noSpacesForNames;

  /// No description provided for @usualName.
  ///
  /// In en, this message translates to:
  /// **'{name} (your usual name)'**
  String usualName(String name);

  /// No description provided for @nameInSpaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Your name in {space}'**
  String nameInSpaceTitle(String space);

  /// No description provided for @nameInSpaceBody.
  ///
  /// In en, this message translates to:
  /// **'Everyone in this space will see it. Leave it empty to go by your usual name.'**
  String get nameInSpaceBody;

  /// No description provided for @spacesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 space} other{{count} spaces}}'**
  String spacesCount(int count);

  /// No description provided for @linkedDevices.
  ///
  /// In en, this message translates to:
  /// **'Linked devices'**
  String get linkedDevices;

  /// No description provided for @recoveryContacts.
  ///
  /// In en, this message translates to:
  /// **'Recovery contacts'**
  String get recoveryContacts;

  /// No description provided for @recoveryContactsSet.
  ///
  /// In en, this message translates to:
  /// **'{set} of {total} set'**
  String recoveryContactsSet(int set, int total);

  /// No description provided for @privacyAndSecurity.
  ///
  /// In en, this message translates to:
  /// **'Privacy and security'**
  String get privacyAndSecurity;

  /// No description provided for @storage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storage;

  /// No description provided for @storageWhere.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{All of it is on this PC and nowhere else.} other{All of it is on this phone and nowhere else.}}'**
  String storageWhere(String device);

  /// No description provided for @storageChats.
  ///
  /// In en, this message translates to:
  /// **'Chats, spaces and settings'**
  String get storageChats;

  /// No description provided for @storageChatsDetail.
  ///
  /// In en, this message translates to:
  /// **'Kept sealed. Only this device can open it.'**
  String get storageChatsDetail;

  /// No description provided for @storageReceived.
  ///
  /// In en, this message translates to:
  /// **'Files you received'**
  String get storageReceived;

  /// No description provided for @storageReceivedDetail.
  ///
  /// In en, this message translates to:
  /// **'Ordinary files, saved where your other apps can open them.'**
  String get storageReceivedDetail;

  /// No description provided for @storageVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice messages'**
  String get storageVoice;

  /// No description provided for @storageVoiceDetail.
  ///
  /// In en, this message translates to:
  /// **'The ones you recorded.'**
  String get storageVoiceDetail;

  /// No description provided for @storageCarried.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a path'**
  String get storageCarried;

  /// No description provided for @storageCarriedDetail.
  ///
  /// In en, this message translates to:
  /// **'Your own sealed messages, kept here until a path to the person opens. Other people\'s messages are passed on at once and never kept on this device.'**
  String get storageCarriedDetail;

  /// No description provided for @storageFilesAndSize.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{None} =1{1 file, {size}} other{{count} files, {size}}}'**
  String storageFilesAndSize(int count, String size);

  /// No description provided for @storageMessagesAndSize.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{None} =1{1 message, {size}} other{{count} messages, {size}}}'**
  String storageMessagesAndSize(int count, String size);

  /// No description provided for @storageHowToClear.
  ///
  /// In en, this message translates to:
  /// **'Old messages can be deleted by themselves: switch on auto-delete under Privacy. To remove everything at once, use Wipe everything there.'**
  String get storageHowToClear;

  /// No description provided for @onThisPhone.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{On this PC} other{On this phone}}'**
  String onThisPhone(String device);

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'About DNet'**
  String get aboutApp;

  /// No description provided for @sharingLabel.
  ///
  /// In en, this message translates to:
  /// **'Sharing. Off keeps you private.'**
  String get sharingLabel;

  /// No description provided for @showWhenOnline.
  ///
  /// In en, this message translates to:
  /// **'Show when I am online'**
  String get showWhenOnline;

  /// No description provided for @letStrangersFindMe.
  ///
  /// In en, this message translates to:
  /// **'Let strangers find me by name'**
  String get letStrangersFindMe;

  /// No description provided for @letStrangersAddMe.
  ///
  /// In en, this message translates to:
  /// **'Let strangers add me to groups'**
  String get letStrangersAddMe;

  /// No description provided for @showIpInCalls.
  ///
  /// In en, this message translates to:
  /// **'Show my IP address in calls'**
  String get showIpInCalls;

  /// No description provided for @sendReadReceipts.
  ///
  /// In en, this message translates to:
  /// **'Send read receipts'**
  String get sendReadReceipts;

  /// No description provided for @showWhenTyping.
  ///
  /// In en, this message translates to:
  /// **'Show when I am typing'**
  String get showWhenTyping;

  /// No description provided for @allowScreenshots.
  ///
  /// In en, this message translates to:
  /// **'Allow screenshots of chats'**
  String get allowScreenshots;

  /// No description provided for @appLock.
  ///
  /// In en, this message translates to:
  /// **'App lock with passcode'**
  String get appLock;

  /// No description provided for @autoDelete.
  ///
  /// In en, this message translates to:
  /// **'Auto-delete old messages'**
  String get autoDelete;

  /// No description provided for @eraseAfterWrongPasscodes.
  ///
  /// In en, this message translates to:
  /// **'Erase after 10 wrong passcodes'**
  String get eraseAfterWrongPasscodes;

  /// No description provided for @alwaysOn.
  ///
  /// In en, this message translates to:
  /// **'Always on'**
  String get alwaysOn;

  /// No description provided for @cannotBeSwitchedOff.
  ///
  /// In en, this message translates to:
  /// **'Cannot be switched off'**
  String get cannotBeSwitchedOff;

  /// No description provided for @chatEncryption.
  ///
  /// In en, this message translates to:
  /// **'Chat encryption'**
  String get chatEncryption;

  /// No description provided for @postQuantumKeys.
  ///
  /// In en, this message translates to:
  /// **'Post-quantum keys'**
  String get postQuantumKeys;

  /// No description provided for @encryptedStorage.
  ///
  /// In en, this message translates to:
  /// **'Encrypted storage'**
  String get encryptedStorage;

  /// No description provided for @keyChangeAlerts.
  ///
  /// In en, this message translates to:
  /// **'Key-change alerts'**
  String get keyChangeAlerts;

  /// No description provided for @notYourContactTitle.
  ///
  /// In en, this message translates to:
  /// **'Not the {name} in your chats'**
  String notYourContactTitle(String name);

  /// No description provided for @notYourContactBody.
  ///
  /// In en, this message translates to:
  /// **'Same name, different key, so this is a different device. If {name} says they have a new one, check with them another way before you accept.'**
  String notYourContactBody(String name);

  /// No description provided for @savedUntilWipe.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{Saved on this PC until you wipe it.} other{Saved on this phone until you wipe it.}}'**
  String savedUntilWipe(String device);

  /// No description provided for @wipeEverythingNow.
  ///
  /// In en, this message translates to:
  /// **'Wipe everything now'**
  String get wipeEverythingNow;

  /// No description provided for @wipeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Wipe everything?'**
  String get wipeConfirmTitle;

  /// No description provided for @wipeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{This erases your key, chats, spaces and files from this PC. It cannot be undone.} other{This erases your key, chats, spaces and files from this phone. It cannot be undone.}}'**
  String wipeConfirmBody(String device);

  /// No description provided for @wipeConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Wipe'**
  String get wipeConfirmAction;

  /// No description provided for @delivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get delivered;

  /// No description provided for @waitingToDeliver.
  ///
  /// In en, this message translates to:
  /// **'Waiting. It will go when they are in range.'**
  String get waitingToDeliver;

  /// No description provided for @spaceName.
  ///
  /// In en, this message translates to:
  /// **'Name of the space'**
  String get spaceName;

  /// No description provided for @spaceAbout.
  ///
  /// In en, this message translates to:
  /// **'What it is about (optional)'**
  String get spaceAbout;

  /// No description provided for @spaceNeedsName.
  ///
  /// In en, this message translates to:
  /// **'Give the space a name first.'**
  String get spaceNeedsName;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @kindPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private space'**
  String get kindPrivate;

  /// No description provided for @kindPrivateDetail.
  ///
  /// In en, this message translates to:
  /// **'Invite only. People nearby cannot see it.'**
  String get kindPrivateDetail;

  /// No description provided for @kindPublic.
  ///
  /// In en, this message translates to:
  /// **'Public space'**
  String get kindPublic;

  /// No description provided for @kindPublicDetail.
  ///
  /// In en, this message translates to:
  /// **'Anyone nearby can find it and join. Nothing said in it is secret.'**
  String get kindPublicDetail;

  /// No description provided for @kindChannel.
  ///
  /// In en, this message translates to:
  /// **'Public channel'**
  String get kindChannel;

  /// No description provided for @kindChannelDetail.
  ///
  /// In en, this message translates to:
  /// **'Anyone nearby can follow it. Only you post.'**
  String get kindChannelDetail;

  /// No description provided for @invitations.
  ///
  /// In en, this message translates to:
  /// **'Invitations'**
  String get invitations;

  /// No description provided for @invitedBy.
  ///
  /// In en, this message translates to:
  /// **'{name} invited you'**
  String invitedBy(String name);

  /// No description provided for @inviteToSpace.
  ///
  /// In en, this message translates to:
  /// **'Invite to {space}'**
  String inviteToSpace(String space);

  /// No description provided for @copyInviteLink.
  ///
  /// In en, this message translates to:
  /// **'Copy invite link'**
  String get copyInviteLink;

  /// No description provided for @linkLasts.
  ///
  /// In en, this message translates to:
  /// **'Link lets people in for'**
  String get linkLasts;

  /// No description provided for @linkLastsForGood.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get linkLastsForGood;

  /// No description provided for @linkLastsHour.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get linkLastsHour;

  /// No description provided for @linkLastsDay.
  ///
  /// In en, this message translates to:
  /// **'1 day'**
  String get linkLastsDay;

  /// No description provided for @linkLastsWeek.
  ///
  /// In en, this message translates to:
  /// **'1 week'**
  String get linkLastsWeek;

  /// No description provided for @linkRunsOutNote.
  ///
  /// In en, this message translates to:
  /// **'After that, DNet will not join with it. The link holds the space\'s key, so a changed app that kept a copy could still use it. Resetting invite links in space settings stops that.'**
  String get linkRunsOutNote;

  /// No description provided for @inviteRunOutTitle.
  ///
  /// In en, this message translates to:
  /// **'This invite has run out'**
  String get inviteRunOutTitle;

  /// No description provided for @inviteRunOutBody.
  ///
  /// In en, this message translates to:
  /// **'Ask whoever sent it for a new one.'**
  String get inviteRunOutBody;

  /// No description provided for @inviteLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Invite link copied. Anyone who has it can join.'**
  String get inviteLinkCopied;

  /// No description provided for @yourContacts.
  ///
  /// In en, this message translates to:
  /// **'Your contacts'**
  String get yourContacts;

  /// No description provided for @invite.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get invite;

  /// No description provided for @invited.
  ///
  /// In en, this message translates to:
  /// **'Invited'**
  String get invited;

  /// No description provided for @noContactsToInvite.
  ///
  /// In en, this message translates to:
  /// **'Nobody to invite by name yet. Copy the link, or add someone from Nearby first.'**
  String get noContactsToInvite;

  /// No description provided for @leaveSpace.
  ///
  /// In en, this message translates to:
  /// **'Leave this space'**
  String get leaveSpace;

  /// No description provided for @leaveSpaceConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave {space}?'**
  String leaveSpaceConfirmTitle(String space);

  /// No description provided for @leaveSpaceConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{It is removed from this PC. You need a new invite to come back.} other{It is removed from this phone. You need a new invite to come back.}}'**
  String leaveSpaceConfirmBody(String device);

  /// No description provided for @leave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get leave;

  /// No description provided for @inviteNotValidTitle.
  ///
  /// In en, this message translates to:
  /// **'That is not a DNet invite'**
  String get inviteNotValidTitle;

  /// No description provided for @inviteNotValidBody.
  ///
  /// In en, this message translates to:
  /// **'Copy the whole invite, then press Paste link again.'**
  String get inviteNotValidBody;

  /// No description provided for @joinedSpace.
  ///
  /// In en, this message translates to:
  /// **'Joined {space}'**
  String joinedSpace(String space);

  /// No description provided for @spaceWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting to meet a member. This space fills in when someone who is in it comes into range.'**
  String get spaceWaiting;

  /// No description provided for @onlyOwnerPosts.
  ///
  /// In en, this message translates to:
  /// **'Only the owner and admins can post here.'**
  String get onlyOwnerPosts;

  /// No description provided for @postToChannel.
  ///
  /// In en, this message translates to:
  /// **'Post to {name}'**
  String postToChannel(String name);

  /// No description provided for @noPostsYet.
  ///
  /// In en, this message translates to:
  /// **'No posts yet.'**
  String get noPostsYet;

  /// No description provided for @followToSeePosts.
  ///
  /// In en, this message translates to:
  /// **'Follow to see what is posted here.'**
  String get followToSeePosts;

  /// No description provided for @react.
  ///
  /// In en, this message translates to:
  /// **'React'**
  String get react;

  /// No description provided for @timeOutTen.
  ///
  /// In en, this message translates to:
  /// **'Time out for 10 minutes'**
  String get timeOutTen;

  /// No description provided for @timeOutHour.
  ///
  /// In en, this message translates to:
  /// **'Time out for 1 hour'**
  String get timeOutHour;

  /// No description provided for @timeOutDay.
  ///
  /// In en, this message translates to:
  /// **'Time out for 1 day'**
  String get timeOutDay;

  /// No description provided for @endTimeOut.
  ///
  /// In en, this message translates to:
  /// **'End time-out'**
  String get endTimeOut;

  /// No description provided for @resetInviteLinks.
  ///
  /// In en, this message translates to:
  /// **'Reset invite links'**
  String get resetInviteLinks;

  /// No description provided for @resetInviteLinksBody.
  ///
  /// In en, this message translates to:
  /// **'Every invite link made before now stops working. Everyone already in the space stays. Use this if a link went to the wrong person.'**
  String get resetInviteLinksBody;

  /// No description provided for @resetInviteLinksAction.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetInviteLinksAction;

  /// No description provided for @timedOutWait.
  ///
  /// In en, this message translates to:
  /// **'You are timed out here for {minutes, plural, =1{1 more minute} other{{minutes} more minutes}}.'**
  String timedOutWait(int minutes);

  /// No description provided for @yourQrCode.
  ///
  /// In en, this message translates to:
  /// **'Your code. Someone points their camera at it to add you.'**
  String get yourQrCode;

  /// No description provided for @scanHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at a DNet code on someone\'s screen.'**
  String get scanHint;

  /// No description provided for @scanVerified.
  ///
  /// In en, this message translates to:
  /// **'Scanned. They are verified.'**
  String get scanVerified;

  /// No description provided for @scanJoinedSpace.
  ///
  /// In en, this message translates to:
  /// **'You joined the space.'**
  String get scanJoinedSpace;

  /// No description provided for @scanNotACodeTitle.
  ///
  /// In en, this message translates to:
  /// **'That is not a DNet code'**
  String get scanNotACodeTitle;

  /// No description provided for @scanNotACodeBody.
  ///
  /// In en, this message translates to:
  /// **'Ask them to open DNet and show their code, then scan again.'**
  String get scanNotACodeBody;

  /// No description provided for @votesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 vote} other{{count} votes}}'**
  String votesCount(int count);

  /// No description provided for @channelRules.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get channelRules;

  /// No description provided for @channelRulesNamed.
  ///
  /// In en, this message translates to:
  /// **'Rules for {name}'**
  String channelRulesNamed(String name);

  /// No description provided for @channelRulesBody.
  ///
  /// In en, this message translates to:
  /// **'Rules bind members. You and the admins are not bound. They apply to what is written from now on.'**
  String get channelRulesBody;

  /// No description provided for @noLinksRule.
  ///
  /// In en, this message translates to:
  /// **'No links from members'**
  String get noLinksRule;

  /// No description provided for @slowMode.
  ///
  /// In en, this message translates to:
  /// **'Slow mode'**
  String get slowMode;

  /// No description provided for @slowModeDetail.
  ///
  /// In en, this message translates to:
  /// **'How long a member waits between two messages'**
  String get slowModeDetail;

  /// No description provided for @slowOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get slowOff;

  /// No description provided for @slowTen.
  ///
  /// In en, this message translates to:
  /// **'10 s'**
  String get slowTen;

  /// No description provided for @slowMinute.
  ///
  /// In en, this message translates to:
  /// **'1 min'**
  String get slowMinute;

  /// No description provided for @slowFive.
  ///
  /// In en, this message translates to:
  /// **'5 min'**
  String get slowFive;

  /// No description provided for @slowHour.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get slowHour;

  /// No description provided for @slowSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String slowSeconds(int seconds);

  /// No description provided for @linksNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Links are not allowed in this channel.'**
  String get linksNotAllowed;

  /// No description provided for @slowModeWait.
  ///
  /// In en, this message translates to:
  /// **'Slow mode is on here. Try again in {seconds, plural, =1{1 second} other{{seconds} seconds}}.'**
  String slowModeWait(int seconds);

  /// No description provided for @rulesNoteNoLinks.
  ///
  /// In en, this message translates to:
  /// **'No links here.'**
  String get rulesNoteNoLinks;

  /// No description provided for @rulesNoteLength.
  ///
  /// In en, this message translates to:
  /// **'Messages up to {count} characters.'**
  String rulesNoteLength(int count);

  /// No description provided for @rulesNoteBanned.
  ///
  /// In en, this message translates to:
  /// **'Some words are not allowed in this space.'**
  String get rulesNoteBanned;

  /// No description provided for @bannedWordRefused.
  ///
  /// In en, this message translates to:
  /// **'That has a word the owner does not allow in this space.'**
  String get bannedWordRefused;

  /// No description provided for @tooLongRefused.
  ///
  /// In en, this message translates to:
  /// **'Messages here can be up to {count} characters.'**
  String tooLongRefused(int count);

  /// No description provided for @roles.
  ///
  /// In en, this message translates to:
  /// **'Roles'**
  String get roles;

  /// No description provided for @rolesBody.
  ///
  /// In en, this message translates to:
  /// **'A role lets the members you give it to do some of what admins do. Changing what a role may do counts for what its holders did before, too.'**
  String get rolesBody;

  /// No description provided for @addRole.
  ///
  /// In en, this message translates to:
  /// **'Add a role'**
  String get addRole;

  /// No description provided for @roleName.
  ///
  /// In en, this message translates to:
  /// **'Role name'**
  String get roleName;

  /// No description provided for @roleMayNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing beyond writing yet'**
  String get roleMayNothing;

  /// No description provided for @roleNotUsable.
  ///
  /// In en, this message translates to:
  /// **'A role needs a name of up to 32 characters. A space has up to 20 roles.'**
  String get roleNotUsable;

  /// No description provided for @rolePowerPin.
  ///
  /// In en, this message translates to:
  /// **'Pin messages'**
  String get rolePowerPin;

  /// No description provided for @rolePowerAnnounce.
  ///
  /// In en, this message translates to:
  /// **'Write in announcement channels'**
  String get rolePowerAnnounce;

  /// No description provided for @rolePowerDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete anyone\'s message'**
  String get rolePowerDelete;

  /// No description provided for @rolePowerTimeout.
  ///
  /// In en, this message translates to:
  /// **'Time members out'**
  String get rolePowerTimeout;

  /// No description provided for @deleteRole.
  ///
  /// In en, this message translates to:
  /// **'Delete role'**
  String get deleteRole;

  /// No description provided for @deleteRoleConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String deleteRoleConfirmTitle(String name);

  /// No description provided for @deleteRoleConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Nobody holds it any more. Channels kept for it are open to everyone again, unless they are kept for another role too.'**
  String get deleteRoleConfirmBody;

  /// No description provided for @giveRole.
  ///
  /// In en, this message translates to:
  /// **'Give {name}'**
  String giveRole(String name);

  /// No description provided for @takeRole.
  ///
  /// In en, this message translates to:
  /// **'Take back {name}'**
  String takeRole(String name);

  /// No description provided for @whoCanWrite.
  ///
  /// In en, this message translates to:
  /// **'Who can write here'**
  String get whoCanWrite;

  /// No description provided for @whoCanWriteDetail.
  ///
  /// In en, this message translates to:
  /// **'Everyone in the space can still read it.'**
  String get whoCanWriteDetail;

  /// No description provided for @everyone.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get everyone;

  /// No description provided for @onlyRolesWrite.
  ///
  /// In en, this message translates to:
  /// **'Only {roles} can write here.'**
  String onlyRolesWrite(String roles);

  /// No description provided for @roleNeededRefused.
  ///
  /// In en, this message translates to:
  /// **'Only some roles can write in this channel.'**
  String get roleNeededRefused;

  /// No description provided for @bannedWords.
  ///
  /// In en, this message translates to:
  /// **'Words not allowed'**
  String get bannedWords;

  /// No description provided for @bannedWordsBody.
  ///
  /// In en, this message translates to:
  /// **'Members cannot use these anywhere in the space. Whole words only, and capitals do not matter. Put commas between them. Up to 50.'**
  String get bannedWordsBody;

  /// No description provided for @bannedWordsNone.
  ///
  /// In en, this message translates to:
  /// **'No words are kept out.'**
  String get bannedWordsNone;

  /// No description provided for @wordFilterSwitch.
  ///
  /// In en, this message translates to:
  /// **'Keep these words out'**
  String get wordFilterSwitch;

  /// No description provided for @bannedWordsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 word or phrase is kept out.} other{{count} words or phrases are kept out.}}'**
  String bannedWordsCount(int count);

  /// No description provided for @bannedWordsNotUsable.
  ///
  /// In en, this message translates to:
  /// **'Up to 50 words, each up to 32 characters.'**
  String get bannedWordsNotUsable;

  /// No description provided for @lengthRule.
  ///
  /// In en, this message translates to:
  /// **'Longest message'**
  String get lengthRule;

  /// No description provided for @lengthNoLimit.
  ///
  /// In en, this message translates to:
  /// **'No limit'**
  String get lengthNoLimit;

  /// No description provided for @lengthChoice.
  ///
  /// In en, this message translates to:
  /// **'{count} characters'**
  String lengthChoice(String count);

  /// No description provided for @rulesNoteDisappear.
  ///
  /// In en, this message translates to:
  /// **'Messages here disappear after {time}.'**
  String rulesNoteDisappear(String time);

  /// No description provided for @disappearRule.
  ///
  /// In en, this message translates to:
  /// **'Messages disappear'**
  String get disappearRule;

  /// No description provided for @disappearRuleDetail.
  ///
  /// In en, this message translates to:
  /// **'What is written here from now on is deleted from every member\'s device after this long. It cannot stop someone copying a message first.'**
  String get disappearRuleDetail;

  /// No description provided for @rulesNoteSlow.
  ///
  /// In en, this message translates to:
  /// **'Slow mode: one message every {time}.'**
  String rulesNoteSlow(String time);

  /// No description provided for @codeExplained.
  ///
  /// In en, this message translates to:
  /// **'People see your name. The code words are made from your key and the time, so they change every 10 minutes. They help people tell your device from another with the same name. They do not prove who you are.'**
  String get codeExplained;

  /// No description provided for @deleteSpace.
  ///
  /// In en, this message translates to:
  /// **'Delete this space'**
  String get deleteSpace;

  /// No description provided for @deleteSpaceConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {space}?'**
  String deleteSpaceConfirmTitle(String space);

  /// No description provided for @deleteSpaceConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'It is removed for everyone in it, with everything said there. Members out of range lose it when they next meet someone who has heard. This cannot be undone.'**
  String get deleteSpaceConfirmBody;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @pasteAnyLink.
  ///
  /// In en, this message translates to:
  /// **'Paste a link'**
  String get pasteAnyLink;

  /// No description provided for @pasteAnyLinkDetail.
  ///
  /// In en, this message translates to:
  /// **'A person\'s link asks them to chat. A space\'s link joins it.'**
  String get pasteAnyLinkDetail;

  /// No description provided for @linkExplained.
  ///
  /// In en, this message translates to:
  /// **'Copy or Share makes a new link each time. It works once, for a day, so it cannot be passed around.'**
  String get linkExplained;

  /// No description provided for @checkFromAnywhere.
  ///
  /// In en, this message translates to:
  /// **'Not together? Check from anywhere'**
  String get checkFromAnywhere;

  /// No description provided for @checkFromAnywhereBody.
  ///
  /// In en, this message translates to:
  /// **'Send your code by any other app, or read these words to each other on a call. If the code they send you is the same as yours, nobody is in between.'**
  String get checkFromAnywhereBody;

  /// No description provided for @copyMyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy my code'**
  String get copyMyCode;

  /// No description provided for @pasteTheirCode.
  ///
  /// In en, this message translates to:
  /// **'Paste their code'**
  String get pasteTheirCode;

  /// No description provided for @codeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied. Send it to them by another app.'**
  String get codeCopied;

  /// No description provided for @codesDiffer.
  ///
  /// In en, this message translates to:
  /// **'The codes are not the same'**
  String get codesDiffer;

  /// No description provided for @codesDifferBody.
  ///
  /// In en, this message translates to:
  /// **'Do not rely on this chat until they match. Check that you copied the whole code and that it really came from them.'**
  String get codesDifferBody;

  /// No description provided for @unblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblock;

  /// No description provided for @codesMatch.
  ///
  /// In en, this message translates to:
  /// **'The codes match. {name} is verified.'**
  String codesMatch(String name);

  /// No description provided for @blockedPeople.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 blocked person} other{{count} blocked people}}'**
  String blockedPeople(int count);

  /// No description provided for @nothingOpen.
  ///
  /// In en, this message translates to:
  /// **'Choose a chat or a channel on the left to open it here.'**
  String get nothingOpen;

  /// No description provided for @keysFindChat.
  ///
  /// In en, this message translates to:
  /// **'Ctrl+K'**
  String get keysFindChat;

  /// No description provided for @keysFindChatLabel.
  ///
  /// In en, this message translates to:
  /// **'Find a chat'**
  String get keysFindChatLabel;

  /// No description provided for @keysNewChat.
  ///
  /// In en, this message translates to:
  /// **'Ctrl+N'**
  String get keysNewChat;

  /// No description provided for @keysNewChatLabel.
  ///
  /// In en, this message translates to:
  /// **'Start a new chat'**
  String get keysNewChatLabel;

  /// No description provided for @keysTabs.
  ///
  /// In en, this message translates to:
  /// **'Ctrl+1–4'**
  String get keysTabs;

  /// No description provided for @keysTabsLabel.
  ///
  /// In en, this message translates to:
  /// **'Switch tabs'**
  String get keysTabsLabel;

  /// No description provided for @keysSearchHere.
  ///
  /// In en, this message translates to:
  /// **'Ctrl+F'**
  String get keysSearchHere;

  /// No description provided for @keysSearchHereLabel.
  ///
  /// In en, this message translates to:
  /// **'Search in a channel'**
  String get keysSearchHereLabel;

  /// No description provided for @keysClose.
  ///
  /// In en, this message translates to:
  /// **'Esc'**
  String get keysClose;

  /// No description provided for @keysCloseLabel.
  ///
  /// In en, this message translates to:
  /// **'Go back or close'**
  String get keysCloseLabel;

  /// No description provided for @scrollToNewest.
  ///
  /// In en, this message translates to:
  /// **'Go to the newest message'**
  String get scrollToNewest;

  /// No description provided for @jumpToNew.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new message} other{{count} new messages}}'**
  String jumpToNew(int count);

  /// No description provided for @showMemberList.
  ///
  /// In en, this message translates to:
  /// **'Show members'**
  String get showMemberList;

  /// No description provided for @hideMemberList.
  ///
  /// In en, this message translates to:
  /// **'Hide members'**
  String get hideMemberList;

  /// No description provided for @messageMore.
  ///
  /// In en, this message translates to:
  /// **'More for this message'**
  String get messageMore;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @deleteForMe.
  ///
  /// In en, this message translates to:
  /// **'Delete for me'**
  String get deleteForMe;

  /// No description provided for @deleteForEveryone.
  ///
  /// In en, this message translates to:
  /// **'Delete for everyone'**
  String get deleteForEveryone;

  /// No description provided for @deleteForEveryoneNote.
  ///
  /// In en, this message translates to:
  /// **'Their copy is deleted when your devices next meet. If they have already read it or copied it, that cannot be undone.'**
  String get deleteForEveryoneNote;

  /// No description provided for @deleteForEveryoneFailed.
  ///
  /// In en, this message translates to:
  /// **'Only your own messages of the last two days can be deleted for everyone.'**
  String get deleteForEveryoneFailed;

  /// No description provided for @messageDeleted.
  ///
  /// In en, this message translates to:
  /// **'This message was deleted'**
  String get messageDeleted;

  /// No description provided for @messageDeletedMine.
  ///
  /// In en, this message translates to:
  /// **'You deleted this message'**
  String get messageDeletedMine;

  /// No description provided for @clearChat.
  ///
  /// In en, this message translates to:
  /// **'Clear chat'**
  String get clearChat;

  /// No description provided for @clearChatConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear the chat with {name}?'**
  String clearChatConfirmTitle(String name);

  /// No description provided for @clearChatConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Every message in it is deleted from this device. {name} keeps theirs.'**
  String clearChatConfirmBody(String name);

  /// No description provided for @deleteChat.
  ///
  /// In en, this message translates to:
  /// **'Delete chat'**
  String get deleteChat;

  /// No description provided for @deleteChatConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete the chat with {name}?'**
  String deleteChatConfirmTitle(String name);

  /// No description provided for @deleteChatConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'It is cleared and taken off your chats until one of you writes again. {name} stays a contact.'**
  String deleteChatConfirmBody(String name);

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @editName.
  ///
  /// In en, this message translates to:
  /// **'Change your name'**
  String get editName;

  /// No description provided for @codeWordsLabel.
  ///
  /// In en, this message translates to:
  /// **'Your code words'**
  String get codeWordsLabel;

  /// No description provided for @editNameBody.
  ///
  /// In en, this message translates to:
  /// **'Your contacts and the spaces you are in will see the new name.'**
  String get editNameBody;

  /// No description provided for @nameNotUsable.
  ///
  /// In en, this message translates to:
  /// **'That name cannot be used. It needs 1 to 64 characters.'**
  String get nameNotUsable;

  /// No description provided for @descriptionTooLong.
  ///
  /// In en, this message translates to:
  /// **'That is too long. Keep it under 140 characters.'**
  String get descriptionTooLong;

  /// No description provided for @spaceSettings.
  ///
  /// In en, this message translates to:
  /// **'Space settings'**
  String get spaceSettings;

  /// No description provided for @channelSettings.
  ///
  /// In en, this message translates to:
  /// **'Channel settings'**
  String get channelSettings;

  /// No description provided for @spaceAboutSection.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get spaceAboutSection;

  /// No description provided for @spaceDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get spaceDescription;

  /// No description provided for @noDescription.
  ///
  /// In en, this message translates to:
  /// **'No description'**
  String get noDescription;

  /// No description provided for @renameSpace.
  ///
  /// In en, this message translates to:
  /// **'Change the name'**
  String get renameSpace;

  /// No description provided for @editDescription.
  ///
  /// In en, this message translates to:
  /// **'Change the description'**
  String get editDescription;

  /// No description provided for @channels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get channels;

  /// No description provided for @addChannel.
  ///
  /// In en, this message translates to:
  /// **'Add a channel'**
  String get addChannel;

  /// No description provided for @channelName.
  ///
  /// In en, this message translates to:
  /// **'Channel name'**
  String get channelName;

  /// No description provided for @channelForOwners.
  ///
  /// In en, this message translates to:
  /// **'Only the owner and admins write here'**
  String get channelForOwners;

  /// No description provided for @channelForOwnersShort.
  ///
  /// In en, this message translates to:
  /// **'Owner and admins write here'**
  String get channelForOwnersShort;

  /// No description provided for @renameChannel.
  ///
  /// In en, this message translates to:
  /// **'Rename channel'**
  String get renameChannel;

  /// No description provided for @lastChannelStays.
  ///
  /// In en, this message translates to:
  /// **'A space keeps at least one channel.'**
  String get lastChannelStays;

  /// No description provided for @deleteChannelConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'What was said in it will no longer be shown to anyone.'**
  String get deleteChannelConfirmBody;

  /// No description provided for @roleOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get roleOwner;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// No description provided for @makeAdmin.
  ///
  /// In en, this message translates to:
  /// **'Make admin'**
  String get makeAdmin;

  /// No description provided for @removeAdmin.
  ///
  /// In en, this message translates to:
  /// **'Remove as admin'**
  String get removeAdmin;

  /// No description provided for @removeFromSpace.
  ///
  /// In en, this message translates to:
  /// **'Remove from space'**
  String get removeFromSpace;

  /// No description provided for @makeOwner.
  ///
  /// In en, this message translates to:
  /// **'Make owner'**
  String get makeOwner;

  /// No description provided for @handOver.
  ///
  /// In en, this message translates to:
  /// **'Hand over'**
  String get handOver;

  /// No description provided for @handOverConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Make {name} the owner?'**
  String handOverConfirmTitle(String name);

  /// No description provided for @handOverConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'They will run this space from now on, and you will be a member. You cannot take it back; only they can give it to you again. Who is an admin, and who was removed, stays as it is.'**
  String get handOverConfirmBody;

  /// No description provided for @removeMemberConfirmBodyPrivate.
  ///
  /// In en, this message translates to:
  /// **'They keep what was said so far. They get nothing said from now on, and invite links made before now stop working.'**
  String get removeMemberConfirmBodyPrivate;

  /// No description provided for @removeMemberConfirmBodyPublic.
  ///
  /// In en, this message translates to:
  /// **'This space is public, so they can still read it. Nothing they write will be shown to anyone.'**
  String get removeMemberConfirmBodyPublic;

  /// No description provided for @rolesExplained.
  ///
  /// In en, this message translates to:
  /// **'The owner changes the name and channels, chooses admins, removes people and can hand the space to someone else. Admins can pin, write in the info channels and delete messages.'**
  String get rolesExplained;

  /// No description provided for @stopFollowing.
  ///
  /// In en, this message translates to:
  /// **'Stop following'**
  String get stopFollowing;

  /// No description provided for @deleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete for everyone'**
  String get deleteMessage;

  /// No description provided for @editMessage.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editMessage;

  /// No description provided for @editMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Change your message'**
  String get editMessageTitle;

  /// No description provided for @editNotDone.
  ///
  /// In en, this message translates to:
  /// **'This message could not be changed.'**
  String get editNotDone;

  /// No description provided for @messageEdited.
  ///
  /// In en, this message translates to:
  /// **'edited'**
  String get messageEdited;

  /// No description provided for @mentionsYou.
  ///
  /// In en, this message translates to:
  /// **'mentions you'**
  String get mentionsYou;

  /// No description provided for @mentionName.
  ///
  /// In en, this message translates to:
  /// **'Mention {name}'**
  String mentionName(String name);

  /// No description provided for @mentionedYouCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message mentions you} other{{count} messages mention you}}'**
  String mentionedYouCount(int count);

  /// No description provided for @deleteMessageConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this for everyone?'**
  String get deleteMessageConfirmTitle;

  /// No description provided for @deleteMessageConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'It is taken down on every device that has it.'**
  String get deleteMessageConfirmBody;

  /// No description provided for @chatOptions.
  ///
  /// In en, this message translates to:
  /// **'Chat options'**
  String get chatOptions;

  /// No description provided for @spaceOptions.
  ///
  /// In en, this message translates to:
  /// **'Space options'**
  String get spaceOptions;

  /// No description provided for @unmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmute;

  /// No description provided for @blockPerson.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get blockPerson;

  /// No description provided for @renameChannelNamed.
  ///
  /// In en, this message translates to:
  /// **'Rename {name}'**
  String renameChannelNamed(String name);

  /// No description provided for @deleteChannelNamed.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}'**
  String deleteChannelNamed(String name);

  /// No description provided for @deleteChannelConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String deleteChannelConfirmTitle(String name);

  /// No description provided for @removeMemberConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String removeMemberConfirmTitle(String name);

  /// No description provided for @nameAndYou.
  ///
  /// In en, this message translates to:
  /// **'{name} (you)'**
  String nameAndYou(String name);

  /// No description provided for @manageMember.
  ///
  /// In en, this message translates to:
  /// **'Manage {name}'**
  String manageMember(String name);

  /// No description provided for @reply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get reply;

  /// No description provided for @replyingTo.
  ///
  /// In en, this message translates to:
  /// **'Replying to {name}'**
  String replyingTo(String name);

  /// No description provided for @cancelReply.
  ///
  /// In en, this message translates to:
  /// **'Stop replying'**
  String get cancelReply;

  /// No description provided for @pinMessage.
  ///
  /// In en, this message translates to:
  /// **'Pin to the top'**
  String get pinMessage;

  /// No description provided for @unpinMessage.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpinMessage;

  /// No description provided for @newPoll.
  ///
  /// In en, this message translates to:
  /// **'New poll'**
  String get newPoll;

  /// No description provided for @pollQuestion.
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get pollQuestion;

  /// No description provided for @pollChoice.
  ///
  /// In en, this message translates to:
  /// **'Choice {number}'**
  String pollChoice(int number);

  /// No description provided for @addChoice.
  ///
  /// In en, this message translates to:
  /// **'Add a choice'**
  String get addChoice;

  /// No description provided for @sendPoll.
  ///
  /// In en, this message translates to:
  /// **'Send poll'**
  String get sendPoll;

  /// No description provided for @pollNeedsTwo.
  ///
  /// In en, this message translates to:
  /// **'A poll needs a question and at least two choices.'**
  String get pollNeedsTwo;

  /// No description provided for @comment.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get comment;

  /// No description provided for @comments.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get comments;

  /// No description provided for @noCommentsYet.
  ///
  /// In en, this message translates to:
  /// **'No comments yet.'**
  String get noCommentsYet;

  /// No description provided for @writeComment.
  ///
  /// In en, this message translates to:
  /// **'Write a comment'**
  String get writeComment;

  /// No description provided for @commentNameShown.
  ///
  /// In en, this message translates to:
  /// **'Comments can be read by anyone who follows this channel. Your name is shown with yours.'**
  String get commentNameShown;

  /// No description provided for @reactHeart.
  ///
  /// In en, this message translates to:
  /// **'Heart'**
  String get reactHeart;

  /// No description provided for @reactAgree.
  ///
  /// In en, this message translates to:
  /// **'Agree'**
  String get reactAgree;

  /// No description provided for @filePreview.
  ///
  /// In en, this message translates to:
  /// **'File: {name}'**
  String filePreview(String name);

  /// No description provided for @fileAsked.
  ///
  /// In en, this message translates to:
  /// **'Wants to send you this'**
  String get fileAsked;

  /// No description provided for @fileWaitingForAnswer.
  ///
  /// In en, this message translates to:
  /// **'Waiting for them to accept'**
  String get fileWaitingForAnswer;

  /// No description provided for @fileSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get fileSent;

  /// No description provided for @fileSaved.
  ///
  /// In en, this message translates to:
  /// **'Received and saved'**
  String get fileSaved;

  /// No description provided for @fileDeclined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get fileDeclined;

  /// No description provided for @fileCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get fileCancelled;

  /// No description provided for @fileFailed.
  ///
  /// In en, this message translates to:
  /// **'Did not arrive whole, so it was not kept'**
  String get fileFailed;

  /// No description provided for @fileSavedAtTitle.
  ///
  /// In en, this message translates to:
  /// **'Where it was saved'**
  String get fileSavedAtTitle;

  /// No description provided for @fileNotSent.
  ///
  /// In en, this message translates to:
  /// **'That file could not be sent.'**
  String get fileNotSent;

  /// No description provided for @channelFileNotSent.
  ///
  /// In en, this message translates to:
  /// **'That could not be posted. A file in a channel can be up to 25 MB.'**
  String get channelFileNotSent;

  /// No description provided for @radarDistanceNote.
  ///
  /// In en, this message translates to:
  /// **'Nearer the middle is nearer you. Bluetooth cannot tell which way.'**
  String get radarDistanceNote;

  /// No description provided for @meshWifi.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi'**
  String get meshWifi;

  /// No description provided for @meshInRange.
  ///
  /// In en, this message translates to:
  /// **'{count} in range'**
  String meshInRange(int count);

  /// No description provided for @meshThroughOthers.
  ///
  /// In en, this message translates to:
  /// **'{count} through others'**
  String meshThroughOthers(int count);

  /// No description provided for @meshMapLabel.
  ///
  /// In en, this message translates to:
  /// **'{radio} map: {inRange} in range, {through} through others'**
  String meshMapLabel(String radio, int inRange, int through);

  /// No description provided for @meshDirect.
  ///
  /// In en, this message translates to:
  /// **'Direct'**
  String get meshDirect;

  /// No description provided for @meshHops.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hop} other{{count} hops}}'**
  String meshHops(int count);

  /// No description provided for @meshThroughPath.
  ///
  /// In en, this message translates to:
  /// **'through {path}'**
  String meshThroughPath(String path);

  /// No description provided for @signalStrong.
  ///
  /// In en, this message translates to:
  /// **'Strong signal'**
  String get signalStrong;

  /// No description provided for @signalFair.
  ///
  /// In en, this message translates to:
  /// **'Fair signal'**
  String get signalFair;

  /// No description provided for @signalWeak.
  ///
  /// In en, this message translates to:
  /// **'Weak signal'**
  String get signalWeak;

  /// No description provided for @meshOpenMap.
  ///
  /// In en, this message translates to:
  /// **'Open the map'**
  String get meshOpenMap;

  /// No description provided for @meshNobodyOn.
  ///
  /// In en, this message translates to:
  /// **'Nobody on {radio} right now.'**
  String meshNobodyOn(String radio);

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @saveACopy.
  ///
  /// In en, this message translates to:
  /// **'Save a copy'**
  String get saveACopy;

  /// No description provided for @fileNotSaved.
  ///
  /// In en, this message translates to:
  /// **'That file could not be saved.'**
  String get fileNotSaved;

  /// No description provided for @fileWaitingForHolder.
  ///
  /// In en, this message translates to:
  /// **'Waiting for someone in range who has it'**
  String get fileWaitingForHolder;

  /// No description provided for @fileComing.
  ///
  /// In en, this message translates to:
  /// **'Getting it: {percent}%'**
  String fileComing(int percent);

  /// No description provided for @receivingFile.
  ///
  /// In en, this message translates to:
  /// **'Receiving file'**
  String get receivingFile;

  /// No description provided for @fileSizeFrom.
  ///
  /// In en, this message translates to:
  /// **'{size}, from {name}'**
  String fileSizeFrom(String size, String name);

  /// No description provided for @kilobytesPerSecond.
  ///
  /// In en, this message translates to:
  /// **'{value} KB/s'**
  String kilobytesPerSecond(int value);

  /// No description provided for @stepStayingOnBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Going over Bluetooth, which is slow for big files'**
  String get stepStayingOnBluetooth;

  /// No description provided for @sendBigFileDetailBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Goes over Bluetooth for now. Slow for big files.'**
  String get sendBigFileDetailBluetooth;

  /// No description provided for @linkNoticeTitle.
  ///
  /// In en, this message translates to:
  /// **'DNet is on'**
  String get linkNoticeTitle;

  /// No description provided for @linkNoticeText.
  ///
  /// In en, this message translates to:
  /// **'Finding people nearby over Bluetooth.'**
  String get linkNoticeText;

  /// No description provided for @linkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied. It works once, for a day. Send it any way you like.'**
  String get linkCopied;

  /// No description provided for @linkRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Request sent. It reaches them when a path opens.'**
  String get linkRequestSent;

  /// No description provided for @personLinkRunOutTitle.
  ///
  /// In en, this message translates to:
  /// **'This link has run out'**
  String get personLinkRunOutTitle;

  /// No description provided for @personLinkRunOutBody.
  ///
  /// In en, this message translates to:
  /// **'Each DNet link works once, for a day. Ask them to send a new one.'**
  String get personLinkRunOutBody;

  /// No description provided for @linkAlreadyContact.
  ///
  /// In en, this message translates to:
  /// **'You already chat with this person.'**
  String get linkAlreadyContact;

  /// No description provided for @linkIsYours.
  ///
  /// In en, this message translates to:
  /// **'That is your own link.'**
  String get linkIsYours;

  /// No description provided for @linkNotValidTitle.
  ///
  /// In en, this message translates to:
  /// **'That is not a DNet link'**
  String get linkNotValidTitle;

  /// No description provided for @linkNotValidBody.
  ///
  /// In en, this message translates to:
  /// **'Copy the whole link, then press Paste again.'**
  String get linkNotValidBody;

  /// No description provided for @searchChats.
  ///
  /// In en, this message translates to:
  /// **'Search chats'**
  String get searchChats;

  /// No description provided for @noChatsFound.
  ///
  /// In en, this message translates to:
  /// **'No chats match.'**
  String get noChatsFound;

  /// No description provided for @lockedTitle.
  ///
  /// In en, this message translates to:
  /// **'DNet is locked'**
  String get lockedTitle;

  /// No description provided for @passcode.
  ///
  /// In en, this message translates to:
  /// **'Passcode'**
  String get passcode;

  /// No description provided for @passcodeAgain.
  ///
  /// In en, this message translates to:
  /// **'Passcode again'**
  String get passcodeAgain;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @wrongPasscode.
  ///
  /// In en, this message translates to:
  /// **'That is not the passcode.'**
  String get wrongPasscode;

  /// No description provided for @triesLeft.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 try left before everything is erased.} other{{count} tries left before everything is erased.}}'**
  String triesLeft(int count);

  /// No description provided for @setPasscodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a passcode'**
  String get setPasscodeTitle;

  /// No description provided for @setPasscodeBody.
  ///
  /// In en, this message translates to:
  /// **'DNet asks for it each time it opens. Use at least 4 characters. If you forget it, the only way back in is to wipe everything.'**
  String get setPasscodeBody;

  /// No description provided for @setPasscode.
  ///
  /// In en, this message translates to:
  /// **'Set passcode'**
  String get setPasscode;

  /// No description provided for @passcodeTooShort.
  ///
  /// In en, this message translates to:
  /// **'Use at least 4 characters.'**
  String get passcodeTooShort;

  /// No description provided for @passcodesDiffer.
  ///
  /// In en, this message translates to:
  /// **'The two do not match.'**
  String get passcodesDiffer;

  /// No description provided for @removePasscodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch off the app lock'**
  String get removePasscodeTitle;

  /// No description provided for @removePasscodeBody.
  ///
  /// In en, this message translates to:
  /// **'Enter your passcode to switch it off.'**
  String get removePasscodeBody;

  /// No description provided for @switchOff.
  ///
  /// In en, this message translates to:
  /// **'Switch off'**
  String get switchOff;

  /// No description provided for @needPasscodeFirst.
  ///
  /// In en, this message translates to:
  /// **'Switch on the app lock first.'**
  String get needPasscodeFirst;

  /// No description provided for @autoDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete old messages?'**
  String get autoDeleteConfirmTitle;

  /// No description provided for @autoDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Chat messages older than 30 days are deleted from this {device, select, pc{PC} other{phone}}, now and from now on. Notes to self, spaces and files are kept.'**
  String autoDeleteConfirmBody(String device);

  /// No description provided for @autoDeleteConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Delete old messages'**
  String get autoDeleteConfirmAction;

  /// No description provided for @notBuiltTag.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get notBuiltTag;

  /// No description provided for @notSetUp.
  ///
  /// In en, this message translates to:
  /// **'Not set up'**
  String get notSetUp;

  /// No description provided for @nothingBeingSent.
  ///
  /// In en, this message translates to:
  /// **'Nothing is being sent right now.'**
  String get nothingBeingSent;

  /// No description provided for @linksAreWorking.
  ///
  /// In en, this message translates to:
  /// **'Your links are working.'**
  String get linksAreWorking;

  /// No description provided for @radioBluetoothOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is off'**
  String get radioBluetoothOffTitle;

  /// No description provided for @radioBluetoothOffBody.
  ///
  /// In en, this message translates to:
  /// **'DNet finds people nearby over Bluetooth. Switch it on to see who is around.'**
  String get radioBluetoothOffBody;

  /// No description provided for @radioBluetoothOffAction.
  ///
  /// In en, this message translates to:
  /// **'Switch on Bluetooth'**
  String get radioBluetoothOffAction;

  /// No description provided for @radioNoPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'DNet may not use Bluetooth yet'**
  String get radioNoPermissionTitle;

  /// No description provided for @radioNoPermissionBody.
  ///
  /// In en, this message translates to:
  /// **'DNet needs your permission to use Bluetooth, to find people near you and carry your chats. Your device may call this Nearby devices or Location. DNet never reads where you are.'**
  String get radioNoPermissionBody;

  /// No description provided for @radioNoPermissionAction.
  ///
  /// In en, this message translates to:
  /// **'Allow Bluetooth'**
  String get radioNoPermissionAction;

  /// No description provided for @radioLocationOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Location is off'**
  String get radioLocationOffTitle;

  /// No description provided for @radioLocationOffBody.
  ///
  /// In en, this message translates to:
  /// **'On this version of Android, apps can only find Bluetooth devices while Location is on. DNet never reads where you are.'**
  String get radioLocationOffBody;

  /// No description provided for @radioLocationOffAction.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get radioLocationOffAction;

  /// No description provided for @radioUnsupportedTitle.
  ///
  /// In en, this message translates to:
  /// **'No Bluetooth here'**
  String get radioUnsupportedTitle;

  /// No description provided for @radioUnsupportedBody.
  ///
  /// In en, this message translates to:
  /// **'DNet could not find a Bluetooth radio it can use on this device, so it cannot find people nearby.'**
  String get radioUnsupportedBody;

  /// No description provided for @radioSwitchedOffTitle.
  ///
  /// In en, this message translates to:
  /// **'The Bluetooth link is switched off'**
  String get radioSwitchedOffTitle;

  /// No description provided for @radioSwitchedOffBody.
  ///
  /// In en, this message translates to:
  /// **'You switched it off in Network. Switch it on again to find people nearby.'**
  String get radioSwitchedOffBody;

  /// No description provided for @radioSwitchedOffAction.
  ///
  /// In en, this message translates to:
  /// **'Open Network'**
  String get radioSwitchedOffAction;

  /// No description provided for @keyChangedTitle.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s key has changed'**
  String keyChangedTitle(String name);

  /// No description provided for @keyChangedBody.
  ///
  /// In en, this message translates to:
  /// **'This is not the key you had for {name}. It may be a new device, or someone pretending to be them. They are not verified. Compare words before you share anything private.'**
  String keyChangedBody(String name);

  /// No description provided for @acceptAnyway.
  ///
  /// In en, this message translates to:
  /// **'Accept anyway'**
  String get acceptAnyway;

  /// No description provided for @voiceCall.
  ///
  /// In en, this message translates to:
  /// **'Voice call'**
  String get voiceCall;

  /// No description provided for @videoCall.
  ///
  /// In en, this message translates to:
  /// **'Video call'**
  String get videoCall;

  /// No description provided for @soonLabel.
  ///
  /// In en, this message translates to:
  /// **'{what} · {soon}'**
  String soonLabel(String what, String soon);

  /// No description provided for @callCalling.
  ///
  /// In en, this message translates to:
  /// **'Calling'**
  String get callCalling;

  /// No description provided for @callRinging.
  ///
  /// In en, this message translates to:
  /// **'Ringing'**
  String get callRinging;

  /// No description provided for @callSettingUpWifi.
  ///
  /// In en, this message translates to:
  /// **'Setting up Wi-Fi'**
  String get callSettingUpWifi;

  /// No description provided for @callIsCalling.
  ///
  /// In en, this message translates to:
  /// **'{name} is calling'**
  String callIsCalling(String name);

  /// No description provided for @callAnswer.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get callAnswer;

  /// No description provided for @callHangUp.
  ///
  /// In en, this message translates to:
  /// **'Hang up'**
  String get callHangUp;

  /// No description provided for @callEnded.
  ///
  /// In en, this message translates to:
  /// **'Call ended'**
  String get callEnded;

  /// No description provided for @callDeclined.
  ///
  /// In en, this message translates to:
  /// **'{name} turned the call down'**
  String callDeclined(String name);

  /// No description provided for @callBusy.
  ///
  /// In en, this message translates to:
  /// **'{name} is in another call'**
  String callBusy(String name);

  /// No description provided for @callNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'No answer'**
  String get callNoAnswer;

  /// No description provided for @callNeedsWifi.
  ///
  /// In en, this message translates to:
  /// **'Calls need Wi-Fi. Bluetooth is too slow for live sound, and no Wi-Fi link could be set up with {name}.'**
  String callNeedsWifi(String name);

  /// No description provided for @callLost.
  ///
  /// In en, this message translates to:
  /// **'The link to {name} was lost'**
  String callLost(String name);

  /// No description provided for @callFailed.
  ///
  /// In en, this message translates to:
  /// **'The call could not be set up safely'**
  String get callFailed;

  /// No description provided for @callNotInRange.
  ///
  /// In en, this message translates to:
  /// **'{name} is not in range. Calls work only with someone nearby.'**
  String callNotInRange(String name);

  /// No description provided for @callAlreadyIn.
  ///
  /// In en, this message translates to:
  /// **'You are already in a call'**
  String get callAlreadyIn;

  /// No description provided for @callRefused.
  ///
  /// In en, this message translates to:
  /// **'This call could not be made'**
  String get callRefused;

  /// No description provided for @callReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi link lost. Trying to get it back'**
  String get callReconnecting;

  /// No description provided for @callMicMissing.
  ///
  /// In en, this message translates to:
  /// **'Your microphone can\'t be used, so they can\'t hear you. Check that DNet is allowed to use it.'**
  String get callMicMissing;

  /// No description provided for @callTheyMuted.
  ///
  /// In en, this message translates to:
  /// **'{name} is muted'**
  String callTheyMuted(String name);

  /// No description provided for @callLoudspeakerOn.
  ///
  /// In en, this message translates to:
  /// **'Turn the loudspeaker on'**
  String get callLoudspeakerOn;

  /// No description provided for @callLoudspeakerOff.
  ///
  /// In en, this message translates to:
  /// **'Turn the loudspeaker off'**
  String get callLoudspeakerOff;

  /// No description provided for @turnCameraOff.
  ///
  /// In en, this message translates to:
  /// **'Turn camera off'**
  String get turnCameraOff;

  /// No description provided for @callMinimise.
  ///
  /// In en, this message translates to:
  /// **'Back to the app'**
  String get callMinimise;

  /// No description provided for @callReturn.
  ///
  /// In en, this message translates to:
  /// **'Return to the call'**
  String get callReturn;

  /// No description provided for @callBarPerson.
  ///
  /// In en, this message translates to:
  /// **'In a call with {name}'**
  String callBarPerson(String name);

  /// No description provided for @callBarRoom.
  ///
  /// In en, this message translates to:
  /// **'In {room}'**
  String callBarRoom(String room);

  /// No description provided for @callOverWifi.
  ///
  /// In en, this message translates to:
  /// **'Over Wi-Fi, end-to-end encrypted'**
  String get callOverWifi;

  /// No description provided for @callKeyNoteTwo.
  ///
  /// In en, this message translates to:
  /// **'If you both see these words, nobody is listening in.'**
  String get callKeyNoteTwo;

  /// No description provided for @callTheirCameraOff.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s camera is off'**
  String callTheirCameraOff(String name);

  /// No description provided for @roomJoining.
  ///
  /// In en, this message translates to:
  /// **'Joining'**
  String get roomJoining;

  /// No description provided for @soundOff.
  ///
  /// In en, this message translates to:
  /// **'Turn sound off'**
  String get soundOff;

  /// No description provided for @soundOn.
  ///
  /// In en, this message translates to:
  /// **'Turn sound back on'**
  String get soundOn;

  /// No description provided for @roomSoundOff.
  ///
  /// In en, this message translates to:
  /// **'Sound off'**
  String get roomSoundOff;

  /// No description provided for @roomNoWifi.
  ///
  /// In en, this message translates to:
  /// **'No Wi-Fi link'**
  String get roomNoWifi;

  /// No description provided for @roomOwnerMuted.
  ///
  /// In en, this message translates to:
  /// **'Muted by an admin'**
  String get roomOwnerMuted;

  /// No description provided for @roomOwnerDeafened.
  ///
  /// In en, this message translates to:
  /// **'Can\'t hear'**
  String get roomOwnerDeafened;

  /// No description provided for @roomYouOwnerMuted.
  ///
  /// In en, this message translates to:
  /// **'An admin has muted you in this space\'s voice rooms.'**
  String get roomYouOwnerMuted;

  /// No description provided for @roomYouOwnerDeafened.
  ///
  /// In en, this message translates to:
  /// **'An admin has deafened you in this space\'s voice rooms.'**
  String get roomYouOwnerDeafened;

  /// No description provided for @roomMuteFor.
  ///
  /// In en, this message translates to:
  /// **'Mute {name} for everyone'**
  String roomMuteFor(String name);

  /// No description provided for @roomUnmuteFor.
  ///
  /// In en, this message translates to:
  /// **'Let {name} speak'**
  String roomUnmuteFor(String name);

  /// No description provided for @roomDeafen.
  ///
  /// In en, this message translates to:
  /// **'Deafen {name}'**
  String roomDeafen(String name);

  /// No description provided for @roomUndeafen.
  ///
  /// In en, this message translates to:
  /// **'Let {name} hear'**
  String roomUndeafen(String name);

  /// No description provided for @roomRuleNotSet.
  ///
  /// In en, this message translates to:
  /// **'That could not be changed.'**
  String get roomRuleNotSet;

  /// No description provided for @roomCannotJoin.
  ///
  /// In en, this message translates to:
  /// **'This voice room can\'t be joined.'**
  String get roomCannotJoin;

  /// No description provided for @roomEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nobody else is here yet.'**
  String get roomEmpty;

  /// No description provided for @voiceRoomKind.
  ///
  /// In en, this message translates to:
  /// **'Voice room'**
  String get voiceRoomKind;

  /// No description provided for @tapHoldTitle.
  ///
  /// In en, this message translates to:
  /// **'Hold your phones back to back'**
  String get tapHoldTitle;

  /// No description provided for @tapHoldBody.
  ///
  /// In en, this message translates to:
  /// **'Keep this screen open on both phones. It takes a second or two.'**
  String get tapHoldBody;

  /// No description provided for @tapNfcOffTitle.
  ///
  /// In en, this message translates to:
  /// **'NFC is off'**
  String get tapNfcOffTitle;

  /// No description provided for @tapNfcOffBody.
  ///
  /// In en, this message translates to:
  /// **'Switch on NFC to tap phones together.'**
  String get tapNfcOffBody;

  /// No description provided for @tapOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open NFC settings'**
  String get tapOpenSettings;

  /// No description provided for @tapGotTheirs.
  ///
  /// In en, this message translates to:
  /// **'Got their code. Chat request sent.'**
  String get tapGotTheirs;

  /// No description provided for @tapGaveMine.
  ///
  /// In en, this message translates to:
  /// **'They have your code.'**
  String get tapGaveMine;

  /// No description provided for @fromStranger.
  ///
  /// In en, this message translates to:
  /// **'From someone you have not accepted'**
  String get fromStranger;

  /// No description provided for @tapToShow.
  ///
  /// In en, this message translates to:
  /// **'Tap to show'**
  String get tapToShow;

  /// No description provided for @spoiler.
  ///
  /// In en, this message translates to:
  /// **'Spoiler, tap to show'**
  String get spoiler;

  /// No description provided for @statusTitle.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get statusTitle;

  /// No description provided for @statusBody.
  ///
  /// In en, this message translates to:
  /// **'Only members of your spaces who are in range are told. Nobody else is.'**
  String get statusBody;

  /// No description provided for @statusOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get statusOnline;

  /// No description provided for @statusIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get statusIdle;

  /// No description provided for @statusDnd.
  ///
  /// In en, this message translates to:
  /// **'Do not disturb'**
  String get statusDnd;

  /// No description provided for @statusInvisible.
  ///
  /// In en, this message translates to:
  /// **'Invisible'**
  String get statusInvisible;

  /// No description provided for @statusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get statusOffline;

  /// No description provided for @statusOnlineDetail.
  ///
  /// In en, this message translates to:
  /// **'Members in range see you are here. Being in range already shows them that.'**
  String get statusOnlineDetail;

  /// No description provided for @statusIdleDetail.
  ///
  /// In en, this message translates to:
  /// **'Members in range see you are away for now.'**
  String get statusIdleDetail;

  /// No description provided for @statusDndDetail.
  ///
  /// In en, this message translates to:
  /// **'Members in range see you would rather not be disturbed. Alerts still come.'**
  String get statusDndDetail;

  /// No description provided for @statusInvisibleDetail.
  ///
  /// In en, this message translates to:
  /// **'Nothing is sent: members see you as offline and are not told when you type. Devices in range still pass messages on, so someone nearby may tell you are there.'**
  String get statusInvisibleDetail;

  /// No description provided for @statusNotChanged.
  ///
  /// In en, this message translates to:
  /// **'Your status could not be changed.'**
  String get statusNotChanged;

  /// No description provided for @everyoneNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Only the owner, admins and roles allowed to can call on @everyone.'**
  String get everyoneNotAllowed;

  /// No description provided for @rolePowerMentionEveryone.
  ///
  /// In en, this message translates to:
  /// **'Call on @everyone'**
  String get rolePowerMentionEveryone;

  /// No description provided for @forwardMessage.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forwardMessage;

  /// No description provided for @forwardTitle.
  ///
  /// In en, this message translates to:
  /// **'Forward to'**
  String get forwardTitle;

  /// No description provided for @forwardBody.
  ///
  /// In en, this message translates to:
  /// **'It goes as your own message, marked as forwarded. Where it came from and who wrote it are not said.'**
  String get forwardBody;

  /// No description provided for @nowhereToForward.
  ///
  /// In en, this message translates to:
  /// **'There is nowhere to forward this yet: no channel you can write in and no contacts.'**
  String get nowhereToForward;

  /// No description provided for @forwardChannels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get forwardChannels;

  /// No description provided for @forwardContacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get forwardContacts;

  /// No description provided for @forwardToChannel.
  ///
  /// In en, this message translates to:
  /// **'Forward to {channel} in {space}'**
  String forwardToChannel(String channel, String space);

  /// No description provided for @forwardToContact.
  ///
  /// In en, this message translates to:
  /// **'Forward to {name}'**
  String forwardToContact(String name);

  /// No description provided for @forwarded.
  ///
  /// In en, this message translates to:
  /// **'Forwarded'**
  String get forwarded;

  /// No description provided for @forwardFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not forward it. They may no longer be a contact.'**
  String get forwardFailed;

  /// No description provided for @messageForwarded.
  ///
  /// In en, this message translates to:
  /// **'forwarded'**
  String get messageForwarded;

  /// No description provided for @typingOne.
  ///
  /// In en, this message translates to:
  /// **'{name} is typing…'**
  String typingOne(String name);

  /// No description provided for @typingTwo.
  ///
  /// In en, this message translates to:
  /// **'{first} and {second} are typing…'**
  String typingTwo(String first, String second);

  /// No description provided for @typingMany.
  ///
  /// In en, this message translates to:
  /// **'Several people are typing…'**
  String get typingMany;

  /// No description provided for @searchChannel.
  ///
  /// In en, this message translates to:
  /// **'Search this channel'**
  String get searchChannel;

  /// No description provided for @searchChannelHint.
  ///
  /// In en, this message translates to:
  /// **'Search #{channel}'**
  String searchChannelHint(String channel);

  /// No description provided for @noSearchMatches.
  ///
  /// In en, this message translates to:
  /// **'Nothing here matches.'**
  String get noSearchMatches;

  /// No description provided for @newMessages.
  ///
  /// In en, this message translates to:
  /// **'New messages'**
  String get newMessages;

  /// No description provided for @spaceRules.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get spaceRules;

  /// No description provided for @spaceRulesOf.
  ///
  /// In en, this message translates to:
  /// **'Rules of {space}'**
  String spaceRulesOf(String space);

  /// No description provided for @noRulesYet.
  ///
  /// In en, this message translates to:
  /// **'No rules written yet.'**
  String get noRulesYet;

  /// No description provided for @rulesSignedNote.
  ///
  /// In en, this message translates to:
  /// **'Written and signed by the owner. Every member\'s app checks the signature.'**
  String get rulesSignedNote;

  /// No description provided for @spaceRulesBody.
  ///
  /// In en, this message translates to:
  /// **'Shown to everyone in the space. Up to 2000 characters.'**
  String get spaceRulesBody;

  /// No description provided for @rulesTooLong.
  ///
  /// In en, this message translates to:
  /// **'Rules can be up to 2000 characters.'**
  String get rulesTooLong;

  /// No description provided for @editRules.
  ///
  /// In en, this message translates to:
  /// **'Edit the rules'**
  String get editRules;

  /// No description provided for @welcomeTo.
  ///
  /// In en, this message translates to:
  /// **'Welcome to {space}'**
  String welcomeTo(String space);

  /// No description provided for @readTheRules.
  ///
  /// In en, this message translates to:
  /// **'Read the rules'**
  String get readTheRules;

  /// No description provided for @welcomeMessage.
  ///
  /// In en, this message translates to:
  /// **'Welcome message'**
  String get welcomeMessage;

  /// No description provided for @welcomeMessageBody.
  ///
  /// In en, this message translates to:
  /// **'Shown at the top of the space to everyone who joins. Up to 500 characters.'**
  String get welcomeMessageBody;

  /// No description provided for @welcomeTooLong.
  ///
  /// In en, this message translates to:
  /// **'A welcome can be up to 500 characters.'**
  String get welcomeTooLong;

  /// No description provided for @noWelcomeYet.
  ///
  /// In en, this message translates to:
  /// **'No welcome message yet.'**
  String get noWelcomeYet;

  /// No description provided for @editWelcome.
  ///
  /// In en, this message translates to:
  /// **'Edit the welcome message'**
  String get editWelcome;

  /// No description provided for @changeNickname.
  ///
  /// In en, this message translates to:
  /// **'Change nickname'**
  String get changeNickname;

  /// No description provided for @changeNicknameOf.
  ///
  /// In en, this message translates to:
  /// **'Change {name}\'s nickname'**
  String changeNicknameOf(String name);

  /// No description provided for @changeNicknameBody.
  ///
  /// In en, this message translates to:
  /// **'Everyone in this space sees them by this name. Leave it empty to give them back their own.'**
  String get changeNicknameBody;

  /// No description provided for @nickname.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get nickname;

  /// No description provided for @scanNotInRangeTitle.
  ///
  /// In en, this message translates to:
  /// **'They are not in range'**
  String get scanNotInRangeTitle;

  /// No description provided for @scanNotInRangeBody.
  ///
  /// In en, this message translates to:
  /// **'A code works when you are near each other. Open DNet on both and come closer, or send them a link instead.'**
  String get scanNotInRangeBody;

  /// No description provided for @profilePhoto.
  ///
  /// In en, this message translates to:
  /// **'Profile photo'**
  String get profilePhoto;

  /// No description provided for @profilePhotoBody.
  ///
  /// In en, this message translates to:
  /// **'A picture or a GIF. It is made small on this device first. Your contacts and the members of your spaces see it. You can stop showing it under Privacy.'**
  String get profilePhotoBody;

  /// No description provided for @choosePhoto.
  ///
  /// In en, this message translates to:
  /// **'Choose a picture or GIF'**
  String get choosePhoto;

  /// No description provided for @removePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get removePhoto;

  /// No description provided for @photoSet.
  ///
  /// In en, this message translates to:
  /// **'Your photo is set.'**
  String get photoSet;

  /// No description provided for @photoNotUsable.
  ///
  /// In en, this message translates to:
  /// **'That picture could not be used. Try a JPEG, PNG or a shorter GIF.'**
  String get photoNotUsable;

  /// No description provided for @showMyPhoto.
  ///
  /// In en, this message translates to:
  /// **'Show my profile photo'**
  String get showMyPhoto;

  /// No description provided for @spaceIcon.
  ///
  /// In en, this message translates to:
  /// **'Space icon'**
  String get spaceIcon;

  /// No description provided for @spaceIconNone.
  ///
  /// In en, this message translates to:
  /// **'No icon yet. Its initials are shown.'**
  String get spaceIconNone;

  /// No description provided for @spaceIconChosen.
  ///
  /// In en, this message translates to:
  /// **'A picture or GIF you chose.'**
  String get spaceIconChosen;

  /// No description provided for @changeSpaceIcon.
  ///
  /// In en, this message translates to:
  /// **'Change the space icon'**
  String get changeSpaceIcon;

  /// No description provided for @spaceIconBody.
  ///
  /// In en, this message translates to:
  /// **'A picture or a GIF. It is made small on this device first. Everyone in this space sees it.'**
  String get spaceIconBody;

  /// No description provided for @spaceIconBodyPublic.
  ///
  /// In en, this message translates to:
  /// **'A picture or a GIF. It is made small on this device first. Everyone in this space sees it, and so does anyone nearby who can find it.'**
  String get spaceIconBodyPublic;

  /// No description provided for @removeSpaceIcon.
  ///
  /// In en, this message translates to:
  /// **'Remove icon'**
  String get removeSpaceIcon;

  /// No description provided for @spaceIconSet.
  ///
  /// In en, this message translates to:
  /// **'The space icon is set.'**
  String get spaceIconSet;

  /// No description provided for @codeWordsNote.
  ///
  /// In en, this message translates to:
  /// **'These words change every 10 minutes. They help people nearby tell you apart from someone with the same name. They do not prove who you are.'**
  String get codeWordsNote;

  /// No description provided for @scanUnavailable.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{This PC has no camera DNet can use.} other{This phone has no camera DNet can use.}} Use Find nearby or a link instead.'**
  String scanUnavailable(String device);

  /// No description provided for @tapUnavailable.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{This PC has no NFC.} other{This phone has no NFC.}} Use Find nearby or a link instead.'**
  String tapUnavailable(String device);

  /// No description provided for @findingLocation.
  ///
  /// In en, this message translates to:
  /// **'Finding where you are…'**
  String get findingLocation;

  /// No description provided for @shareLocationWarnTitle.
  ///
  /// In en, this message translates to:
  /// **'Send your exact location?'**
  String get shareLocationWarnTitle;

  /// No description provided for @shareLocationWarnBody.
  ///
  /// In en, this message translates to:
  /// **'Your exact location will be sent to {to}: {where}. Only send it if you are happy for them to know where you are.'**
  String shareLocationWarnBody(String to, String where);

  /// No description provided for @shareLocationWarnBodyChannel.
  ///
  /// In en, this message translates to:
  /// **'Your exact location will be posted in this channel: {where}. Everyone who can read it will know where you are.'**
  String shareLocationWarnBodyChannel(String where);

  /// No description provided for @placeWithin.
  ///
  /// In en, this message translates to:
  /// **'{place}, to within about {metres} m'**
  String placeWithin(String place, int metres);

  /// No description provided for @locationNotSent.
  ///
  /// In en, this message translates to:
  /// **'Your location was not sent.'**
  String get locationNotSent;

  /// No description provided for @locationDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'DNet can\'t see where you are'**
  String get locationDeniedTitle;

  /// No description provided for @locationDeniedBody.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{Windows has not let DNet know where this PC is. In Settings, under Privacy & security, Location, let desktop apps see your location, then try again.} other{Allow DNet to use your location in Settings, then try again.}}'**
  String locationDeniedBody(String device);

  /// No description provided for @locationOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Location is off'**
  String get locationOffTitle;

  /// No description provided for @locationOffBody.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{Turn on location services in Settings, under Privacy & security, Location, then try again.} other{Turn on location for this phone, then try again.}}'**
  String locationOffBody(String device);

  /// No description provided for @locationUnknownTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find where you are'**
  String get locationUnknownTitle;

  /// No description provided for @locationUnknownBody.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{Windows could not tell where this PC is. A PC without GPS works it out from Wi-Fi networks nearby, which needs the internet.} other{Your phone could not tell in time. GPS finds you more easily outside or near a window.}}'**
  String locationUnknownBody(String device);

  /// No description provided for @openLocationSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openLocationSettings;

  /// No description provided for @locationCard.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get locationCard;

  /// No description provided for @locationWithin.
  ///
  /// In en, this message translates to:
  /// **'Within about {metres} m'**
  String locationWithin(int metres);

  /// No description provided for @locationCardLabel.
  ///
  /// In en, this message translates to:
  /// **'Location: {place}'**
  String locationCardLabel(String place);

  /// No description provided for @locationCopied.
  ///
  /// In en, this message translates to:
  /// **'Location copied'**
  String get locationCopied;

  /// No description provided for @openInMaps.
  ///
  /// In en, this message translates to:
  /// **'Open in maps'**
  String get openInMaps;

  /// No description provided for @openMapWarnTitle.
  ///
  /// In en, this message translates to:
  /// **'Open this place in a map?'**
  String get openMapWarnTitle;

  /// No description provided for @openMapWarnBody.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{This opens openstreetmap.org in your browser. That site will learn this place and your internet address.} other{Your map app will be shown this place. It may look it up online, which tells its maker about this place.}}'**
  String openMapWarnBody(String device);

  /// No description provided for @noMapApp.
  ///
  /// In en, this message translates to:
  /// **'There is no map app to open it in.'**
  String get noMapApp;

  /// No description provided for @cameraStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting the camera…'**
  String get cameraStarting;

  /// No description provided for @cameraUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'The camera could not be opened'**
  String get cameraUnavailableTitle;

  /// No description provided for @cameraUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'Another app may be using it, or Windows may not let desktop apps use the camera. Check Settings, under Privacy & security, Camera, then try again.'**
  String get cameraUnavailableBody;

  /// No description provided for @emojiAndStickers.
  ///
  /// In en, this message translates to:
  /// **'Emoji and stickers'**
  String get emojiAndStickers;

  /// No description provided for @showKeyboard.
  ///
  /// In en, this message translates to:
  /// **'Keyboard'**
  String get showKeyboard;

  /// No description provided for @emojiTab.
  ///
  /// In en, this message translates to:
  /// **'Emoji'**
  String get emojiTab;

  /// No description provided for @stickersTab.
  ///
  /// In en, this message translates to:
  /// **'Stickers'**
  String get stickersTab;

  /// No description provided for @emojiGroup.
  ///
  /// In en, this message translates to:
  /// **'{group, select, recent{Recent} smileys{Smileys} people{People} nature{Animals and nature} food{Food and drink} activities{Activities} travel{Travel and places} objects{Objects} symbols{Symbols} flags{Flags} other{Emoji}}'**
  String emojiGroup(String group);

  /// No description provided for @noRecentEmoji.
  ///
  /// In en, this message translates to:
  /// **'Emoji you use show up here.'**
  String get noRecentEmoji;

  /// No description provided for @stickerPackTitle.
  ///
  /// In en, this message translates to:
  /// **'DNet stickers'**
  String get stickerPackTitle;

  /// No description provided for @myStickersTitle.
  ///
  /// In en, this message translates to:
  /// **'Your stickers'**
  String get myStickersTitle;

  /// No description provided for @noStickersYet.
  ///
  /// In en, this message translates to:
  /// **'Open a picture or GIF someone sent you and choose Save as sticker to keep it here.'**
  String get noStickersYet;

  /// No description provided for @stickerPreview.
  ///
  /// In en, this message translates to:
  /// **'Sticker'**
  String get stickerPreview;

  /// No description provided for @stickerLabel.
  ///
  /// In en, this message translates to:
  /// **'{name, select, hello{Sticker: Hi!} thanks{Sticker: Thanks!} lol{Sticker: laughing} love{Sticker: in love} wow{Sticker: wow} sad{Sticker: sad} angry{Sticker: angry} cool{Sticker: cool} sleepy{Sticker: sleepy} party{Sticker: party} ok{Sticker: OK!} cat{Sticker: cat} other{Sticker}}'**
  String stickerLabel(String name);

  /// No description provided for @stickerUnknown.
  ///
  /// In en, this message translates to:
  /// **'A sticker this version of DNet does not have'**
  String get stickerUnknown;

  /// No description provided for @stickerNotSent.
  ///
  /// In en, this message translates to:
  /// **'The sticker was not sent.'**
  String get stickerNotSent;

  /// No description provided for @saveAsSticker.
  ///
  /// In en, this message translates to:
  /// **'Save as sticker'**
  String get saveAsSticker;

  /// No description provided for @stickerSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to your stickers.'**
  String get stickerSaved;

  /// No description provided for @stickerNotMade.
  ///
  /// In en, this message translates to:
  /// **'This picture can\'t be made into a sticker.'**
  String get stickerNotMade;

  /// No description provided for @stickerAlreadyKept.
  ///
  /// In en, this message translates to:
  /// **'It is in your stickers.'**
  String get stickerAlreadyKept;

  /// No description provided for @removeSticker.
  ///
  /// In en, this message translates to:
  /// **'Remove from your stickers'**
  String get removeSticker;

  /// No description provided for @stickerRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed from your stickers.'**
  String get stickerRemoved;

  /// No description provided for @moreEmoji.
  ///
  /// In en, this message translates to:
  /// **'More emoji'**
  String get moreEmoji;

  /// No description provided for @reactWithEmoji.
  ///
  /// In en, this message translates to:
  /// **'React with {emoji}'**
  String reactWithEmoji(String emoji);

  /// No description provided for @emojiReaction.
  ///
  /// In en, this message translates to:
  /// **'{emoji} reaction, {count}'**
  String emojiReaction(String emoji, int count);

  /// No description provided for @chooseReaction.
  ///
  /// In en, this message translates to:
  /// **'Choose a reaction'**
  String get chooseReaction;

  /// No description provided for @shareVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get shareVideo;

  /// No description provided for @videoNamed.
  ///
  /// In en, this message translates to:
  /// **'Video: {name}'**
  String videoNamed(String name);

  /// No description provided for @videoLength.
  ///
  /// In en, this message translates to:
  /// **'{length} long'**
  String videoLength(String length);

  /// No description provided for @playVideo.
  ///
  /// In en, this message translates to:
  /// **'Play video'**
  String get playVideo;

  /// No description provided for @pauseVideo.
  ///
  /// In en, this message translates to:
  /// **'Pause video'**
  String get pauseVideo;

  /// No description provided for @videoFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Full screen'**
  String get videoFullScreen;

  /// No description provided for @videoCannotPlay.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{This PC can\'t play this video. Windows plays the kinds of video it has codecs for.} other{This phone can\'t play this video.}}'**
  String videoCannotPlay(String device);

  /// No description provided for @videoNotHere.
  ///
  /// In en, this message translates to:
  /// **'Not on this device yet'**
  String get videoNotHere;

  /// No description provided for @videosSentAsTheyAre.
  ///
  /// In en, this message translates to:
  /// **'Only photos have their location taken out. Videos are sent as they are, with anything the camera noted.'**
  String get videosSentAsTheyAre;

  /// No description provided for @videoPosition.
  ///
  /// In en, this message translates to:
  /// **'{position} of {length}'**
  String videoPosition(String position, String length);

  /// No description provided for @videoCallPerson.
  ///
  /// In en, this message translates to:
  /// **'Video call {name}'**
  String videoCallPerson(String name);

  /// No description provided for @timerOffShort.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get timerOffShort;

  /// No description provided for @shareCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get shareCamera;

  /// No description provided for @cameraTitle.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get cameraTitle;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get takePhoto;

  /// No description provided for @retakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get retakePhoto;

  /// No description provided for @usePhoto.
  ///
  /// In en, this message translates to:
  /// **'Use photo'**
  String get usePhoto;

  /// No description provided for @photoNotTaken.
  ///
  /// In en, this message translates to:
  /// **'The photo could not be saved. Try again.'**
  String get photoNotTaken;

  /// No description provided for @cameraDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'DNet may not use the camera'**
  String get cameraDeniedTitle;

  /// No description provided for @cameraDeniedBody.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{To take a photo here, allow the camera for DNet in Windows Settings, under Privacy & security, Camera, then try again.} other{To take a photo here, allow the camera for DNet in your phone\'s settings, then try again.}}'**
  String cameraDeniedBody(String device);

  /// No description provided for @noCameraApp.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{This PC has no camera DNet can use.} other{This phone has no camera app DNet can use.}}'**
  String noCameraApp(String device);

  /// No description provided for @transferOwnership.
  ///
  /// In en, this message translates to:
  /// **'Transfer ownership'**
  String get transferOwnership;

  /// No description provided for @transferOwnershipDetail.
  ///
  /// In en, this message translates to:
  /// **'Hand this space to another member'**
  String get transferOwnershipDetail;

  /// No description provided for @transferOwnershipBody.
  ///
  /// In en, this message translates to:
  /// **'Choose who runs {space} from now on.'**
  String transferOwnershipBody(String space);

  /// No description provided for @transferOwnershipNobody.
  ///
  /// In en, this message translates to:
  /// **'Nobody else is in this space yet. Invite someone, then hand it over.'**
  String get transferOwnershipNobody;

  /// No description provided for @transferConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{name} will own {space}. You will be a member, and can no longer change its name, channels, rules or roles, manage its members, or delete it. Who is an admin, and who was removed, stays as it is.\n\nYou cannot undo this yourself. Only {name} can give it back.'**
  String transferConfirmBody(String name, String space);

  /// No description provided for @transfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get transfer;

  /// No description provided for @transferDone.
  ///
  /// In en, this message translates to:
  /// **'{name} now owns {space}.'**
  String transferDone(String name, String space);

  /// No description provided for @videoPreview.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get videoPreview;

  /// No description provided for @videoPreviewLength.
  ///
  /// In en, this message translates to:
  /// **'Video · {length}'**
  String videoPreviewLength(String length);

  /// No description provided for @videoPreviewReading.
  ///
  /// In en, this message translates to:
  /// **'Video · reading…'**
  String get videoPreviewReading;

  /// No description provided for @videoPreviewNotHere.
  ///
  /// In en, this message translates to:
  /// **'Video · not here yet'**
  String get videoPreviewNotHere;

  /// No description provided for @videoPreviewCannotRead.
  ///
  /// In en, this message translates to:
  /// **'Video · cannot be played here'**
  String get videoPreviewCannotRead;

  /// No description provided for @locationPreview.
  ///
  /// In en, this message translates to:
  /// **'Location · {place}'**
  String locationPreview(String place);

  /// No description provided for @locationPreviewGone.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get locationPreviewGone;

  /// No description provided for @locationAccuracy.
  ///
  /// In en, this message translates to:
  /// **'±{metres} m'**
  String locationAccuracy(int metres);

  /// No description provided for @pollPreview.
  ///
  /// In en, this message translates to:
  /// **'Poll · {question}'**
  String pollPreview(String question);

  /// No description provided for @pollOptionVotes.
  ///
  /// In en, this message translates to:
  /// **'{option} {votes}'**
  String pollOptionVotes(String option, int votes);

  /// No description provided for @pollNoVotesYet.
  ///
  /// In en, this message translates to:
  /// **'No votes yet'**
  String get pollNoVotesYet;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @couldNotChangeSpace.
  ///
  /// In en, this message translates to:
  /// **'That change could not be made.'**
  String get couldNotChangeSpace;

  /// No description provided for @couldNotRemoveIcon.
  ///
  /// In en, this message translates to:
  /// **'The icon could not be removed.'**
  String get couldNotRemoveIcon;

  /// No description provided for @couldNotResetLinks.
  ///
  /// In en, this message translates to:
  /// **'The invite links could not be reset.'**
  String get couldNotResetLinks;

  /// No description provided for @inviteLinksReset.
  ///
  /// In en, this message translates to:
  /// **'Invite links reset.'**
  String get inviteLinksReset;

  /// No description provided for @couldNotDeleteSpace.
  ///
  /// In en, this message translates to:
  /// **'The space could not be deleted.'**
  String get couldNotDeleteSpace;

  /// No description provided for @couldNotLeaveSpace.
  ///
  /// In en, this message translates to:
  /// **'You could not leave just now.'**
  String get couldNotLeaveSpace;

  /// No description provided for @couldNotJoinSpace.
  ///
  /// In en, this message translates to:
  /// **'The space could not be joined.'**
  String get couldNotJoinSpace;

  /// No description provided for @couldNotSetRule.
  ///
  /// In en, this message translates to:
  /// **'The rule could not be set.'**
  String get couldNotSetRule;

  /// No description provided for @couldNotRemoveRole.
  ///
  /// In en, this message translates to:
  /// **'The role \"{name}\" could not be deleted.'**
  String couldNotRemoveRole(String name);

  /// No description provided for @couldNotGiveRole.
  ///
  /// In en, this message translates to:
  /// **'The role could not be changed for {name}.'**
  String couldNotGiveRole(String name);

  /// No description provided for @couldNotChangeAdmin.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s role could not be changed.'**
  String couldNotChangeAdmin(String name);

  /// No description provided for @couldNotTimeOut.
  ///
  /// In en, this message translates to:
  /// **'{name} could not be timed out.'**
  String couldNotTimeOut(String name);

  /// No description provided for @couldNotRemoveMember.
  ///
  /// In en, this message translates to:
  /// **'{name} could not be removed.'**
  String couldNotRemoveMember(String name);

  /// No description provided for @transferFailed.
  ///
  /// In en, this message translates to:
  /// **'{name} could not be made the owner. They may have left the space.'**
  String transferFailed(String name);

  /// No description provided for @verifyByHand.
  ///
  /// In en, this message translates to:
  /// **'Or check by hand'**
  String get verifyByHand;

  /// No description provided for @verifyDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} is verified'**
  String verifyDoneTitle(String name);

  /// No description provided for @verifiedHowTap.
  ///
  /// In en, this message translates to:
  /// **'Verified by a tap on {date}. The key came from their own device.'**
  String verifiedHowTap(DateTime date);

  /// No description provided for @verifiedHowQr.
  ///
  /// In en, this message translates to:
  /// **'You scanned the code on their screen on {date}. The key came from their own device.'**
  String verifiedHowQr(DateTime date);

  /// No description provided for @verifiedHowWords.
  ///
  /// In en, this message translates to:
  /// **'You compared the four words on {date}.'**
  String verifiedHowWords(DateTime date);

  /// No description provided for @verifiedHowCode.
  ///
  /// In en, this message translates to:
  /// **'You swapped the long code on {date}.'**
  String verifiedHowCode(DateTime date);

  /// No description provided for @verifiedHowUnknown.
  ///
  /// In en, this message translates to:
  /// **'Verified before DNet noted how.'**
  String get verifiedHowUnknown;

  /// No description provided for @verifyAutoNotYet.
  ///
  /// In en, this message translates to:
  /// **'Not verified yet'**
  String get verifyAutoNotYet;

  /// No description provided for @verifyAutoBody.
  ///
  /// In en, this message translates to:
  /// **'Scan the code on their screen, or tap the two together if both have NFC. DNet checks the key came from their own device and verifies them by itself.'**
  String get verifyAutoBody;

  /// No description provided for @verifyAutoOff.
  ///
  /// In en, this message translates to:
  /// **'Verifying automatically is off in Privacy and security. Scanning their code here still verifies them.'**
  String get verifyAutoOff;

  /// No description provided for @verifyAutoNoWays.
  ///
  /// In en, this message translates to:
  /// **'{device, select, pc{This PC} other{This phone}} cannot scan a code or tap phones. Check by hand below.'**
  String verifyAutoNoWays(String device);

  /// No description provided for @verifyTogetherTitle.
  ///
  /// In en, this message translates to:
  /// **'Together: compare four words'**
  String get verifyTogetherTitle;

  /// No description provided for @verifyTogetherBody.
  ///
  /// In en, this message translates to:
  /// **'Read them to each other, in person or on a call. Both {device, select, pc{devices} other{phones}} must show the same four.'**
  String verifyTogetherBody(String device);

  /// No description provided for @verifyKeyChangeNote.
  ///
  /// In en, this message translates to:
  /// **'If {name}\'s key ever changes, they go back to not verified and you are told.'**
  String verifyKeyChangeNote(String name);

  /// No description provided for @verifyDoneAction.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get verifyDoneAction;

  /// No description provided for @verifiedToast.
  ///
  /// In en, this message translates to:
  /// **'{name} is verified.'**
  String verifiedToast(String name);

  /// No description provided for @tapVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified. The key came from their own device.'**
  String get tapVerified;

  /// No description provided for @personCheckOtherWay.
  ///
  /// In en, this message translates to:
  /// **'Cannot see the pictures? Type instead'**
  String get personCheckOtherWay;

  /// No description provided for @personCheckPicturesInstead.
  ///
  /// In en, this message translates to:
  /// **'Use the pictures instead'**
  String get personCheckPicturesInstead;

  /// No description provided for @personCheckTypePrompt.
  ///
  /// In en, this message translates to:
  /// **'Quick check that you are a person: type these numbers as digits. {numbers}'**
  String personCheckTypePrompt(String numbers);

  /// No description provided for @personCheckTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'The numbers, as digits'**
  String get personCheckTypeLabel;

  /// No description provided for @personCheckTypeCheck.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get personCheckTypeCheck;

  /// No description provided for @personCheckWait.
  ///
  /// In en, this message translates to:
  /// **'Too many wrong answers. Try again in a few seconds.'**
  String get personCheckWait;

  /// No description provided for @numberWords.
  ///
  /// In en, this message translates to:
  /// **'zero,one,two,three,four,five,six,seven,eight,nine'**
  String get numberWords;

  /// No description provided for @makingKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Making your key'**
  String get makingKeyTitle;

  /// No description provided for @makingKeyBody.
  ///
  /// In en, this message translates to:
  /// **'A few seconds of work on this {device, select, pc{PC} other{phone}}. It shows other devices that a person made this identity, not a program making thousands.'**
  String makingKeyBody(String device);

  /// No description provided for @makingKeyProgress.
  ///
  /// In en, this message translates to:
  /// **'{percent}% done'**
  String makingKeyProgress(int percent);

  /// No description provided for @welcomePoint4Title.
  ///
  /// In en, this message translates to:
  /// **'Groups without a server'**
  String get welcomePoint4Title;

  /// No description provided for @welcomePoint4Body.
  ///
  /// In en, this message translates to:
  /// **'Spaces with channels and voice rooms live on members\' devices.'**
  String get welcomePoint4Body;

  /// No description provided for @welcomeCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your identity'**
  String get welcomeCreateTitle;

  /// No description provided for @welcomeCreateBody.
  ///
  /// In en, this message translates to:
  /// **'All it takes is a name. No number, no email, no account.'**
  String get welcomeCreateBody;

  /// No description provided for @welcomeOpenSource.
  ///
  /// In en, this message translates to:
  /// **'Open source · MIT License · Version {version}'**
  String welcomeOpenSource(String version);

  /// No description provided for @termsOfUse.
  ///
  /// In en, this message translates to:
  /// **'Terms of Use'**
  String get termsOfUse;

  /// No description provided for @termsDocTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms of Use and Disclaimer'**
  String get termsDocTitle;

  /// No description provided for @termsDocVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version} · last changed {date}'**
  String termsDocVersion(int version, DateTime date);

  /// No description provided for @termsGateIntro.
  ///
  /// In en, this message translates to:
  /// **'Before you start, please read the terms of use to the end and accept them. DNet opens only after you do.'**
  String get termsGateIntro;

  /// No description provided for @termsGateChanged.
  ///
  /// In en, this message translates to:
  /// **'The terms have changed since you last accepted them. Please read and accept the new version to keep using DNet.'**
  String get termsGateChanged;

  /// No description provided for @termsInShort.
  ///
  /// In en, this message translates to:
  /// **'In short'**
  String get termsInShort;

  /// No description provided for @termsShortAsIs.
  ///
  /// In en, this message translates to:
  /// **'DNet is given as it is, with no warranty. You use it at your own risk.'**
  String get termsShortAsIs;

  /// No description provided for @termsShortLawful.
  ///
  /// In en, this message translates to:
  /// **'You alone are responsible for using it lawfully, including radio bands, power and licences.'**
  String get termsShortLawful;

  /// No description provided for @termsShortEmergency.
  ///
  /// In en, this message translates to:
  /// **'It is not for emergencies. Messages may not arrive, and may not stay private.'**
  String get termsShortEmergency;

  /// No description provided for @termsShortEarly.
  ///
  /// In en, this message translates to:
  /// **'It is early software, not independently audited and not yet verified on devices.'**
  String get termsShortEarly;

  /// No description provided for @termsShortNoServers.
  ///
  /// In en, this message translates to:
  /// **'The authors run no servers and collect nothing. Your data stays on devices.'**
  String get termsShortNoServers;

  /// No description provided for @termsInShortNote.
  ///
  /// In en, this message translates to:
  /// **'This summary only helps you read. The full terms below are what you agree to.'**
  String get termsInShortNote;

  /// No description provided for @termsContents.
  ///
  /// In en, this message translates to:
  /// **'Contents'**
  String get termsContents;

  /// No description provided for @termsReadToEnd.
  ///
  /// In en, this message translates to:
  /// **'Read to the end to accept'**
  String get termsReadToEnd;

  /// No description provided for @termsReachedEnd.
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached the end'**
  String get termsReachedEnd;

  /// No description provided for @termsReadProgress.
  ///
  /// In en, this message translates to:
  /// **'{percent}% read'**
  String termsReadProgress(int percent);

  /// No description provided for @termsAgreeBox.
  ///
  /// In en, this message translates to:
  /// **'I have read and agree to the Terms of Use and Disclaimer'**
  String get termsAgreeBox;

  /// No description provided for @termsAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get termsAccept;

  /// No description provided for @termsDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get termsDecline;

  /// No description provided for @termsDeclinedTitle.
  ///
  /// In en, this message translates to:
  /// **'DNet stays closed'**
  String get termsDeclinedTitle;

  /// No description provided for @termsDeclinedBody.
  ///
  /// In en, this message translates to:
  /// **'You declined the Terms of Use, so DNet won\'t start. Nothing has been opened, sent or changed. You can read the terms again, or quit.'**
  String get termsDeclinedBody;

  /// No description provided for @termsReadAgain.
  ///
  /// In en, this message translates to:
  /// **'Read the terms again'**
  String get termsReadAgain;

  /// No description provided for @termsQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit DNet'**
  String get termsQuit;

  /// No description provided for @termsAcceptedOn.
  ///
  /// In en, this message translates to:
  /// **'You accepted version {version} on {date}.'**
  String termsAcceptedOn(int version, DateTime date);

  /// No description provided for @termsDocIntro.
  ///
  /// In en, this message translates to:
  /// **'These Terms of Use and Disclaimer (\"terms\") are an agreement between you and the authors and contributors of DNet (together, \"the authors\"). They apply to your use of the DNet app and of everything it does on your device (\"DNet\"). Please read all of them. They limit the authors\' responsibility to you, and they make you responsible for how you use DNet.\n\nYou must accept these terms before DNet can be used. If you do not agree with them, choose Decline and do not use DNet.'**
  String get termsDocIntro;

  /// No description provided for @termsDoc1Title.
  ///
  /// In en, this message translates to:
  /// **'What DNet is'**
  String get termsDoc1Title;

  /// No description provided for @termsDoc1Body.
  ///
  /// In en, this message translates to:
  /// **'DNet is free, open-source software for sending messages, calls and files directly between devices without the internet. Devices reach each other over Bluetooth, over Wi-Fi on the same local network, over Wi-Fi Direct and, if you connect one, through an external LoRa radio. When the person you want is out of range, encrypted messages may be passed along by other DNet devices.\n\nThe authors do not run any server, network or messaging service for DNet. They do not carry, store, see, check or control any message, call, file, name, location or other content sent with it, and they cannot do so. DNet is a tool that runs on your device and on the devices of the people you talk to.'**
  String get termsDoc1Body;

  /// No description provided for @termsDoc2Title.
  ///
  /// In en, this message translates to:
  /// **'Accepting these terms'**
  String get termsDoc2Title;

  /// No description provided for @termsDoc2Body.
  ///
  /// In en, this message translates to:
  /// **'By ticking \"I have read and agree\" and choosing Accept, you confirm that you have read and understood these terms and agree to be bound by them. DNet keeps a record on your device of which version of the terms you accepted, and when. If you do not accept them, DNet will not open.\n\nIf you use DNet for or on behalf of an organisation, you confirm that you have the authority to accept these terms for it, and \"you\" then includes that organisation.'**
  String get termsDoc2Body;

  /// No description provided for @termsDoc3Title.
  ///
  /// In en, this message translates to:
  /// **'Who may use DNet'**
  String get termsDoc3Title;

  /// No description provided for @termsDoc3Body.
  ///
  /// In en, this message translates to:
  /// **'You may use DNet only if you are old enough, under the law that applies to you, to use communication services like it and to accept these terms yourself. If you are below that age, you may use DNet only with the permission and supervision of a parent or legal guardian, who accepts these terms for you and is responsible for your use.\n\nYou may not use DNet where the law that applies to you forbids it, or if you have been barred from using software like it.'**
  String get termsDoc3Body;

  /// No description provided for @termsDoc4Title.
  ///
  /// In en, this message translates to:
  /// **'You are responsible for lawful use'**
  String get termsDoc4Title;

  /// No description provided for @termsDoc4Body.
  ///
  /// In en, this message translates to:
  /// **'You alone are responsible for how you use DNet, and for making sure that your use is lawful where you are and wherever your messages or radio signals reach. Laws differ from country to country and change over time. Among other things, you are responsible for following the laws and rules on:\n• Encryption: some countries restrict the use, import or export of encryption software.\n• Radio: if you connect a LoRa or other radio, you must choose only a frequency band that is allowed where you are, and keep to its rules on transmit power, antennas, duty cycle or airtime, channel use, and any licence, registration or certification. DNet\'s region choices and airtime limits are only an aid. They are not legal advice and may be wrong, incomplete or out of date.\n• Bluetooth, Wi-Fi and Wi-Fi Direct: where and when wireless devices may be used, including on aircraft, in hospitals and at secure or restricted sites.\n• Recording and capture: recording, saving or sharing calls, voices, screens, screenshots, photos or the location of other people may need their consent and may be restricted.\n• Content: everything you send, share or publish with DNet, including in spaces and public channels, and any rights that others have in it.\n• Privacy and data protection: any duties you have when you collect, keep or share information about other people.\n\nNothing in DNet, its documentation or these terms is legal advice. If you are unsure whether something is allowed where you are, find out before you do it.'**
  String get termsDoc4Body;

  /// No description provided for @termsDoc5Title.
  ///
  /// In en, this message translates to:
  /// **'Things you must not do'**
  String get termsDoc5Title;

  /// No description provided for @termsDoc5Body.
  ///
  /// In en, this message translates to:
  /// **'You agree not to use DNet, or help or allow anyone else to use it, to:\n• break any law or regulation, or encourage or help anyone else to break one;\n• create, send, keep or share illegal content, including content that sexually exploits or endangers children, incites violence, hatred or terrorism, or is fraudulent;\n• harass, threaten, stalk, bully, intimidate, impersonate or deceive anyone, or send unwanted messages in bulk;\n• infringe anyone\'s copyright, trademark, privacy, publicity or other rights, or share another person\'s private information or images without the right to;\n• track, watch or locate a person without their knowledge and consent;\n• interfere with, disrupt or overload any network, device, service or radio frequency, including by transmitting where, when, at a power or for longer than is allowed, or by deliberately causing interference to other radio users;\n• get into any device, account or data without permission, or spread malware;\n• make identities in bulk, or get around DNet\'s protections, such as the identity stamp, chat requests, blocking or the app lock, to reach or harm other people;\n• plan or carry out anything that could cause death, injury, or damage to property or the environment.\n\nThe authors cannot see how DNet is used and do not monitor it, but none of these uses is allowed.'**
  String get termsDoc5Body;

  /// No description provided for @termsDoc6Title.
  ///
  /// In en, this message translates to:
  /// **'Not for emergencies or critical use'**
  String get termsDoc6Title;

  /// No description provided for @termsDoc6Body.
  ///
  /// In en, this message translates to:
  /// **'DNet is not an emergency service and cannot contact emergency services. Do not rely on it for emergency, life-safety or other critical communication: not as your only way to call for help, not to coordinate rescue or medical care, and not for anything where a failure, delay or loss of a message could lead to death, injury, or serious damage to property or the environment. This includes medical, aviation, maritime, vehicle, industrial-control and disaster-response use. Always keep another way to reach help.'**
  String get termsDoc6Body;

  /// No description provided for @termsDoc7Title.
  ///
  /// In en, this message translates to:
  /// **'No promise that messages arrive or stay private'**
  String get termsDoc7Title;

  /// No description provided for @termsDoc7Body.
  ///
  /// In en, this message translates to:
  /// **'DNet works only when other devices are within range and the links between them happen to work. Messages, calls and files may be delayed, arrive out of order, arrive more than once, arrive incomplete or not arrive at all, and DNet may not be able to tell you which. A message shown as sent, relayed or delivered may still not have been read.\n\nDNet is designed to protect what you send with end-to-end encryption, but no software is perfect. The authors do not promise that DNet is secure, that it will keep your messages, calls, files, identity or location private, or that it will hide the fact that you use it. People near you may be able to tell that your device is sending radio signals, and anyone listening on a LoRa band can see that two DNet radios are talking, when, and how much. Known limits are listed in SECURITY.md in the source code.\n\nOnce you send something, the people who receive it can keep, copy, record, photograph or pass it on, and neither you nor the authors can take it back. Disappearing messages, view-once media and deleting a message depend on the other person\'s device, and cannot stop them from keeping a copy.'**
  String get termsDoc7Body;

  /// No description provided for @termsDoc8Title.
  ///
  /// In en, this message translates to:
  /// **'Early software, not independently audited'**
  String get termsDoc8Title;

  /// No description provided for @termsDoc8Body.
  ///
  /// In en, this message translates to:
  /// **'DNet is early-stage software. It has had an internal security review but no independent security audit, and its Bluetooth, Wi-Fi Direct, mesh relay, NFC, screen sharing and LoRa radio features have not yet been verified between real devices. It may have bugs and security flaws. It may lose or damage data, use a lot of battery or other resources, behave differently on different devices, and change or stop working without notice. Do not rely on it to protect anyone, and keep your own copies of anything important.'**
  String get termsDoc8Body;

  /// No description provided for @termsDoc9Title.
  ///
  /// In en, this message translates to:
  /// **'Your data stays with you'**
  String get termsDoc9Title;

  /// No description provided for @termsDoc9Body.
  ///
  /// In en, this message translates to:
  /// **'The authors run no servers and collect no data. DNet has no accounts, analytics, advertising or tracking, and it sends nothing to the authors. Your identity, messages, contacts and settings are kept encrypted on your device, together with the record of the terms you accepted.\n\nUsing DNet means your device exchanges information with other devices, directly or through other DNet devices: for example the name you choose, your public key, and, when you choose to send them, messages, files, photos, your status or your location. Your device may also pass on other people\'s sealed messages, which it cannot read; you can turn this off in Privacy. What other people receive is on their devices, outside your control and outside the authors\' control.\n\nYou are responsible for your device and its security, for keeping DNet and your system up to date, for your app lock passcode, and for keeping copies of anything you need. If you lose your device, forget your passcode or wipe DNet, your data may be gone for good: the authors hold no copy and cannot recover it.'**
  String get termsDoc9Body;

  /// No description provided for @termsDoc10Title.
  ///
  /// In en, this message translates to:
  /// **'Other people, devices and links'**
  String get termsDoc10Title;

  /// No description provided for @termsDoc10Body.
  ///
  /// In en, this message translates to:
  /// **'DNet puts you in touch with people the authors do not know. The authors are not responsible for other users, their content or their conduct, or for what they do with what you send them. Content you receive may be false, offensive, harmful or illegal, and the authors do not review it. Think before you accept a chat request or verify someone, and use Decline and Block when you need to.\n\nRadios, boards, firmware and other hardware or software made by others, such as Meshtastic devices, are not made or supported by the authors. Their makers\' terms, and the law where you use them, apply to them.\n\nDNet never opens a link by itself. If you choose to open a link, it opens in your own browser, outside DNet, and the authors are not responsible for the site or for what happens there.'**
  String get termsDoc10Body;

  /// No description provided for @termsDoc11Title.
  ///
  /// In en, this message translates to:
  /// **'No warranty'**
  String get termsDoc11Title;

  /// No description provided for @termsDoc11Body.
  ///
  /// In en, this message translates to:
  /// **'DNET IS PROVIDED \"AS IS\" AND \"AS AVAILABLE\", WITH ALL FAULTS AND WITHOUT WARRANTY OF ANY KIND. To the fullest extent the law allows, the authors disclaim all warranties, conditions and terms, whether express, implied or statutory, including any of merchantability, satisfactory quality, fitness for a particular purpose, title, non-infringement, accuracy, security, availability and quiet enjoyment, and any arising from a course of dealing or usage of trade.\n\nThe authors do not warrant that DNet will meet your needs, that it will work without interruption or error, that it is secure or free of harmful components, that defects will be fixed, or that it will work with any particular device, radio or operating system. No advice or information, spoken or written, that you get from the authors or from anywhere else creates any warranty. You use DNet entirely at your own risk.'**
  String get termsDoc11Body;

  /// No description provided for @termsDoc12Title.
  ///
  /// In en, this message translates to:
  /// **'Limitation of liability'**
  String get termsDoc12Title;

  /// No description provided for @termsDoc12Body.
  ///
  /// In en, this message translates to:
  /// **'TO THE FULLEST EXTENT THE LAW ALLOWS, IN NO EVENT WILL THE AUTHORS, CONTRIBUTORS OR COPYRIGHT HOLDERS BE LIABLE to you or to anyone else for any direct, indirect, incidental, special, consequential, exemplary or punitive damages, or for any loss of data, messages, privacy, profits, revenue, goodwill, business or opportunity, any damage to devices or equipment, any personal injury or death, or the cost of any substitute service, arising out of or in connection with DNet or these terms, however caused and on any theory of liability, whether in contract, tort (including negligence), strict liability or otherwise, even if they were told that such damage was possible. This includes anything done, sent or not done by other people using DNet.\n\nWhere the law does not allow liability to be excluded completely, the authors\' total liability is limited to the smallest amount the law allows. DNet is given away free of charge, and you agree that these limits are a fair basis for that.\n\nSome places do not allow certain warranties to be excluded or certain liability to be limited, such as liability for death or personal injury caused by negligence, or for fraud. There, the exclusions and limits in these terms apply only as far as the law allows, and nothing in these terms takes away any right you have that cannot be changed by agreement.'**
  String get termsDoc12Body;

  /// No description provided for @termsDoc13Title.
  ///
  /// In en, this message translates to:
  /// **'Indemnity'**
  String get termsDoc13Title;

  /// No description provided for @termsDoc13Body.
  ///
  /// In en, this message translates to:
  /// **'To the fullest extent the law allows, you agree to defend, indemnify and hold harmless the authors and contributors against any claim, demand, action, loss, liability, damage, fine, penalty, cost or expense, including reasonable legal fees, that arises from or relates to: your use of DNet; anything you send, share or publish with it; your breach of these terms; your breach of any law or regulation, including rules on radio and encryption; or your infringement of anyone else\'s rights.'**
  String get termsDoc13Body;

  /// No description provided for @termsDoc14Title.
  ///
  /// In en, this message translates to:
  /// **'The open-source licence'**
  String get termsDoc14Title;

  /// No description provided for @termsDoc14Body.
  ///
  /// In en, this message translates to:
  /// **'DNet\'s source code is published under the MIT License, which you can read in the app under About and in the LICENSE file of the source code. These terms cover your use of DNet. They do not take away any right that the licence gives you to use, copy, change or share the source code, and the licence\'s own disclaimer of warranty and limitation of liability apply as well as these terms.\n\nIf you change DNet or share a copy of it, changed or not, you are responsible for that copy, and you must not suggest that the authors made, checked or approve of your version. Software and fonts that DNet includes from others come under their own licences, listed in About under Open-source licences.'**
  String get termsDoc14Body;

  /// No description provided for @termsDoc15Title.
  ///
  /// In en, this message translates to:
  /// **'Changes to DNet and to these terms'**
  String get termsDoc15Title;

  /// No description provided for @termsDoc15Body.
  ///
  /// In en, this message translates to:
  /// **'The authors may change, pause or stop work on DNet at any time without notice, and they have no obligation to provide updates, fixes or support.\n\nThe authors may change these terms. When a later version of DNet comes with changed terms, it asks you to read and accept them before you can go on using it. If you do not accept the changed terms, stop using DNet. The version of the terms you accepted, and when, is kept on your device and shown in About.'**
  String get termsDoc15Body;

  /// No description provided for @termsDoc16Title.
  ///
  /// In en, this message translates to:
  /// **'Stopping use'**
  String get termsDoc16Title;

  /// No description provided for @termsDoc16Body.
  ///
  /// In en, this message translates to:
  /// **'You can stop using DNet at any time: wipe its data from Privacy and remove the app. If you break these terms, you are no longer allowed to use DNet. The sections on lawful use, things you must not do, no warranty, limitation of liability and indemnity, and these general terms, keep applying to anything that happened before you stopped.'**
  String get termsDoc16Body;

  /// No description provided for @termsDoc17Title.
  ///
  /// In en, this message translates to:
  /// **'General terms'**
  String get termsDoc17Title;

  /// No description provided for @termsDoc17Body.
  ///
  /// In en, this message translates to:
  /// **'If any part of these terms is found invalid or unenforceable, it is limited or changed only as far as needed to make it enforceable, and the rest of the terms remain in full force.\n\nIf the authors do not enforce any part of these terms, that does not mean they give up the right to do so later.\n\nThese terms, together with the open-source licence, are the whole agreement between you and the authors about DNet, and they replace anything said before. Every author and contributor may rely on them. You may not transfer your rights or duties under them to anyone else.\n\nHeadings are there to help you read. They do not change what the terms mean.\n\nQuestions about DNet or these terms can be raised on the project\'s GitHub page, linked from About. Security problems should be reported privately, as SECURITY.md in the source code describes.'**
  String get termsDoc17Body;

  /// No description provided for @termsDocClosing.
  ///
  /// In en, this message translates to:
  /// **'By ticking \"I have read and agree\" and choosing Accept, you confirm that you have read these terms to the end, that you understand them, that you are allowed to accept them, and that you agree to them.'**
  String get termsDocClosing;

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'Your offline connector'**
  String get aboutTagline;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersion(String version);

  /// No description provided for @aboutVersionCopied.
  ///
  /// In en, this message translates to:
  /// **'Version copied'**
  String get aboutVersionCopied;

  /// No description provided for @aboutCopyVersion.
  ///
  /// In en, this message translates to:
  /// **'Copy the version, for a bug report'**
  String get aboutCopyVersion;

  /// No description provided for @aboutPurposeTitle.
  ///
  /// In en, this message translates to:
  /// **'What it\'s for'**
  String get aboutPurposeTitle;

  /// No description provided for @aboutPurposeBody.
  ///
  /// In en, this message translates to:
  /// **'DNet lets you chat, call and share files with the people around you when there is no internet, no signal and no server, or when you would rather not use them. There is no account, no number and no email: your identity is a key made on your device, and all it needs is a name.'**
  String get aboutPurposeBody;

  /// No description provided for @aboutAimTitle.
  ///
  /// In en, this message translates to:
  /// **'What it aims for'**
  String get aboutAimTitle;

  /// No description provided for @aboutAimBody.
  ///
  /// In en, this message translates to:
  /// **'To keep people in touch when networks fail, are switched off or can\'t be trusted: at events, while travelling, in remote places and during outages. Private by default, owned by nobody, and open for anyone to check.'**
  String get aboutAimBody;

  /// No description provided for @aboutHowTitle.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get aboutHowTitle;

  /// No description provided for @aboutHowNearbyTitle.
  ///
  /// In en, this message translates to:
  /// **'Finds people nearby'**
  String get aboutHowNearbyTitle;

  /// No description provided for @aboutHowNearbyBody.
  ///
  /// In en, this message translates to:
  /// **'Devices find each other over Bluetooth and Wi-Fi, with no internet.'**
  String get aboutHowNearbyBody;

  /// No description provided for @aboutHowMeshTitle.
  ///
  /// In en, this message translates to:
  /// **'Passes messages along'**
  String get aboutHowMeshTitle;

  /// No description provided for @aboutHowMeshBody.
  ///
  /// In en, this message translates to:
  /// **'Out of range? Sealed messages hop through other DNet devices, which can\'t read them.'**
  String get aboutHowMeshBody;

  /// No description provided for @aboutHowSealedTitle.
  ///
  /// In en, this message translates to:
  /// **'Encrypted end to end'**
  String get aboutHowSealedTitle;

  /// No description provided for @aboutHowSealedBody.
  ///
  /// In en, this message translates to:
  /// **'Each message is sealed on your device for the one person it\'s for.'**
  String get aboutHowSealedBody;

  /// No description provided for @aboutHowSpacesTitle.
  ///
  /// In en, this message translates to:
  /// **'Spaces for groups'**
  String get aboutHowSpacesTitle;

  /// No description provided for @aboutHowSpacesBody.
  ///
  /// In en, this message translates to:
  /// **'Channels and voice rooms, kept on members\' devices. No server.'**
  String get aboutHowSpacesBody;

  /// No description provided for @aboutHowRadioTitle.
  ///
  /// In en, this message translates to:
  /// **'Long range by radio'**
  String get aboutHowRadioTitle;

  /// No description provided for @aboutHowRadioBody.
  ///
  /// In en, this message translates to:
  /// **'Plug in a LoRa radio to send text for kilometres, on the band that is legal where you are.'**
  String get aboutHowRadioBody;

  /// No description provided for @aboutStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Where it stands'**
  String get aboutStatusTitle;

  /// No description provided for @aboutStatusBody.
  ///
  /// In en, this message translates to:
  /// **'This is an early build. It has had an internal security review but has not had an independent security review, and its Bluetooth, Wi-Fi Direct, mesh and LoRa links have not yet been verified on devices. Don\'t rely on it to protect anyone, or in an emergency.'**
  String get aboutStatusBody;

  /// No description provided for @aboutLinksTitle.
  ///
  /// In en, this message translates to:
  /// **'Source code and help'**
  String get aboutLinksTitle;

  /// No description provided for @aboutGithub.
  ///
  /// In en, this message translates to:
  /// **'Source code on GitHub'**
  String get aboutGithub;

  /// No description provided for @aboutGithubDetail.
  ///
  /// In en, this message translates to:
  /// **'See how DNet works, build it yourself, help out'**
  String get aboutGithubDetail;

  /// No description provided for @aboutIssues.
  ///
  /// In en, this message translates to:
  /// **'Report a bug or ask for a feature'**
  String get aboutIssues;

  /// No description provided for @aboutIssuesDetail.
  ///
  /// In en, this message translates to:
  /// **'Issues on GitHub. Report security problems privately, as SECURITY.md says.'**
  String get aboutIssuesDetail;

  /// No description provided for @aboutLegalTitle.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get aboutLegalTitle;

  /// No description provided for @aboutTermsDetail.
  ///
  /// In en, this message translates to:
  /// **'What you agreed to before using DNet'**
  String get aboutTermsDetail;

  /// No description provided for @aboutLicence.
  ///
  /// In en, this message translates to:
  /// **'MIT License'**
  String get aboutLicence;

  /// No description provided for @aboutLicenceDetail.
  ///
  /// In en, this message translates to:
  /// **'Free to use, change and share. No warranty.'**
  String get aboutLicenceDetail;

  /// No description provided for @aboutOpenSource.
  ///
  /// In en, this message translates to:
  /// **'Open-source licences'**
  String get aboutOpenSource;

  /// No description provided for @aboutOpenSourceDetail.
  ///
  /// In en, this message translates to:
  /// **'The software and fonts DNet is built with'**
  String get aboutOpenSourceDetail;

  /// No description provided for @aboutFooter.
  ///
  /// In en, this message translates to:
  /// **'Made in the open by the DNet authors. No servers, no tracking, no ads.'**
  String get aboutFooter;

  /// No description provided for @privacyWhoCanReach.
  ///
  /// In en, this message translates to:
  /// **'Who can reach me'**
  String get privacyWhoCanReach;

  /// No description provided for @privacyWhatOthersSee.
  ///
  /// In en, this message translates to:
  /// **'What others see. Off keeps you private.'**
  String get privacyWhatOthersSee;

  /// No description provided for @privacySafety.
  ///
  /// In en, this message translates to:
  /// **'Safety'**
  String get privacySafety;

  /// No description provided for @requestsFromTitle.
  ///
  /// In en, this message translates to:
  /// **'Who can send me chat requests'**
  String get requestsFromTitle;

  /// No description provided for @requestsFromEveryone.
  ///
  /// In en, this message translates to:
  /// **'Everyone nearby'**
  String get requestsFromEveryone;

  /// No description provided for @requestsFromSpaces.
  ///
  /// In en, this message translates to:
  /// **'People in my spaces'**
  String get requestsFromSpaces;

  /// No description provided for @requestsFromNobody.
  ///
  /// In en, this message translates to:
  /// **'Nobody'**
  String get requestsFromNobody;

  /// No description provided for @requestsFromNote.
  ///
  /// In en, this message translates to:
  /// **'Someone you send your own link to can always ask.'**
  String get requestsFromNote;

  /// No description provided for @autoVerifySwitch.
  ///
  /// In en, this message translates to:
  /// **'Verify people automatically'**
  String get autoVerifySwitch;

  /// No description provided for @autoVerifyDetail.
  ///
  /// In en, this message translates to:
  /// **'When you scan the code on their screen, or tap with NFC'**
  String get autoVerifyDetail;

  /// No description provided for @relaySwitch.
  ///
  /// In en, this message translates to:
  /// **'Pass on messages for others'**
  String get relaySwitch;

  /// No description provided for @relayDetail.
  ///
  /// In en, this message translates to:
  /// **'Sealed, so this device cannot read them'**
  String get relayDetail;

  /// No description provided for @verifiedFilesOnlySwitch.
  ///
  /// In en, this message translates to:
  /// **'Ask before saving files from people not verified'**
  String get verifiedFilesOnlySwitch;

  /// No description provided for @lockAfterTitle.
  ///
  /// In en, this message translates to:
  /// **'Lock after leaving the app'**
  String get lockAfterTitle;

  /// No description provided for @lockAfterChoice.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =0{At once} other{{minutes} min}}'**
  String lockAfterChoice(int minutes);

  /// No description provided for @lockAfterHour.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get lockAfterHour;

  /// No description provided for @emojiSearch.
  ///
  /// In en, this message translates to:
  /// **'Search emoji'**
  String get emojiSearch;

  /// No description provided for @emojiNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No emoji match that.'**
  String get emojiNoMatch;

  /// No description provided for @skinTone.
  ///
  /// In en, this message translates to:
  /// **'Skin tone'**
  String get skinTone;

  /// No description provided for @skinToneName.
  ///
  /// In en, this message translates to:
  /// **'{tone, select, 0{No skin tone} 1{Light} 2{Medium light} 3{Medium} 4{Medium dark} 5{Dark} other{Skin tone}}'**
  String skinToneName(String tone);

  /// No description provided for @chooseSkinTone.
  ///
  /// In en, this message translates to:
  /// **'Choose a skin tone for {emoji}'**
  String chooseSkinTone(String emoji);

  /// No description provided for @emojiInTone.
  ///
  /// In en, this message translates to:
  /// **'{emoji}, {tone}'**
  String emojiInTone(String emoji, String tone);

  /// No description provided for @favouriteStickers.
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get favouriteStickers;

  /// No description provided for @noFavouriteStickers.
  ///
  /// In en, this message translates to:
  /// **'Press and hold a sticker to add it here.'**
  String get noFavouriteStickers;

  /// No description provided for @newSticker.
  ///
  /// In en, this message translates to:
  /// **'New sticker'**
  String get newSticker;

  /// No description provided for @stickerPacksTitle.
  ///
  /// In en, this message translates to:
  /// **'Your sticker packs'**
  String get stickerPacksTitle;

  /// No description provided for @arrangeStickers.
  ///
  /// In en, this message translates to:
  /// **'Arrange stickers'**
  String get arrangeStickers;

  /// No description provided for @addToFavourites.
  ///
  /// In en, this message translates to:
  /// **'Add to favourites'**
  String get addToFavourites;

  /// No description provided for @removeFromFavourites.
  ///
  /// In en, this message translates to:
  /// **'Remove from favourites'**
  String get removeFromFavourites;

  /// No description provided for @moveToPack.
  ///
  /// In en, this message translates to:
  /// **'Move to another pack'**
  String get moveToPack;

  /// No description provided for @saveToPack.
  ///
  /// In en, this message translates to:
  /// **'Save to a pack'**
  String get saveToPack;

  /// No description provided for @chooseStickerPack.
  ///
  /// In en, this message translates to:
  /// **'Which pack?'**
  String get chooseStickerPack;

  /// No description provided for @newStickerPack.
  ///
  /// In en, this message translates to:
  /// **'New pack'**
  String get newStickerPack;

  /// No description provided for @stickerPackName.
  ///
  /// In en, this message translates to:
  /// **'Pack name'**
  String get stickerPackName;

  /// No description provided for @renameStickerPack.
  ///
  /// In en, this message translates to:
  /// **'Rename pack'**
  String get renameStickerPack;

  /// No description provided for @deleteStickerPack.
  ///
  /// In en, this message translates to:
  /// **'Delete pack'**
  String get deleteStickerPack;

  /// No description provided for @deleteStickerPackBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{The pack is empty.} =1{Its 1 sticker is deleted from this device.} other{Its {count} stickers are deleted from this device.}}'**
  String deleteStickerPackBody(int count);

  /// No description provided for @stickerPackDeleted.
  ///
  /// In en, this message translates to:
  /// **'Pack deleted.'**
  String get stickerPackDeleted;

  /// No description provided for @stickerPackFull.
  ///
  /// In en, this message translates to:
  /// **'No more packs can be made.'**
  String get stickerPackFull;

  /// No description provided for @stickerPackCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No stickers yet} =1{1 sticker} other{{count} stickers}}'**
  String stickerPackCount(int count);

  /// No description provided for @stickerPackEmpty.
  ///
  /// In en, this message translates to:
  /// **'No stickers in this pack yet.'**
  String get stickerPackEmpty;

  /// No description provided for @noStickerPacks.
  ///
  /// In en, this message translates to:
  /// **'Make a sticker from a photo, or save one someone sent you, and it goes in a pack here.'**
  String get noStickerPacks;

  /// No description provided for @moveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get moveDown;

  /// No description provided for @moveEarlier.
  ///
  /// In en, this message translates to:
  /// **'Move earlier'**
  String get moveEarlier;

  /// No description provided for @moveLater.
  ///
  /// In en, this message translates to:
  /// **'Move later'**
  String get moveLater;

  /// No description provided for @stickerMoved.
  ///
  /// In en, this message translates to:
  /// **'Moved.'**
  String get stickerMoved;

  /// No description provided for @stickerFromPhoto.
  ///
  /// In en, this message translates to:
  /// **'Choose a photo'**
  String get stickerFromPhoto;

  /// No description provided for @stickerFromCamera.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get stickerFromCamera;

  /// No description provided for @stickerEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'New sticker'**
  String get stickerEditorTitle;

  /// No description provided for @stickerShape.
  ///
  /// In en, this message translates to:
  /// **'Shape'**
  String get stickerShape;

  /// No description provided for @stickerShapeFree.
  ///
  /// In en, this message translates to:
  /// **'As cut'**
  String get stickerShapeFree;

  /// No description provided for @stickerShapeRounded.
  ///
  /// In en, this message translates to:
  /// **'Rounded'**
  String get stickerShapeRounded;

  /// No description provided for @stickerShapeCircle.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get stickerShapeCircle;

  /// No description provided for @stickerCropHint.
  ///
  /// In en, this message translates to:
  /// **'Drag the frame, or its corners, to choose what goes in the sticker.'**
  String get stickerCropHint;

  /// No description provided for @stickerCutOut.
  ///
  /// In en, this message translates to:
  /// **'Remove the background'**
  String get stickerCutOut;

  /// No description provided for @stickerCutOutDetail.
  ///
  /// In en, this message translates to:
  /// **'Works best on a plain background. Done on this device.'**
  String get stickerCutOutDetail;

  /// No description provided for @stickerCutOutFailed.
  ///
  /// In en, this message translates to:
  /// **'The background could not be told apart here. Try a plainer one.'**
  String get stickerCutOutFailed;

  /// No description provided for @stickerWords.
  ///
  /// In en, this message translates to:
  /// **'Words on the sticker'**
  String get stickerWords;

  /// No description provided for @stickerWordsHint.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get stickerWordsHint;

  /// No description provided for @stickerSaveTo.
  ///
  /// In en, this message translates to:
  /// **'Save to'**
  String get stickerSaveTo;

  /// No description provided for @saveSticker.
  ///
  /// In en, this message translates to:
  /// **'Save sticker'**
  String get saveSticker;

  /// No description provided for @stickerMade.
  ///
  /// In en, this message translates to:
  /// **'Sticker saved.'**
  String get stickerMade;

  /// No description provided for @stickerPhotoUnreadable.
  ///
  /// In en, this message translates to:
  /// **'This photo can\'t be opened.'**
  String get stickerPhotoUnreadable;

  /// No description provided for @stickerCropFrame.
  ///
  /// In en, this message translates to:
  /// **'Crop frame'**
  String get stickerCropFrame;

  /// No description provided for @packMenuLabel.
  ///
  /// In en, this message translates to:
  /// **'More for {name}'**
  String packMenuLabel(String name);

  /// No description provided for @screenShare.
  ///
  /// In en, this message translates to:
  /// **'Share screen'**
  String get screenShare;

  /// No description provided for @screenShareStop.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing'**
  String get screenShareStop;

  /// No description provided for @screenShareYouAre.
  ///
  /// In en, this message translates to:
  /// **'You\'re sharing your screen'**
  String get screenShareYouAre;

  /// No description provided for @screenShareYouAreWindow.
  ///
  /// In en, this message translates to:
  /// **'You\'re sharing {name}'**
  String screenShareYouAreWindow(String name);

  /// No description provided for @screenShareStopShort.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get screenShareStopShort;

  /// No description provided for @screenSharePickTitle.
  ///
  /// In en, this message translates to:
  /// **'Share your screen'**
  String get screenSharePickTitle;

  /// No description provided for @screenSharePickNote.
  ///
  /// In en, this message translates to:
  /// **'Only what you pick is shared, and only while you\'re in this call.'**
  String get screenSharePickNote;

  /// No description provided for @screenShareWhole.
  ///
  /// In en, this message translates to:
  /// **'Whole screen'**
  String get screenShareWhole;

  /// No description provided for @screenShareNumber.
  ///
  /// In en, this message translates to:
  /// **'Screen {number}'**
  String screenShareNumber(int number);

  /// No description provided for @screenShareMain.
  ///
  /// In en, this message translates to:
  /// **'Main screen'**
  String get screenShareMain;

  /// No description provided for @screenShareWindows.
  ///
  /// In en, this message translates to:
  /// **'One window'**
  String get screenShareWindows;

  /// No description provided for @screenShareNothing.
  ///
  /// In en, this message translates to:
  /// **'There is nothing to share right now.'**
  String get screenShareNothing;

  /// No description provided for @screenShareNeedsWifi.
  ///
  /// In en, this message translates to:
  /// **'Sharing a screen needs Wi-Fi nearby. Bluetooth is too slow for it.'**
  String get screenShareNeedsWifi;

  /// No description provided for @screenShareNeedsWifiShort.
  ///
  /// In en, this message translates to:
  /// **'Share screen: needs Wi-Fi nearby'**
  String get screenShareNeedsWifiShort;

  /// No description provided for @screenShareFailed.
  ///
  /// In en, this message translates to:
  /// **'Your screen was not shared.'**
  String get screenShareFailed;

  /// No description provided for @screenShareEnded.
  ///
  /// In en, this message translates to:
  /// **'Screen sharing stopped.'**
  String get screenShareEnded;

  /// No description provided for @screenShareTheirs.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s screen'**
  String screenShareTheirs(String name);

  /// No description provided for @screenShareSharing.
  ///
  /// In en, this message translates to:
  /// **'Sharing screen'**
  String get screenShareSharing;

  /// No description provided for @screenShareEnlarge.
  ///
  /// In en, this message translates to:
  /// **'Enlarge'**
  String get screenShareEnlarge;

  /// No description provided for @screenShareShrink.
  ///
  /// In en, this message translates to:
  /// **'Make smaller'**
  String get screenShareShrink;

  /// No description provided for @screenShareWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the screen'**
  String get screenShareWaiting;

  /// No description provided for @screenShareNoticeTitle.
  ///
  /// In en, this message translates to:
  /// **'Sharing your screen'**
  String get screenShareNoticeTitle;

  /// No description provided for @screenShareNoticeText.
  ///
  /// In en, this message translates to:
  /// **'Everyone in the call can see it. Open DNet to stop.'**
  String get screenShareNoticeText;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
