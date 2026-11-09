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

// ── Logins in server addresses ──────────────────────────────────────────────
//
// A `user:password@` part is how a server behind Basic auth is reached — the
// HTTP client sends it as the Authorization header — so it is kept and used,
// but never stored in `AppSettings`, which Settings → Data exports whole, and
// never shown (audit A-17).

/// What stands in for a saved password wherever a server address is shown.
/// Typed back unchanged, it keeps the saved password — see
/// [resolveTypedUserInfo].
const passwordMask = '••••••';

/// [url] as the address without its `user:password@` part, and that part
/// (null when there is none), still percent-encoded as the URL had it.
({String url, String? userInfo}) splitUserInfo(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.userInfo.isEmpty) return (url: url, userInfo: null);
  return (url: uri.replace(userInfo: '').toString(), userInfo: uri.userInfo);
}

/// [url] with [userInfo] put back in front of its host.
///
/// Done as text: `Uri.replace` would percent-encode [passwordMask].
String withUserInfo(String url, String? userInfo) {
  if (userInfo == null || userInfo.isEmpty) return url;
  final start = url.indexOf('://');
  if (start == -1) return url;
  return '${url.substring(0, start + 3)}$userInfo@${url.substring(start + 3)}';
}

/// [url] for display: any password replaced by [passwordMask].
String maskPassword(String url) {
  final split = splitUserInfo(url);
  final info = split.userInfo;
  if (info == null) return url;
  final colon = info.indexOf(':');
  return colon == -1
      ? withUserInfo(split.url, info)
      : withUserInfo(split.url, '${info.substring(0, colon)}:$passwordMask');
}

/// The login to keep when [typed] is saved over [saved], both `user:password`
/// parts as [splitUserInfo] gives them.
///
/// A field shows the saved password as [passwordMask], so a field saved
/// unchanged sends the mask back: for the same user that keeps the saved
/// password. Any other password is the user's new one, and no login at all
/// removes it.
String? resolveTypedUserInfo(String? typed, String? saved) {
  if (typed == null || typed.isEmpty) return null;
  final colon = typed.indexOf(':');
  if (colon == -1) return typed;
  final password = Uri.decodeComponent(typed.substring(colon + 1));
  if (password != passwordMask) return typed;
  final user = typed.substring(0, colon);
  final savedColon = saved?.indexOf(':') ?? -1;
  if (saved != null &&
      savedColon != -1 &&
      saved.substring(0, savedColon) == user) {
    return saved;
  }
  // The mask for a login that was never saved: there is no password to keep.
  return user;
}

/// Where [url] goes — scheme, host and port — for telling whether a saved
/// login belongs to it.
String serverOrigin(String url) {
  final uri = Uri.tryParse(splitUserInfo(url).url);
  if (uri == null || uri.host.isEmpty) return url;
  return '${uri.scheme}://${uri.host.toLowerCase()}:${uri.port}';
}
