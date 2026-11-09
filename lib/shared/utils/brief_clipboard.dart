import 'dart:async';

import 'package:flutter/services.dart';

/// How long copied financial text stays on the clipboard.
const briefClipboardLife = Duration(minutes: 1);

Timer? _clearing;

/// Copies [text], then empties the clipboard after [briefClipboardLife].
///
/// For text full of the user's figures — a chat answer. Left on the
/// clipboard it stayed readable by any app that reads it, for as long as
/// nothing else was copied (audit U-16). Cleared without reading it first:
/// reading the clipboard asks the user's permission on iOS 16 and later, and
/// shows a notice on Android 12 and later. So something else copied within
/// the minute is cleared too, which the caller says when it copies.
Future<void> copyBriefly(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  _clearing?.cancel();
  _clearing = Timer(
    briefClipboardLife,
    () => unawaited(Clipboard.setData(const ClipboardData(text: ''))),
  );
}
