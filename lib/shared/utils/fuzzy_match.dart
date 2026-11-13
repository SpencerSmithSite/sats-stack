/// Forgiving text search: typos, abbreviations and accents.
///
/// Bank statements spell merchants their own way — "AMZN Mktp US",
/// "STARBUCKS #1234", "CAFÉ NÉRO" — and a search that only matched exact
/// substrings missed them whenever the user typed it the way they would say
/// it. This matcher keeps substring matches as the first tier and adds a
/// second, "close" tier underneath, so a typo still finds the row without
/// burying what the user typed exactly.
///
/// Hand-written rather than a package: the whole of it is a token split, a
/// character fold and a bounded edit distance.
library;

/// How well a [SearchText] answers a [SearchQuery].
enum MatchQuality {
  none,

  /// Found only by tolerating a typo or reading an abbreviation.
  close,

  /// Every word of the query appears, as typed, somewhere in the text.
  exact,
}

/// [text] lower-cased with accents removed, so "Café" and "cafe" compare
/// equal. Covers the Latin letters bank descriptions actually use; anything
/// else passes through unchanged.
String foldForSearch(String text) {
  final lower = text.toLowerCase();
  // Plain ASCII is by far the common case, and needs no second pass.
  if (!lower.codeUnits.any((c) => c > 0x7f)) return lower;
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    out.write(_folds[char] ?? char);
  }
  return out.toString();
}

/// Accented letter → the letters it is searched as.
final Map<String, String> _folds = () {
  const groups = {
    'a': 'àáâãäåāăą',
    'c': 'çćčĉċ',
    'd': 'ďđ',
    'e': 'èéêëēĕėęě',
    'g': 'ĝğġģ',
    'i': 'ìíîïĩīĭįı',
    'l': 'ĺļľŀł',
    'n': 'ñńņňŉ',
    'o': 'òóôõöøōŏő',
    'r': 'ŕŗř',
    's': 'śŝşš',
    't': 'ţťŧ',
    'u': 'ùúûüũūŭůűų',
    'y': 'ýÿŷ',
    'z': 'źżž',
  };
  return {
    for (final MapEntry(key: plain, value: accented) in groups.entries)
      for (final char in accented.split('')) char: plain,
    'ß': 'ss',
    'æ': 'ae',
    'œ': 'oe',
    'þ': 'th',
  };
}();

final _wordSplit = RegExp(r'[^a-z0-9]+');

/// The words of already-folded [text]: runs of letters and digits.
List<String> _words(String folded) => [
  for (final word in folded.split(_wordSplit))
    if (word.isNotEmpty) word,
];

/// Text to be searched, folded and split once so that a search over
/// thousands of rows does not redo it on every query.
class SearchText {
  SearchText(String text) : this._(foldForSearch(text));
  SearchText._(this.folded) : words = _words(folded);

  final String folded;
  final List<String> words;
}

/// What the user typed, folded and split once per search.
class SearchQuery {
  SearchQuery(String text) : this._(foldForSearch(text.trim()));
  SearchQuery._(this.folded) : words = _words(folded) {
    _queryWords = [for (final word in words) _QueryWord(word)];
    allowsClose = _queryWords.any((w) => w.fuzzy);
  }

  final String folded;
  final List<String> words;
  late final List<_QueryWord> _queryWords;

  /// Whether this query may match anything it does not contain exactly.
  ///
  /// Only when at least one word is long enough to tolerate a typo, or is a
  /// vowel-less abbreviation: two letters, or a short word with one letter
  /// changed, would match almost every row.
  late final bool allowsClose;

  bool get isEmpty => folded.isEmpty;

  MatchQuality match(SearchText text) {
    if (isEmpty) return MatchQuality.exact;
    if (_isExact(text)) return MatchQuality.exact;
    if (allowsClose && _isClose(text)) return MatchQuality.close;
    return MatchQuality.none;
  }

  bool _isExact(SearchText text) {
    // The query as typed, punctuation and all — "#1234", or a bare "&".
    if (text.folded.contains(folded)) return true;
    // Or every word of it, in any order: "mktp amzn".
    return words.isNotEmpty && words.every(text.folded.contains);
  }

  bool _isClose(SearchText text) =>
      _queryWords.every((q) => text.words.any(q.matches));
}

const _vowels = 'aeiou';
final _digit = RegExp(r'\d');

/// One word of a query, with what it may match worked out once rather than
/// for every word of every row.
class _QueryWord {
  _QueryWord(this.text)
    : abbreviation =
          text.length >= 3 &&
          !_digit.hasMatch(text) &&
          !text.substring(1).split('').any(_vowels.contains),
      typos =
          _digit.hasMatch(text)
              ? 0
              : text.length >= 8
              ? 2
              : text.length >= 4
              ? 1
              : 0;

  final String text;

  /// "amzn", "mktp", "wmt": no vowel after the first letter, which is how
  /// statements shorten a merchant's name.
  final bool abbreviation;

  /// How many edits a typo may take. One from four letters and two from
  /// eight, as most search engines allow; fewer would miss "starbuks", more
  /// would match unrelated short words. None for a word with a digit in it:
  /// a card number or an amount one digit off is a different one.
  final int typos;

  bool get fuzzy => abbreviation || typos > 0;

  /// Whether this word is in text word [t], or close enough to it.
  bool matches(String t) {
    if (t.contains(text)) return true;
    // The first letter must be right, for a typo as for an abbreviation: it
    // is the one people rarely get wrong, and letting it vary roughly
    // doubles what a short word matches. It is also what keeps this cheap,
    // since most words fail here before any counting.
    if (!fuzzy || t.codeUnitAt(0) != text.codeUnitAt(0)) return false;
    // An abbreviation's letters, in order, in a word not so long that almost
    // anything would contain them.
    if (abbreviation &&
        t.length <= text.length * 3 &&
        _isSubsequence(text, t)) {
      return true;
    }
    return typos > 0 && prefixEditDistance(text, t, typos) <= typos;
  }
}

bool _isSubsequence(String q, String t) {
  var i = 0;
  for (var j = 0; j < t.length && i < q.length; j++) {
    if (q.codeUnitAt(i) == t.codeUnitAt(j)) i++;
  }
  return i == q.length;
}

/// The fewest single-letter edits — insertion, deletion, substitution, or
/// swapping two neighbours — that turn [q] into [t] or into the start of [t],
/// so that a half-typed word is compared with the start of the word it is
/// heading for: "starbuk" is one edit from "starbuc", the start of
/// "starbucks".
///
/// Gives up once the answer must exceed [limit], returning `limit + 1`, so a
/// word that is nowhere near costs a length check and no table.
int prefixEditDistance(String q, String t, int limit) {
  final m = q.length;
  final n = t.length;
  if (n < m - limit) return limit + 1;
  // Three rows of the usual table: the swap looks two rows back.
  var before = List<int>.filled(n + 1, 0);
  var previous = List<int>.generate(n + 1, (j) => j);
  var current = List<int>.filled(n + 1, 0);
  var previousMin = 0;
  for (var i = 1; i <= m; i++) {
    current[0] = i;
    var rowMin = i;
    for (var j = 1; j <= n; j++) {
      final cost = q.codeUnitAt(i - 1) == t.codeUnitAt(j - 1) ? 0 : 1;
      var d = previous[j - 1] + cost;
      if (previous[j] + 1 < d) d = previous[j] + 1;
      if (current[j - 1] + 1 < d) d = current[j - 1] + 1;
      if (i > 1 &&
          j > 1 &&
          q.codeUnitAt(i - 1) == t.codeUnitAt(j - 2) &&
          q.codeUnitAt(i - 2) == t.codeUnitAt(j - 1) &&
          before[j - 2] + 1 < d) {
        d = before[j - 2] + 1;
      }
      current[j] = d;
      if (d < rowMin) rowMin = d;
    }
    // Every later cell is reached from this row, or by a swap from the one
    // before it at a cost of one more, so once both are past the limit
    // nothing can come back under it.
    if (rowMin > limit && previousMin >= limit) return limit + 1;
    previousMin = rowMin;
    final spare = before;
    before = previous;
    previous = current;
    current = spare;
  }
  // `previous` now holds the last row: [q] against every prefix of [t].
  var best = limit + 1;
  for (var j = m - limit < 0 ? 0 : m - limit; j <= n; j++) {
    if (previous[j] < best) best = previous[j];
  }
  return best;
}
