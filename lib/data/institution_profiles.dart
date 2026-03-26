/// Pre-configured column mappings for common financial institutions.
/// Tier 2 parser checks these before falling back to generic header detection.
class InstitutionProfile {
  const InstitutionProfile({
    required this.name,
    required this.requiredHeaders,
    this.dateHeader,
    this.dateColumn,
    this.descriptionHeader,
    this.descriptionColumn,
    this.amountHeader,
    this.amountColumn,
    this.debitHeader,
    this.creditHeader,
    this.skipHeaderRow = true,
    this.signedAmount = false,
    this.defaultCurrency = 'USD',
    this.positional = false,
  });

  final String name;

  /// Set of lowercase header strings that must ALL be present to match.
  final Set<String> requiredHeaders;

  /// Header name to resolve the column index at runtime (lowercased).
  final String? dateHeader;
  final String? descriptionHeader;
  final String? amountHeader;
  final String? debitHeader;
  final String? creditHeader;

  /// Fixed column indices for positional formats (e.g. Wells Fargo).
  final int? dateColumn;
  final int? descriptionColumn;
  final int? amountColumn;

  final bool skipHeaderRow;

  /// True → single amount column where negative = debit, positive = credit.
  final bool signedAmount;

  final String defaultCurrency;

  /// True → do not rely on header names to find columns; use fixed indices.
  final bool positional;
}

abstract final class InstitutionProfiles {
  static const _chase = InstitutionProfile(
    name: 'Chase Bank',
    requiredHeaders: {'transaction date', 'post date'},
    dateHeader: 'transaction date',
    descriptionHeader: 'description',
    amountHeader: 'amount',
    signedAmount: true,
    defaultCurrency: 'USD',
  );

  static const _bofa = InstitutionProfile(
    name: 'Bank of America',
    requiredHeaders: {'running bal.'},
    dateHeader: 'date',
    descriptionHeader: 'description',
    amountHeader: 'amount',
    signedAmount: true,
    defaultCurrency: 'USD',
  );

  // Wells Fargo exports: "Date","Amount","*","*","Description" — positional, no real headers
  static const _wellsFargo = InstitutionProfile(
    name: 'Wells Fargo',
    requiredHeaders: {'*'},
    dateColumn: 0,
    amountColumn: 1,
    descriptionColumn: 4,
    signedAmount: true,
    positional: true,
    defaultCurrency: 'USD',
  );

  static const _capitalOne = InstitutionProfile(
    name: 'Capital One',
    requiredHeaders: {'transaction date', 'posted date', 'card no.'},
    dateHeader: 'transaction date',
    descriptionHeader: 'description',
    debitHeader: 'debit',
    creditHeader: 'credit',
    defaultCurrency: 'USD',
  );

  static const _coinbase = InstitutionProfile(
    name: 'Coinbase',
    requiredHeaders: {'timestamp', 'transaction type', 'asset', 'quantity transacted'},
    dateHeader: 'timestamp',
    descriptionHeader: 'notes',
    amountHeader: 'total (inclusive of fees and/or spread)',
    signedAmount: false,
    defaultCurrency: 'USD',
  );

  static const _strike = InstitutionProfile(
    name: 'Strike',
    requiredHeaders: {'date', 'type', 'asset', 'amount', 'fee', 'total'},
    dateHeader: 'date',
    descriptionHeader: 'type',
    amountHeader: 'total',
    signedAmount: false,
    defaultCurrency: 'USD',
  );

  static const _swan = InstitutionProfile(
    name: 'Swan Bitcoin',
    requiredHeaders: {'amount btc', 'amount usd', 'fee usd'},
    dateHeader: 'date',
    descriptionHeader: 'type',
    amountHeader: 'amount usd',
    signedAmount: false,
    defaultCurrency: 'USD',
  );

  static const all = <InstitutionProfile>[
    _chase,
    _bofa,
    _wellsFargo,
    _capitalOne,
    _coinbase,
    _strike,
    _swan,
  ];

  /// Returns the first profile whose required headers are all present in [headers].
  /// [headers] must be lowercase-trimmed.
  static InstitutionProfile? detect(List<String> headers) {
    final headerSet = headers.toSet();
    for (final profile in all) {
      if (profile.positional) {
        // Wells Fargo: look for '*' in columns 2 and 3
        if (headers.length >= 5 && headers[2] == '*' && headers[3] == '*') {
          return profile;
        }
      } else {
        if (profile.requiredHeaders.every((h) => headerSet.contains(h))) {
          return profile;
        }
      }
    }
    return null;
  }
}
