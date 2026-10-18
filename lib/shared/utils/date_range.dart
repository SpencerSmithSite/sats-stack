/// A half-open date range — `[start, end)`.
///
/// Every month aggregate in the app used to be built as a closed range ending
/// at `DateTime(y, m + 1, 0, 23, 59, 59)` and tested with `!isAfter(end)`.
/// `DateTime` carries milliseconds and microseconds, so that end is 999 ms
/// short of midnight and anything stamped in the last second of a month —
/// 23:59:59.400, say — belonged to no month at all: absent from the dashboard,
/// from analytics, from the budget it should have counted against, and from
/// the exported summary. Reachable without trying, because the add-transaction
/// sheet seeds the date with `DateTime.now()`.
///
/// A half-open range has no gap to fall into: consecutive months tile the
/// timeline exactly.
class DateRange {
  const DateRange(this.start, this.end);

  /// Inclusive.
  final DateTime start;

  /// Exclusive.
  final DateTime end;

  /// The calendar month containing [month], from midnight on the 1st up to —
  /// but not including — midnight on the 1st of the next month.
  ///
  /// December is fine: `DateTime(2025, 13, 1)` normalises to 2026-01-01.
  factory DateRange.month(DateTime month) => DateRange(
        DateTime(month.year, month.month, 1),
        DateTime(month.year, month.month + 1, 1),
      );

  /// The whole calendar year containing [date].
  factory DateRange.year(DateTime date) => DateRange(
        DateTime(date.year, 1, 1),
        DateTime(date.year + 1, 1, 1),
      );

  bool contains(DateTime date) => !date.isBefore(start) && date.isBefore(end);
}
