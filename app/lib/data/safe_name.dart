/// A name someone else chose, made safe to show.
///
/// Anyone can call themselves anything, so a name is never proof of who
/// someone is: verifying them is. But a name must not be able to *look*
/// like another while being different underneath, or the short tag shown
/// when two people share a name (`Sam·4F2A`) would never appear. So the
/// characters that show as nothing, or turn the text around, are taken
/// out: direction marks and overrides, zero-width spaces, word joiners,
/// blank "filler" letters, invisible tags and control characters. Runs of
/// spaces become one.
///
/// The two joiners that some scripts (Hindi, Bengali, Malayalam…) and
/// emoji need to draw correctly, U+200C and U+200D, are kept.
String safeName(String name) {
  final kept = StringBuffer();
  for (final rune in name.runes) {
    if (!_hidden(rune)) kept.writeCharCode(rune);
  }
  return kept.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool _hidden(int r) =>
    // Control characters.
    r < 0x20 ||
    (r >= 0x7F && r <= 0x9F) ||
    // Soft hyphen, combining grapheme joiner, Arabic letter mark.
    r == 0x00AD ||
    r == 0x034F ||
    r == 0x061C ||
    // Hangul and Khmer letters that draw as nothing, Mongolian separator.
    r == 0x115F ||
    r == 0x1160 ||
    r == 0x17B4 ||
    r == 0x17B5 ||
    r == 0x180E ||
    r == 0x3164 ||
    r == 0xFFA0 ||
    // Zero-width space, and the left-to-right and right-to-left marks.
    r == 0x200B ||
    r == 0x200E ||
    r == 0x200F ||
    // Direction embeddings and overrides.
    (r >= 0x202A && r <= 0x202E) ||
    // Word joiner and the invisible maths operators.
    (r >= 0x2060 && r <= 0x2064) ||
    // Direction isolates, and the deprecated format characters.
    (r >= 0x2066 && r <= 0x206F) ||
    // Byte order mark, interlinear annotation marks.
    r == 0xFEFF ||
    (r >= 0xFFF9 && r <= 0xFFFB) ||
    // Tags.
    (r >= 0xE0000 && r <= 0xE007F);
