/// Kinds of file that can run a program or change the device when opened.
/// A received one is shown with a warning. DNet itself never opens files.
const _risky = {
  'apk',
  'apks',
  'xapk',
  'exe',
  'msi',
  'msix',
  'bat',
  'cmd',
  'com',
  'scr',
  'pif',
  'cpl',
  'dll',
  'sys',
  'lnk',
  'ps1',
  'psm1',
  'vbs',
  'vbe',
  'js',
  'jse',
  'wsf',
  'wsh',
  'hta',
  'jar',
  'reg',
  'sh',
  'appx',
  'appxbundle',
};

/// Whether a file called [name] could run a program when opened.
bool isRiskyFile(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return false;
  return _risky.contains(name.substring(dot + 1).toLowerCase());
}
