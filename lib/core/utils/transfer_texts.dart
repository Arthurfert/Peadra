/// Helpers to keep transfer descriptions meaningful after an account is
/// deleted.
///
/// A transfer is stored as two plain legs whose only link is the
/// description text: `Transfer to <dest>` on the source account and
/// `Transfer from <src>` on the destination account. When an account is
/// deleted (with or without its transactions), one half can end up with a
/// `NULL` account while its text still references the historical account
/// name. These pure helpers resolve display names from a mix of the live
/// account name and the name parsed out of the description text, so the UI
/// can keep showing "Transfer from A to B" instead of "?" or a raw stale
/// string.
library;

final _toPattern = RegExp(r'^Transfer to (.+)$', caseSensitive: false);
final _fromPattern = RegExp(r'^Transfer from (.+)$', caseSensitive: false);

/// Parses a transfer description. Returns `(isTo, name)` where [isTo] is
/// true for `Transfer to <name>` and false for `Transfer from <name>`,
/// or null when [text] is not a transfer description.
({bool isTo, String name})? parseTransferText(String? text) {
  final trimmed = (text ?? '').trim();
  if (trimmed.isEmpty) return null;
  final toMatch = _toPattern.firstMatch(trimmed);
  if (toMatch != null) return (isTo: true, name: toMatch.group(1)!.trim());
  final fromMatch = _fromPattern.firstMatch(trimmed);
  if (fromMatch != null) {
    return (isTo: false, name: fromMatch.group(1)!.trim());
  }
  return null;
}

/// True when [text] looks like a transfer leg description.
bool isTransferText(String? text) => parseTransferText(text) != null;

/// Resolves the (source, dest) account names for a single transfer leg.
///
/// - `Transfer to B` on account A → (A, B)
/// - `Transfer from A` on account B → (A, B)
/// - Either side is null when the account is gone (deleted) and the name
///   cannot be recovered from the text alone.
({String? source, String? dest}) transferEndsForSingle({
  required String? ownAccountName,
  required String? text,
}) {
  final parsed = parseTransferText(text);
  if (parsed == null) return (source: null, dest: null);
  if (parsed.isTo) {
    return (source: ownAccountName, dest: parsed.name);
  }
  return (source: parsed.name, dest: ownAccountName);
}

/// Resolves the (source, dest) names for a merged transfer pair.
///
/// [sourceAccountName] / [destAccountName] are the legs' live account names
/// (null when that account was deleted); [sourceLegText] / [destLegText]
/// are their description texts, from which the missing name is recovered.
({String? source, String? dest}) transferEndsForPair({
  required String? sourceAccountName,
  required String? destAccountName,
  required String? sourceLegText,
  required String? destLegText,
}) {
  // Fast path: both live names known, no text parsing needed.
  if (sourceAccountName != null && destAccountName != null) {
    return (source: sourceAccountName, dest: destAccountName);
  }
  final fromParsed = parseTransferText(destLegText);
  final toParsed = parseTransferText(sourceLegText);
  return (
    source: sourceAccountName ?? (fromParsed?.isTo == false ? fromParsed!.name : null),
    dest: destAccountName ?? (toParsed?.isTo == true ? toParsed!.name : null),
  );
}

/// Builds the user-facing transfer title.
///
/// Returns the [template] with `{source}` / `{dest}` filled in when both
/// ends are known, otherwise [fallback] (typically the raw description, so
/// the user still sees the historical account name).
String transferTitle({
  required String? source,
  required String? dest,
  required String template,
  required String fallback,
}) {
  if (source == null || source.isEmpty || dest == null || dest.isEmpty) {
    return fallback;
  }
  return template
      .replaceAll('{source}', source)
      .replaceAll('{dest}', dest);
}
