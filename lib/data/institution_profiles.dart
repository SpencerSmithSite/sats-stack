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
    this.positional = false,
    this.amountCurrency,
    this.currencyHeader,
    this.typeHeader,
    this.creditTypes = const {},
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

  /// True → do not rely on header names to find columns; use fixed indices.
  final bool positional;

  /// The currency the amount column is in, when the layout fixes it — Swan's
  /// "Amount USD". Null when it is the account's own currency.
  ///
  /// The exchange layouts read a fiat column. Stamping those rows with the
  /// account's currency booked a $500 purchase into a BTC account as 500 BTC.
  final String? amountCurrency;

  /// A column naming each row's currency, for layouts that mix them
  /// (lowercased). Read before [amountCurrency].
  final String? currencyHeader;

  /// A column naming the kind of transaction (lowercased), and the kinds in
  /// it that are money in. With an unsigned amount column this is the only
  /// way to tell a sale from a purchase.
  final String? typeHeader;
  final Set<String> creditTypes;
}

abstract final class InstitutionProfiles {
  static const _chase = InstitutionProfile(
    name: 'Chase Bank',
    requiredHeaders: {'transaction date', 'post date'},
    dateHeader: 'transaction date',
    descriptionHeader: 'description',
    amountHeader: 'amount',
    signedAmount: true,
  );

  static const _bofa = InstitutionProfile(
    name: 'Bank of America',
    requiredHeaders: {'running bal.'},
    dateHeader: 'date',
    descriptionHeader: 'description',
    amountHeader: 'amount',
    signedAmount: true,
  );

  // Wells Fargo exports: "Date","Amount","*","","Description" — positional,
  // and with no header line at all, so row 0 is the first transaction.
  static const _wellsFargo = InstitutionProfile(
    name: 'Wells Fargo',
    requiredHeaders: {'*'},
    dateColumn: 0,
    amountColumn: 1,
    descriptionColumn: 4,
    signedAmount: true,
    positional: true,
    skipHeaderRow: false,
  );

  static const _capitalOne = InstitutionProfile(
    name: 'Capital One',
    requiredHeaders: {'transaction date', 'posted date', 'card no.'},
    dateHeader: 'transaction date',
    descriptionHeader: 'description',
    debitHeader: 'debit',
    creditHeader: 'credit',
  );

  static const _coinbase = InstitutionProfile(
    name: 'Coinbase',
    requiredHeaders: {
      'timestamp',
      'transaction type',
      'asset',
      'quantity transacted',
    },
    dateHeader: 'timestamp',
    descriptionHeader: 'notes',
    // In the "Spot Price Currency" of the row, not in the asset.
    amountHeader: 'total (inclusive of fees and/or spread)',
    currencyHeader: 'spot price currency',
    signedAmount: false,
    typeHeader: 'transaction type',
    creditTypes: {
      'sell',
      'advanced trade sell',
      'receive',
      'deposit',
      'rewards income',
      'staking income',
      'learning reward',
      'inflation reward',
    },
  );

  static const _strike = InstitutionProfile(
    name: 'Strike',
    requiredHeaders: {'date', 'type', 'asset', 'amount', 'fee', 'total'},
    dateHeader: 'date',
    descriptionHeader: 'type',
    // Denominated in the row's asset.
    amountHeader: 'total',
    currencyHeader: 'asset',
    signedAmount: false,
    typeHeader: 'type',
    creditTypes: {'deposit', 'sell', 'receive'},
  );

  static const _swan = InstitutionProfile(
    name: 'Swan Bitcoin',
    requiredHeaders: {'amount btc', 'amount usd', 'fee usd'},
    dateHeader: 'date',
    descriptionHeader: 'type',
    amountHeader: 'amount usd',
    amountCurrency: 'USD',
    signedAmount: false,
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
        // Wells Fargo: five columns with '*' in the third. The fourth is the
        // check number — empty on almost every row, which requiring '*' there
        // too meant a real export never matched.
        if (headers.length == 5 && headers[2] == '*') {
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
