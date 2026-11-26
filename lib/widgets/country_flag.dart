/// Renders a two-letter country code as a flag emoji.
String countryFlagEmoji(String countryCode) {
  final code = countryCode.toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(code)) return '🏳️';
  const base = 0x1F1E6;
  final first = base + (code.codeUnitAt(0) - 'A'.codeUnitAt(0));
  final second = base + (code.codeUnitAt(1) - 'A'.codeUnitAt(0));
  return String.fromCharCode(first) + String.fromCharCode(second);
}
