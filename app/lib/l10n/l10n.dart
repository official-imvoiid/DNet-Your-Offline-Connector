import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import 'app_localizations.dart';

export 'app_localizations.dart';

extension L10nContext on BuildContext {
  /// The interface text for the current language. Every string the user
  /// reads comes from here.
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// "pc" or "phone": which word the text should use for this device.
  /// Passed to the strings that name the device, so a PC is never called
  /// a phone.
  String get deviceKind => AppScope.read(this).isPc ? 'pc' : 'phone';
}

/// How long a message has left, written in the largest unit that fits.
/// It is rounded up, so it never says less time than there is, but with
/// a little give, so that a second's difference between two devices'
/// clocks does not turn "1 day" into "2 days".
extension GoneIn on AppLocalizations {
  String goneIn(int seconds) {
    const minute = 60, hour = 60 * minute, day = 24 * hour;
    if (seconds > day - 5 * minute) {
      return goneInDays(((seconds - 5 * minute) / day).ceil().clamp(1, 400));
    }
    if (seconds > hour - minute) {
      return goneInHours(((seconds - minute) / hour).ceil().clamp(1, 24));
    }
    return goneInMinutes((seconds / minute).ceil().clamp(1, 60));
  }
}

/// How a slow-mode wait is written: the five the app offers by name,
/// anything else in seconds.
extension SlowChoice on AppLocalizations {
  String slowChoice(int seconds) => switch (seconds) {
    0 => slowOff,
    10 => slowTen,
    60 => slowMinute,
    300 => slowFive,
    3600 => slowHour,
    _ => slowSeconds(seconds),
  };
}
