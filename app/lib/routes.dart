import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'screens/about_screen.dart';
import 'screens/channel_screen.dart';
import 'screens/chat_requests_screen.dart';
import 'screens/direct_message_screen.dart';
import 'screens/file_transfer_screen.dart';
import 'screens/find_space_screen.dart';
import 'screens/link_trouble_screen.dart';
import 'data/mesh.dart';
import 'screens/nearby_screen.dart';
import 'screens/network_screen.dart';
import 'screens/new_chat_screen.dart';
import 'screens/photo_screen.dart';
import 'screens/privacy_screen.dart';
import 'screens/public_channel_screen.dart';
import 'screens/radio_screen.dart';
import 'screens/share_sheet.dart';
import 'screens/space_names_screen.dart';
import 'screens/space_settings_screen.dart';
import 'screens/sticker_editor_screen.dart';
import 'screens/sticker_packs_screen.dart';
import 'screens/storage_screen.dart';
import 'screens/terms_screen.dart';
import 'screens/verify_screen.dart';
import 'screens/voice_room_screen.dart';
import 'shell/home_shell.dart';
import 'widgets/feedback.dart';
import 'widgets/tab_bar.dart';

/// Every move between screens, in one place. The numbers are the screen
/// numbers in the design kit.
abstract final class Go {
  static Future<T?> _push<T>(BuildContext context, Widget screen) {
    final route = MaterialPageRoute<T>(builder: (_) => screen);
    final here = Navigator.of(context);
    final detail = DetailPane.navigator;
    // A phone-sized window has one stack of screens.
    if (detail == null || identical(here, detail)) return here.push<T>(route);
    // On a wide window everything opens in the right-hand pane. Opened
    // from the list on the left, it takes the place of what was there.
    // Opened from anywhere else, such as a sheet, it goes on top.
    return ListPane.holds(context)
        ? detail.pushAndRemoveUntil<T>(route, (old) => old.isFirst)
        : detail.push<T>(route);
  }

  /// 03
  static Future<void> chatRequests(BuildContext context) =>
      _push(context, const ChatRequestsScreen());

  /// 04
  static Future<void> newChat(BuildContext context) =>
      _push(context, const NewChatScreen());

  /// 05
  static Future<void> verify(BuildContext context, String personId) =>
      _push(context, VerifyScreen(personId: personId));

  /// 06. [chatId] is a person id or the saved messages id.
  static Future<void> directMessage(BuildContext context, String chatId) =>
      _push(context, DirectMessageScreen(chatId: chatId));

  /// 06, replacing the current screen, so Back returns to the list behind.
  static Future<void> directMessageInstead(
    BuildContext context,
    String chatId,
  ) => Navigator.of(context).pushReplacement<void, void>(
    MaterialPageRoute(builder: (_) => DirectMessageScreen(chatId: chatId)),
  );

  /// 08
  static Future<void> channel(
    BuildContext context,
    String spaceId,
    String channelId,
  ) => _push(context, ChannelScreen(spaceId: spaceId, channelId: channelId));

  /// 09. [chatId] is the direct chat it was opened from, if any: that is
  /// who a file chosen here goes to. [channelId] is the channel it was
  /// opened from, if any: that is where a poll made here goes.
  static Future<void> shareSheet(
    BuildContext context, {
    String? chatId,
    String? channelId,
  }) => showAppSheet<void>(
    context,
    builder: (_) => ShareSheet(chatId: chatId, channelId: channelId),
  );

  /// 10
  static Future<void> fileTransfer(BuildContext context) =>
      _push(context, const FileTransferScreen());

  /// A picture from a chat, opened large.
  static Future<void> photo(
    BuildContext context, {
    required String path,
    required String name,
    Uint8List? once,
  }) => _push(context, PhotoScreen(path: path, name: name, once: once));

  /// 11
  static Future<void> voiceRoom(
    BuildContext context,
    String spaceId,
    String channelId,
  ) => _push(context, VoiceRoomScreen(spaceId: spaceId, channelId: channelId));

  /// 12
  static Future<void> findSpace(BuildContext context) =>
      _push(context, const FindSpaceScreen());

  /// 13
  static Future<void> publicChannel(BuildContext context, String spaceId) =>
      _push(context, PublicChannelScreen(spaceId: spaceId));

  /// Running a space: its name, channels and members.
  static Future<void> spaceSettings(BuildContext context, String spaceId) =>
      _push(context, SpaceSettingsScreen(spaceId: spaceId));

  /// 15
  static Future<void> network(BuildContext context) =>
      _push(context, const NetworkScreen());

  /// Setting up a long-range (LoRa) radio. Opened from Network.
  static Future<void> radio(BuildContext context) =>
      _push(context, const RadioScreen());

  /// 14's map, full size. On a wide window it fills the right-hand pane.
  static Future<void> meshMap(
    BuildContext context, {
    MeshRadio radio = MeshRadio.bluetooth,
    String? picked,
  }) => _push(context, MeshMapScreen(radio: radio, picked: picked));

  /// 16
  static Future<void> linkTrouble(BuildContext context) =>
      _push(context, const LinkTroubleScreen());

  /// 18
  static Future<void> privacy(BuildContext context) =>
      _push(context, const PrivacyScreen());

  /// The name the user goes by in each space.
  static Future<void> spaceNames(BuildContext context) =>
      _push(context, const SpaceNamesScreen());

  /// What the app keeps on this device.
  static Future<void> storage(BuildContext context) =>
      _push(context, const StorageScreen());

  /// About DNet: what it is for, its version, its links and its licences.
  static Future<void> about(BuildContext context) =>
      _push(context, const AboutScreen());

  /// The Terms of Use, read-only.
  static Future<void> terms(BuildContext context) =>
      _push(context, const TermsScreen());

  /// The user's sticker packs, to arrange.
  static Future<void> stickerPacks(BuildContext context) =>
      _push(context, const StickerPacksScreen());

  /// Makes a sticker from the photo at [path].
  static Future<void> stickerEditor(BuildContext context, String path) =>
      _push(context, StickerEditorScreen(path: path));

  /// Back to the tabs, showing [tab].
  static void home(BuildContext context, AppTab tab) {
    TabSelection.show(context, tab);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
