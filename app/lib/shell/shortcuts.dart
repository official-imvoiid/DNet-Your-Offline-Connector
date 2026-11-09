import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../widgets/tab_bar.dart';

/// Ctrl+F: look for something in what is open. A screen with a search of
/// its own, such as a channel, answers it. Anywhere else the chat list's
/// search opens, as for [FindChatIntent].
class SearchIntent extends Intent {
  const SearchIntent();
}

/// Ctrl+K: go to the chat list and type a name to find a chat.
class FindChatIntent extends Intent {
  const FindChatIntent();
}

/// Ctrl+1 to Ctrl+4: one of the four tabs.
class ShowTabIntent extends Intent {
  const ShowTabIntent(this.tab);

  final AppTab tab;
}

/// Ctrl+N: ask someone new for a chat.
class NewChatIntent extends Intent {
  const NewChatIntent();
}

/// The keys the app answers wherever the user is in it. Esc is Flutter's
/// own [DismissIntent]: it closes a sheet or a dialog, and [AppScreen]
/// makes it go back a screen.
const Map<ShortcutActivator, Intent> shellShortcuts = {
  SingleActivator(LogicalKeyboardKey.keyF, control: true): SearchIntent(),
  SingleActivator(LogicalKeyboardKey.keyK, control: true): FindChatIntent(),
  SingleActivator(LogicalKeyboardKey.keyN, control: true): NewChatIntent(),
  SingleActivator(LogicalKeyboardKey.digit1, control: true): ShowTabIntent(
    AppTab.chats,
  ),
  SingleActivator(LogicalKeyboardKey.digit2, control: true): ShowTabIntent(
    AppTab.spaces,
  ),
  SingleActivator(LogicalKeyboardKey.digit3, control: true): ShowTabIntent(
    AppTab.nearby,
  ),
  SingleActivator(LogicalKeyboardKey.digit4, control: true): ShowTabIntent(
    AppTab.you,
  ),
  SingleActivator(LogicalKeyboardKey.numpad1, control: true): ShowTabIntent(
    AppTab.chats,
  ),
  SingleActivator(LogicalKeyboardKey.numpad2, control: true): ShowTabIntent(
    AppTab.spaces,
  ),
  SingleActivator(LogicalKeyboardKey.numpad3, control: true): ShowTabIntent(
    AppTab.nearby,
  ),
  SingleActivator(LogicalKeyboardKey.numpad4, control: true): ShowTabIntent(
    AppTab.you,
  ),
};

/// Asks the chat list to open its search and put the cursor in it. The
/// chat list listens; whoever wants it found calls [request].
abstract final class ChatFinder {
  static final _asked = ValueNotifier<int>(0);

  static Listenable get asked => _asked;

  static void request() => _asked.value++;
}
