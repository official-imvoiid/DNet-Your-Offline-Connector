import '../data/app_state.dart';
import '../routes.dart';
import '../screens/call_screen.dart';

/// Opens what a tapped notification was about: the chat, the chat
/// requests, or the channel the user was mentioned in. A call needs
/// nothing: the call screen shows itself.
void openNotice(String key) {
  final context = appNavigator.currentContext;
  if (context == null) return;
  final state = AppScope.read(context);
  if (key.startsWith('chat:')) {
    final id = key.substring('chat:'.length);
    if (state.findPerson(id) != null) Go.directMessage(context, id);
  } else if (key.startsWith('request:')) {
    Go.chatRequests(context);
  } else if (key.startsWith('mention:')) {
    final channelId = key.substring('mention:'.length);
    for (final space in state.spaces) {
      final found = space.channels.values
          .expand((list) => list)
          .any((channel) => channel.id == channelId);
      if (found) {
        Go.channel(context, space.id, channelId);
        return;
      }
    }
  }
}
