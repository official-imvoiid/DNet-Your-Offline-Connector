import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../core/device_platform.dart';

/// The version of the Terms of Use the app shows now. Raise it whenever the
/// terms change in a way people must agree to again: everyone who accepted
/// an older version is asked again before the app opens.
const termsVersion = 1;

/// When the current terms were last changed, as shown above them.
final termsChanged = DateTime(2026, 11, 8);

/// Which version of the terms was accepted on this device, and when.
@immutable
class TermsAcceptance {
  const TermsAcceptance({required this.version, required this.acceptedAt});

  final int version;
  final DateTime acceptedAt;

  /// Whether this acceptance covers the terms the app shows now.
  bool get isCurrent => version >= termsVersion;

  Map<String, Object> toJson() => {
    'version': version,
    'accepted_at': acceptedAt.toUtc().toIso8601String(),
  };

  /// Null for anything that is not a whole, readable record: a damaged
  /// file is treated as no acceptance, so the terms are shown again.
  static TermsAcceptance? fromJson(Object? json) {
    if (json is! Map) return null;
    final version = json['version'];
    final at = DateTime.tryParse('${json['accepted_at']}');
    if (version is! int || at == null) return null;
    return TermsAcceptance(version: version, acceptedAt: at.toLocal());
  }
}

/// Keeps the record of which terms were accepted, with the app's other
/// settings on this device. It is never sent anywhere.
abstract class TermsKeeper {
  /// Reads the record, or null if the terms were never accepted here.
  Future<TermsAcceptance?> load();

  /// Keeps [acceptance]. Throws if it could not be kept.
  Future<void> save(TermsAcceptance acceptance);

  /// The keeper the app uses: a small file in the app's private folder,
  /// beside the vault and the radio settings.
  factory TermsKeeper.device() =>
      FileTermsKeeper(folder: DevicePlatform.dataDir);
}

/// Keeps the record as `terms.json` in a folder.
class FileTermsKeeper implements TermsKeeper {
  FileTermsKeeper({required this.folder});

  /// Finds the folder. It is made if it is not there yet, as on a first
  /// launch on a PC, where nothing else has made it.
  final Future<String> Function() folder;

  static const fileName = 'terms.json';

  Future<File> _file() async {
    final dir = await folder();
    return File('$dir${Platform.pathSeparator}$fileName');
  }

  @override
  Future<TermsAcceptance?> load() async {
    try {
      final text = await (await _file()).readAsString();
      return TermsAcceptance.fromJson(jsonDecode(text));
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(TermsAcceptance acceptance) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    // Written whole, then put in place, so a crash halfway leaves either
    // the old record or the new one, never half of one.
    final temporary = File('${file.path}.new');
    await temporary.writeAsString(jsonEncode(acceptance.toJson()), flush: true);
    await temporary.rename(file.path);
  }
}

/// A keeper that holds the record in memory only, for tests and previews.
class MemoryTermsKeeper implements TermsKeeper {
  MemoryTermsKeeper([this.saved]);

  /// A keeper whose record says the current terms were accepted.
  MemoryTermsKeeper.accepted()
    : saved = TermsAcceptance(
        version: termsVersion,
        acceptedAt: DateTime(2026, 11, 8, 10, 46),
      );

  TermsAcceptance? saved;

  @override
  Future<TermsAcceptance?> load() async => saved;

  @override
  Future<void> save(TermsAcceptance acceptance) async => saved = acceptance;
}

/// The terms accepted on this device, for the screens inside the app that
/// mention them, such as About. Absent where the app was opened without
/// the terms gate, as in tests that open one screen directly.
class AcceptedTerms extends InheritedWidget {
  const AcceptedTerms({
    super.key,
    required this.acceptance,
    required super.child,
  });

  final TermsAcceptance acceptance;

  static TermsAcceptance? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AcceptedTerms>()?.acceptance;

  @override
  bool updateShouldNotify(AcceptedTerms oldWidget) =>
      acceptance.version != oldWidget.acceptance.version ||
      acceptance.acceptedAt != oldWidget.acceptance.acceptedAt;
}
