/// Which way the price has to go for a [PriceAlert] to fire.
enum PriceAlertDirection {
  above,
  below;

  static PriceAlertDirection? fromName(Object? name) => switch (name) {
    'above' => above,
    'below' => below,
    _ => null,
  };
}

/// A BTC price the user wants to hear about, in the currency they set it in.
///
/// It keeps its own currency rather than following the display currency, and
/// is compared with the price in that currency: converting it on every
/// currency switch would move the level by whatever the exchange rate did,
/// so an alert set at $100,000 would no longer be at $100,000.
///
/// It fires on a crossing, not on the price merely being past the level, so
/// it remembers which side the price was last seen on ([wasBeyond]). Once it
/// has fired it is spent ([triggeredAt]) and stays in the list, marked, until
/// the user deletes it. It is not re-armed when the price comes back: prices
/// are checked about every ten minutes, and a price hovering at the level
/// would re-arm and fire again on most of them.
class PriceAlert {
  const PriceAlert({
    required this.id,
    required this.direction,
    required this.price,
    required this.currency,
    required this.createdAt,
    this.wasBeyond,
    this.triggeredAt,
  });

  /// Unique among the alerts, and never reused while the list holds one —
  /// the notification id is derived from it.
  final int id;
  final PriceAlertDirection direction;

  /// The level, in [currency].
  final double price;

  /// Upper-case code, e.g. `USD`.
  final String currency;
  final DateTime createdAt;

  /// Whether the price was past the level when last seen; null until a price
  /// in [currency] has been seen at all. A first sighting only records the
  /// side: with nothing seen before it, there is no crossing to report.
  final bool? wasBeyond;

  /// When it fired, or null while it is still waiting.
  final DateTime? triggeredAt;

  bool get isTriggered => triggeredAt != null;

  /// Whether [current] is at or past the level, in the alert's direction.
  bool isBeyond(double current) => switch (direction) {
    PriceAlertDirection.above => current >= price,
    PriceAlertDirection.below => current <= price,
  };

  /// Whether [current] completes a crossing: the price was last seen short of
  /// the level and is now at or past it.
  bool isCrossedBy(double current) =>
      !isTriggered && wasBeyond == false && isBeyond(current);

  PriceAlert copyWith({bool? wasBeyond, DateTime? triggeredAt}) => PriceAlert(
    id: id,
    direction: direction,
    price: price,
    currency: currency,
    createdAt: createdAt,
    wasBeyond: wasBeyond ?? this.wasBeyond,
    triggeredAt: triggeredAt ?? this.triggeredAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'direction': direction.name,
    'price': price,
    'currency': currency,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'wasBeyond': wasBeyond,
    'triggeredAt': triggeredAt?.millisecondsSinceEpoch,
  };

  /// The alert [json] describes, or null if it is not a whole one.
  ///
  /// A restored database can hold anything under the key, so a malformed
  /// entry is dropped rather than allowed to throw out of Settings or out of
  /// the price listener.
  static PriceAlert? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final direction = PriceAlertDirection.fromName(json['direction']);
    final price = json['price'];
    final currency = json['currency'];
    final createdAt = json['createdAt'];
    final wasBeyond = json['wasBeyond'];
    final triggeredAt = json['triggeredAt'];
    if (id is! int ||
        direction == null ||
        price is! num ||
        !price.isFinite ||
        price <= 0 ||
        currency is! String ||
        currency.isEmpty ||
        createdAt is! int ||
        (wasBeyond != null && wasBeyond is! bool) ||
        (triggeredAt != null && triggeredAt is! int)) {
      return null;
    }
    return PriceAlert(
      id: id,
      direction: direction,
      price: price.toDouble(),
      currency: currency.toUpperCase(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
      wasBeyond: wasBeyond as bool?,
      triggeredAt:
          triggeredAt == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(triggeredAt as int),
    );
  }
}
