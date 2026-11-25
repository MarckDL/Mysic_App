const _plain = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', 'å': 'a', //
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e', //
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', //
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o', //
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', //
  'ñ': 'n', 'ç': 'c', 'ý': 'y', 'ÿ': 'y',
};

/// [text] en minúsculas y sin tildes, para comparar sin distinguirlas.
String foldText(String text) {
  final out = StringBuffer();
  for (final char in text.trim().toLowerCase().split('')) {
    out.write(_plain[char] ?? char);
  }
  return out.toString();
}
