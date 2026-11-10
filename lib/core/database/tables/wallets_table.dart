import 'package:drift/drift.dart';

class Wallets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get label => text().withLength(min: 1, max: 100)();
  // 'xpub' | 'manual'
  TextColumn get type => text().withLength(min: 1, max: 10)();
  TextColumn get xpub => text().nullable()();

  /// Whether the user chose the address type, which [xpub]'s version bytes
  /// record (`xpub`/`ypub`/`zpub`). A key and an address type together are
  /// one wallet, so the same key can be tracked again as another type (audit
  /// B-7). Left false, a plain `xpub` with no history yet is looked at again
  /// on each sync; set, the user's choice stands.
  BoolColumn get scriptTypeChosen =>
      boolean().withDefault(const Constant(false))();
  // hex color string e.g. '#F7931A'
  TextColumn get color => text().withLength(min: 7, max: 7)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
