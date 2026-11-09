import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where DNet's source code lives, and where bugs are reported. Both are
/// opened only through the link check, in the user's own browser.
const sourceCodeUrl =
    'https://github.com/official-imvoiid/DNet-Your-Offline-Connector';
const issuesUrl = '$sourceCodeUrl/issues';

/// DNet's own licence, word for word as in the LICENSE file at the root of
/// the source code. A test holds the two in step.
const mitLicenceText = '''MIT License

Copyright (c) 2026 The DNet authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
''';

/// The fonts bundled with the app, and the licence file that must travel
/// with each of them.
const fontLicences = {
  'Figtree': 'assets/fonts/Figtree-OFL.txt',
  'JetBrains Mono': 'assets/fonts/JetBrainsMono-OFL.txt',
  'Noto Color Emoji': 'assets/fonts/NotoColorEmoji-OFL.txt',
};

/// DNet's own licence, then its fonts' licences, as entries for Flutter's
/// licences page. A font whose file is missing from a build is left out.
Stream<LicenseEntry> appLicences() async* {
  yield const LicenseEntryWithLineBreaks(['DNet'], mitLicenceText);
  for (final MapEntry(key: font, value: path) in fontLicences.entries) {
    final String text;
    try {
      text = await rootBundle.loadString(path);
    } on FlutterError {
      continue;
    }
    yield LicenseEntryWithLineBreaks([font], text);
  }
}

bool _registered = false;

/// Adds [appLicences] to the list Flutter shows on its licences page,
/// beside the packages' own. Safe to call more than once. Nothing is read
/// until that page is opened.
void registerAppLicences() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(appLicences);
}
