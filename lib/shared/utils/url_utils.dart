/// Cleaning up server URLs the user types.
library;

/// Cleans up a user-typed server URL, or returns null if it cannot be used.
///
/// Accepts a bare `host:port` or `host/path` and supplies [defaultScheme],
/// strips trailing slashes that would produce `//path`, and rejects anything
/// without an http(s) scheme and a host.
///
/// The scheme is the part that matters. `Uri.parse('ollama.example.com:11434')`
/// does not fail: it reads `ollama.example.com` as the *scheme* and yields a
/// URI with no host at all. Every check that looked at `.host` then saw an
/// empty string, which is how a remote server came to be treated as local.
String? normalizeServerUrl(String raw, {String defaultScheme = 'https'}) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = '$defaultScheme://$text';
  text = text.replaceAll(RegExp(r'/+$'), '');
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  return text;
}

/// Whether [url] — saved or typed — leaves mempool.space's public server in
/// use: blank, unusable (Save falls back to the default for it), or a
/// mempool.space address.
///
/// The one test for it. There were three — `contains('mempool.space')` on
/// raw text, "any custom value", and exact equality with the default URL —
/// so one URL was "custom" on one screen and "default" on another, which
/// decided both whether CoinGecko was also contacted and which privacy copy
/// was shown (audit B-9).
bool isDefaultMempoolServer(String? url) {
  final normalized = url == null ? null : normalizeServerUrl(url);
  if (normalized == null) return true;
  final host = Uri.parse(normalized).host.toLowerCase();
  return host == 'mempool.space' || host.endsWith('.mempool.space');
}
