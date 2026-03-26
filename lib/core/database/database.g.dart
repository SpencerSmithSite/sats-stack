// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $WalletsTable extends Wallets with TableInfo<$WalletsTable, Wallet> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WalletsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 100,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 10,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _xpubMeta = const VerificationMeta('xpub');
  @override
  late final GeneratedColumn<String> xpub = GeneratedColumn<String>(
    'xpub',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 7,
      maxTextLength: 7,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    label,
    type,
    xpub,
    color,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'wallets';
  @override
  VerificationContext validateIntegrity(
    Insertable<Wallet> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('xpub')) {
      context.handle(
        _xpubMeta,
        xpub.isAcceptableOrUnknown(data['xpub']!, _xpubMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Wallet map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Wallet(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      label:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}label'],
          )!,
      type:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}type'],
          )!,
      xpub: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}xpub'],
      ),
      color:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}color'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
    );
  }

  @override
  $WalletsTable createAlias(String alias) {
    return $WalletsTable(attachedDatabase, alias);
  }
}

class Wallet extends DataClass implements Insertable<Wallet> {
  final int id;
  final String label;
  final String type;
  final String? xpub;
  final String color;
  final DateTime createdAt;
  const Wallet({
    required this.id,
    required this.label,
    required this.type,
    this.xpub,
    required this.color,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['label'] = Variable<String>(label);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || xpub != null) {
      map['xpub'] = Variable<String>(xpub);
    }
    map['color'] = Variable<String>(color);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  WalletsCompanion toCompanion(bool nullToAbsent) {
    return WalletsCompanion(
      id: Value(id),
      label: Value(label),
      type: Value(type),
      xpub: xpub == null && nullToAbsent ? const Value.absent() : Value(xpub),
      color: Value(color),
      createdAt: Value(createdAt),
    );
  }

  factory Wallet.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Wallet(
      id: serializer.fromJson<int>(json['id']),
      label: serializer.fromJson<String>(json['label']),
      type: serializer.fromJson<String>(json['type']),
      xpub: serializer.fromJson<String?>(json['xpub']),
      color: serializer.fromJson<String>(json['color']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'label': serializer.toJson<String>(label),
      'type': serializer.toJson<String>(type),
      'xpub': serializer.toJson<String?>(xpub),
      'color': serializer.toJson<String>(color),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Wallet copyWith({
    int? id,
    String? label,
    String? type,
    Value<String?> xpub = const Value.absent(),
    String? color,
    DateTime? createdAt,
  }) => Wallet(
    id: id ?? this.id,
    label: label ?? this.label,
    type: type ?? this.type,
    xpub: xpub.present ? xpub.value : this.xpub,
    color: color ?? this.color,
    createdAt: createdAt ?? this.createdAt,
  );
  Wallet copyWithCompanion(WalletsCompanion data) {
    return Wallet(
      id: data.id.present ? data.id.value : this.id,
      label: data.label.present ? data.label.value : this.label,
      type: data.type.present ? data.type.value : this.type,
      xpub: data.xpub.present ? data.xpub.value : this.xpub,
      color: data.color.present ? data.color.value : this.color,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Wallet(')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('type: $type, ')
          ..write('xpub: $xpub, ')
          ..write('color: $color, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, label, type, xpub, color, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Wallet &&
          other.id == this.id &&
          other.label == this.label &&
          other.type == this.type &&
          other.xpub == this.xpub &&
          other.color == this.color &&
          other.createdAt == this.createdAt);
}

class WalletsCompanion extends UpdateCompanion<Wallet> {
  final Value<int> id;
  final Value<String> label;
  final Value<String> type;
  final Value<String?> xpub;
  final Value<String> color;
  final Value<DateTime> createdAt;
  const WalletsCompanion({
    this.id = const Value.absent(),
    this.label = const Value.absent(),
    this.type = const Value.absent(),
    this.xpub = const Value.absent(),
    this.color = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  WalletsCompanion.insert({
    this.id = const Value.absent(),
    required String label,
    required String type,
    this.xpub = const Value.absent(),
    required String color,
    this.createdAt = const Value.absent(),
  }) : label = Value(label),
       type = Value(type),
       color = Value(color);
  static Insertable<Wallet> custom({
    Expression<int>? id,
    Expression<String>? label,
    Expression<String>? type,
    Expression<String>? xpub,
    Expression<String>? color,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (label != null) 'label': label,
      if (type != null) 'type': type,
      if (xpub != null) 'xpub': xpub,
      if (color != null) 'color': color,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  WalletsCompanion copyWith({
    Value<int>? id,
    Value<String>? label,
    Value<String>? type,
    Value<String?>? xpub,
    Value<String>? color,
    Value<DateTime>? createdAt,
  }) {
    return WalletsCompanion(
      id: id ?? this.id,
      label: label ?? this.label,
      type: type ?? this.type,
      xpub: xpub ?? this.xpub,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (xpub.present) {
      map['xpub'] = Variable<String>(xpub.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WalletsCompanion(')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('type: $type, ')
          ..write('xpub: $xpub, ')
          ..write('color: $color, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $TransactionsTable extends Transactions
    with TableInfo<$TransactionsTable, Transaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _walletIdMeta = const VerificationMeta(
    'walletId',
  );
  @override
  late final GeneratedColumn<int> walletId = GeneratedColumn<int>(
    'wallet_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES wallets (id)',
    ),
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 0,
      maxTextLength: 500,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountSatsMeta = const VerificationMeta(
    'amountSats',
  );
  @override
  late final GeneratedColumn<int> amountSats = GeneratedColumn<int>(
    'amount_sats',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountFiatMeta = const VerificationMeta(
    'amountFiat',
  );
  @override
  late final GeneratedColumn<double> amountFiat = GeneratedColumn<double>(
    'amount_fiat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fiatCurrencyMeta = const VerificationMeta(
    'fiatCurrency',
  );
  @override
  late final GeneratedColumn<String> fiatCurrency = GeneratedColumn<String>(
    'fiat_currency',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 3,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 10,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isBitcoinMeta = const VerificationMeta(
    'isBitcoin',
  );
  @override
  late final GeneratedColumn<bool> isBitcoin = GeneratedColumn<bool>(
    'is_bitcoin',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_bitcoin" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dedupHashMeta = const VerificationMeta(
    'dedupHash',
  );
  @override
  late final GeneratedColumn<String> dedupHash = GeneratedColumn<String>(
    'dedup_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _recurringPeriodMeta = const VerificationMeta(
    'recurringPeriod',
  );
  @override
  late final GeneratedColumn<String> recurringPeriod = GeneratedColumn<String>(
    'recurring_period',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recurringAnchorDateMeta =
      const VerificationMeta('recurringAnchorDate');
  @override
  late final GeneratedColumn<DateTime> recurringAnchorDate =
      GeneratedColumn<DateTime>(
        'recurring_anchor_date',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    walletId,
    date,
    description,
    amountSats,
    amountFiat,
    fiatCurrency,
    category,
    source,
    isBitcoin,
    notes,
    dedupHash,
    createdAt,
    recurringPeriod,
    recurringAnchorDate,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Transaction> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('wallet_id')) {
      context.handle(
        _walletIdMeta,
        walletId.isAcceptableOrUnknown(data['wallet_id']!, _walletIdMeta),
      );
    } else if (isInserting) {
      context.missing(_walletIdMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('amount_sats')) {
      context.handle(
        _amountSatsMeta,
        amountSats.isAcceptableOrUnknown(data['amount_sats']!, _amountSatsMeta),
      );
    } else if (isInserting) {
      context.missing(_amountSatsMeta);
    }
    if (data.containsKey('amount_fiat')) {
      context.handle(
        _amountFiatMeta,
        amountFiat.isAcceptableOrUnknown(data['amount_fiat']!, _amountFiatMeta),
      );
    } else if (isInserting) {
      context.missing(_amountFiatMeta);
    }
    if (data.containsKey('fiat_currency')) {
      context.handle(
        _fiatCurrencyMeta,
        fiatCurrency.isAcceptableOrUnknown(
          data['fiat_currency']!,
          _fiatCurrencyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fiatCurrencyMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('is_bitcoin')) {
      context.handle(
        _isBitcoinMeta,
        isBitcoin.isAcceptableOrUnknown(data['is_bitcoin']!, _isBitcoinMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('dedup_hash')) {
      context.handle(
        _dedupHashMeta,
        dedupHash.isAcceptableOrUnknown(data['dedup_hash']!, _dedupHashMeta),
      );
    } else if (isInserting) {
      context.missing(_dedupHashMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('recurring_period')) {
      context.handle(
        _recurringPeriodMeta,
        recurringPeriod.isAcceptableOrUnknown(
          data['recurring_period']!,
          _recurringPeriodMeta,
        ),
      );
    }
    if (data.containsKey('recurring_anchor_date')) {
      context.handle(
        _recurringAnchorDateMeta,
        recurringAnchorDate.isAcceptableOrUnknown(
          data['recurring_anchor_date']!,
          _recurringAnchorDateMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Transaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Transaction(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      walletId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}wallet_id'],
          )!,
      date:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}date'],
          )!,
      description:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}description'],
          )!,
      amountSats:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}amount_sats'],
          )!,
      amountFiat:
          attachedDatabase.typeMapping.read(
            DriftSqlType.double,
            data['${effectivePrefix}amount_fiat'],
          )!,
      fiatCurrency:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}fiat_currency'],
          )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
      source:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}source'],
          )!,
      isBitcoin:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}is_bitcoin'],
          )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      dedupHash:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}dedup_hash'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      recurringPeriod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recurring_period'],
      ),
      recurringAnchorDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}recurring_anchor_date'],
      ),
    );
  }

  @override
  $TransactionsTable createAlias(String alias) {
    return $TransactionsTable(attachedDatabase, alias);
  }
}

class Transaction extends DataClass implements Insertable<Transaction> {
  final int id;
  final int walletId;
  final DateTime date;
  final String description;
  final int amountSats;
  final double amountFiat;
  final String fiatCurrency;
  final String? category;
  final String source;
  final bool isBitcoin;
  final String? notes;
  final String dedupHash;
  final DateTime createdAt;
  final String? recurringPeriod;
  final DateTime? recurringAnchorDate;
  const Transaction({
    required this.id,
    required this.walletId,
    required this.date,
    required this.description,
    required this.amountSats,
    required this.amountFiat,
    required this.fiatCurrency,
    this.category,
    required this.source,
    required this.isBitcoin,
    this.notes,
    required this.dedupHash,
    required this.createdAt,
    this.recurringPeriod,
    this.recurringAnchorDate,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['wallet_id'] = Variable<int>(walletId);
    map['date'] = Variable<DateTime>(date);
    map['description'] = Variable<String>(description);
    map['amount_sats'] = Variable<int>(amountSats);
    map['amount_fiat'] = Variable<double>(amountFiat);
    map['fiat_currency'] = Variable<String>(fiatCurrency);
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    map['source'] = Variable<String>(source);
    map['is_bitcoin'] = Variable<bool>(isBitcoin);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['dedup_hash'] = Variable<String>(dedupHash);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || recurringPeriod != null) {
      map['recurring_period'] = Variable<String>(recurringPeriod);
    }
    if (!nullToAbsent || recurringAnchorDate != null) {
      map['recurring_anchor_date'] = Variable<DateTime>(recurringAnchorDate);
    }
    return map;
  }

  TransactionsCompanion toCompanion(bool nullToAbsent) {
    return TransactionsCompanion(
      id: Value(id),
      walletId: Value(walletId),
      date: Value(date),
      description: Value(description),
      amountSats: Value(amountSats),
      amountFiat: Value(amountFiat),
      fiatCurrency: Value(fiatCurrency),
      category:
          category == null && nullToAbsent
              ? const Value.absent()
              : Value(category),
      source: Value(source),
      isBitcoin: Value(isBitcoin),
      notes:
          notes == null && nullToAbsent ? const Value.absent() : Value(notes),
      dedupHash: Value(dedupHash),
      createdAt: Value(createdAt),
      recurringPeriod:
          recurringPeriod == null && nullToAbsent
              ? const Value.absent()
              : Value(recurringPeriod),
      recurringAnchorDate:
          recurringAnchorDate == null && nullToAbsent
              ? const Value.absent()
              : Value(recurringAnchorDate),
    );
  }

  factory Transaction.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Transaction(
      id: serializer.fromJson<int>(json['id']),
      walletId: serializer.fromJson<int>(json['walletId']),
      date: serializer.fromJson<DateTime>(json['date']),
      description: serializer.fromJson<String>(json['description']),
      amountSats: serializer.fromJson<int>(json['amountSats']),
      amountFiat: serializer.fromJson<double>(json['amountFiat']),
      fiatCurrency: serializer.fromJson<String>(json['fiatCurrency']),
      category: serializer.fromJson<String?>(json['category']),
      source: serializer.fromJson<String>(json['source']),
      isBitcoin: serializer.fromJson<bool>(json['isBitcoin']),
      notes: serializer.fromJson<String?>(json['notes']),
      dedupHash: serializer.fromJson<String>(json['dedupHash']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      recurringPeriod: serializer.fromJson<String?>(json['recurringPeriod']),
      recurringAnchorDate: serializer.fromJson<DateTime?>(
        json['recurringAnchorDate'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'walletId': serializer.toJson<int>(walletId),
      'date': serializer.toJson<DateTime>(date),
      'description': serializer.toJson<String>(description),
      'amountSats': serializer.toJson<int>(amountSats),
      'amountFiat': serializer.toJson<double>(amountFiat),
      'fiatCurrency': serializer.toJson<String>(fiatCurrency),
      'category': serializer.toJson<String?>(category),
      'source': serializer.toJson<String>(source),
      'isBitcoin': serializer.toJson<bool>(isBitcoin),
      'notes': serializer.toJson<String?>(notes),
      'dedupHash': serializer.toJson<String>(dedupHash),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'recurringPeriod': serializer.toJson<String?>(recurringPeriod),
      'recurringAnchorDate': serializer.toJson<DateTime?>(recurringAnchorDate),
    };
  }

  Transaction copyWith({
    int? id,
    int? walletId,
    DateTime? date,
    String? description,
    int? amountSats,
    double? amountFiat,
    String? fiatCurrency,
    Value<String?> category = const Value.absent(),
    String? source,
    bool? isBitcoin,
    Value<String?> notes = const Value.absent(),
    String? dedupHash,
    DateTime? createdAt,
    Value<String?> recurringPeriod = const Value.absent(),
    Value<DateTime?> recurringAnchorDate = const Value.absent(),
  }) => Transaction(
    id: id ?? this.id,
    walletId: walletId ?? this.walletId,
    date: date ?? this.date,
    description: description ?? this.description,
    amountSats: amountSats ?? this.amountSats,
    amountFiat: amountFiat ?? this.amountFiat,
    fiatCurrency: fiatCurrency ?? this.fiatCurrency,
    category: category.present ? category.value : this.category,
    source: source ?? this.source,
    isBitcoin: isBitcoin ?? this.isBitcoin,
    notes: notes.present ? notes.value : this.notes,
    dedupHash: dedupHash ?? this.dedupHash,
    createdAt: createdAt ?? this.createdAt,
    recurringPeriod:
        recurringPeriod.present ? recurringPeriod.value : this.recurringPeriod,
    recurringAnchorDate:
        recurringAnchorDate.present
            ? recurringAnchorDate.value
            : this.recurringAnchorDate,
  );
  Transaction copyWithCompanion(TransactionsCompanion data) {
    return Transaction(
      id: data.id.present ? data.id.value : this.id,
      walletId: data.walletId.present ? data.walletId.value : this.walletId,
      date: data.date.present ? data.date.value : this.date,
      description:
          data.description.present ? data.description.value : this.description,
      amountSats:
          data.amountSats.present ? data.amountSats.value : this.amountSats,
      amountFiat:
          data.amountFiat.present ? data.amountFiat.value : this.amountFiat,
      fiatCurrency:
          data.fiatCurrency.present
              ? data.fiatCurrency.value
              : this.fiatCurrency,
      category: data.category.present ? data.category.value : this.category,
      source: data.source.present ? data.source.value : this.source,
      isBitcoin: data.isBitcoin.present ? data.isBitcoin.value : this.isBitcoin,
      notes: data.notes.present ? data.notes.value : this.notes,
      dedupHash: data.dedupHash.present ? data.dedupHash.value : this.dedupHash,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      recurringPeriod:
          data.recurringPeriod.present
              ? data.recurringPeriod.value
              : this.recurringPeriod,
      recurringAnchorDate:
          data.recurringAnchorDate.present
              ? data.recurringAnchorDate.value
              : this.recurringAnchorDate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Transaction(')
          ..write('id: $id, ')
          ..write('walletId: $walletId, ')
          ..write('date: $date, ')
          ..write('description: $description, ')
          ..write('amountSats: $amountSats, ')
          ..write('amountFiat: $amountFiat, ')
          ..write('fiatCurrency: $fiatCurrency, ')
          ..write('category: $category, ')
          ..write('source: $source, ')
          ..write('isBitcoin: $isBitcoin, ')
          ..write('notes: $notes, ')
          ..write('dedupHash: $dedupHash, ')
          ..write('createdAt: $createdAt, ')
          ..write('recurringPeriod: $recurringPeriod, ')
          ..write('recurringAnchorDate: $recurringAnchorDate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    walletId,
    date,
    description,
    amountSats,
    amountFiat,
    fiatCurrency,
    category,
    source,
    isBitcoin,
    notes,
    dedupHash,
    createdAt,
    recurringPeriod,
    recurringAnchorDate,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Transaction &&
          other.id == this.id &&
          other.walletId == this.walletId &&
          other.date == this.date &&
          other.description == this.description &&
          other.amountSats == this.amountSats &&
          other.amountFiat == this.amountFiat &&
          other.fiatCurrency == this.fiatCurrency &&
          other.category == this.category &&
          other.source == this.source &&
          other.isBitcoin == this.isBitcoin &&
          other.notes == this.notes &&
          other.dedupHash == this.dedupHash &&
          other.createdAt == this.createdAt &&
          other.recurringPeriod == this.recurringPeriod &&
          other.recurringAnchorDate == this.recurringAnchorDate);
}

class TransactionsCompanion extends UpdateCompanion<Transaction> {
  final Value<int> id;
  final Value<int> walletId;
  final Value<DateTime> date;
  final Value<String> description;
  final Value<int> amountSats;
  final Value<double> amountFiat;
  final Value<String> fiatCurrency;
  final Value<String?> category;
  final Value<String> source;
  final Value<bool> isBitcoin;
  final Value<String?> notes;
  final Value<String> dedupHash;
  final Value<DateTime> createdAt;
  final Value<String?> recurringPeriod;
  final Value<DateTime?> recurringAnchorDate;
  const TransactionsCompanion({
    this.id = const Value.absent(),
    this.walletId = const Value.absent(),
    this.date = const Value.absent(),
    this.description = const Value.absent(),
    this.amountSats = const Value.absent(),
    this.amountFiat = const Value.absent(),
    this.fiatCurrency = const Value.absent(),
    this.category = const Value.absent(),
    this.source = const Value.absent(),
    this.isBitcoin = const Value.absent(),
    this.notes = const Value.absent(),
    this.dedupHash = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.recurringPeriod = const Value.absent(),
    this.recurringAnchorDate = const Value.absent(),
  });
  TransactionsCompanion.insert({
    this.id = const Value.absent(),
    required int walletId,
    required DateTime date,
    required String description,
    required int amountSats,
    required double amountFiat,
    required String fiatCurrency,
    this.category = const Value.absent(),
    required String source,
    this.isBitcoin = const Value.absent(),
    this.notes = const Value.absent(),
    required String dedupHash,
    this.createdAt = const Value.absent(),
    this.recurringPeriod = const Value.absent(),
    this.recurringAnchorDate = const Value.absent(),
  }) : walletId = Value(walletId),
       date = Value(date),
       description = Value(description),
       amountSats = Value(amountSats),
       amountFiat = Value(amountFiat),
       fiatCurrency = Value(fiatCurrency),
       source = Value(source),
       dedupHash = Value(dedupHash);
  static Insertable<Transaction> custom({
    Expression<int>? id,
    Expression<int>? walletId,
    Expression<DateTime>? date,
    Expression<String>? description,
    Expression<int>? amountSats,
    Expression<double>? amountFiat,
    Expression<String>? fiatCurrency,
    Expression<String>? category,
    Expression<String>? source,
    Expression<bool>? isBitcoin,
    Expression<String>? notes,
    Expression<String>? dedupHash,
    Expression<DateTime>? createdAt,
    Expression<String>? recurringPeriod,
    Expression<DateTime>? recurringAnchorDate,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (walletId != null) 'wallet_id': walletId,
      if (date != null) 'date': date,
      if (description != null) 'description': description,
      if (amountSats != null) 'amount_sats': amountSats,
      if (amountFiat != null) 'amount_fiat': amountFiat,
      if (fiatCurrency != null) 'fiat_currency': fiatCurrency,
      if (category != null) 'category': category,
      if (source != null) 'source': source,
      if (isBitcoin != null) 'is_bitcoin': isBitcoin,
      if (notes != null) 'notes': notes,
      if (dedupHash != null) 'dedup_hash': dedupHash,
      if (createdAt != null) 'created_at': createdAt,
      if (recurringPeriod != null) 'recurring_period': recurringPeriod,
      if (recurringAnchorDate != null)
        'recurring_anchor_date': recurringAnchorDate,
    });
  }

  TransactionsCompanion copyWith({
    Value<int>? id,
    Value<int>? walletId,
    Value<DateTime>? date,
    Value<String>? description,
    Value<int>? amountSats,
    Value<double>? amountFiat,
    Value<String>? fiatCurrency,
    Value<String?>? category,
    Value<String>? source,
    Value<bool>? isBitcoin,
    Value<String?>? notes,
    Value<String>? dedupHash,
    Value<DateTime>? createdAt,
    Value<String?>? recurringPeriod,
    Value<DateTime?>? recurringAnchorDate,
  }) {
    return TransactionsCompanion(
      id: id ?? this.id,
      walletId: walletId ?? this.walletId,
      date: date ?? this.date,
      description: description ?? this.description,
      amountSats: amountSats ?? this.amountSats,
      amountFiat: amountFiat ?? this.amountFiat,
      fiatCurrency: fiatCurrency ?? this.fiatCurrency,
      category: category ?? this.category,
      source: source ?? this.source,
      isBitcoin: isBitcoin ?? this.isBitcoin,
      notes: notes ?? this.notes,
      dedupHash: dedupHash ?? this.dedupHash,
      createdAt: createdAt ?? this.createdAt,
      recurringPeriod: recurringPeriod ?? this.recurringPeriod,
      recurringAnchorDate: recurringAnchorDate ?? this.recurringAnchorDate,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (walletId.present) {
      map['wallet_id'] = Variable<int>(walletId.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (amountSats.present) {
      map['amount_sats'] = Variable<int>(amountSats.value);
    }
    if (amountFiat.present) {
      map['amount_fiat'] = Variable<double>(amountFiat.value);
    }
    if (fiatCurrency.present) {
      map['fiat_currency'] = Variable<String>(fiatCurrency.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (isBitcoin.present) {
      map['is_bitcoin'] = Variable<bool>(isBitcoin.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (dedupHash.present) {
      map['dedup_hash'] = Variable<String>(dedupHash.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (recurringPeriod.present) {
      map['recurring_period'] = Variable<String>(recurringPeriod.value);
    }
    if (recurringAnchorDate.present) {
      map['recurring_anchor_date'] = Variable<DateTime>(
        recurringAnchorDate.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionsCompanion(')
          ..write('id: $id, ')
          ..write('walletId: $walletId, ')
          ..write('date: $date, ')
          ..write('description: $description, ')
          ..write('amountSats: $amountSats, ')
          ..write('amountFiat: $amountFiat, ')
          ..write('fiatCurrency: $fiatCurrency, ')
          ..write('category: $category, ')
          ..write('source: $source, ')
          ..write('isBitcoin: $isBitcoin, ')
          ..write('notes: $notes, ')
          ..write('dedupHash: $dedupHash, ')
          ..write('createdAt: $createdAt, ')
          ..write('recurringPeriod: $recurringPeriod, ')
          ..write('recurringAnchorDate: $recurringAnchorDate')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 60,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 7,
      maxTextLength: 7,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 50,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isSystemMeta = const VerificationMeta(
    'isSystem',
  );
  @override
  late final GeneratedColumn<bool> isSystem = GeneratedColumn<bool>(
    'is_system',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_system" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, color, icon, isSystem];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<Category> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    } else if (isInserting) {
      context.missing(_iconMeta);
    }
    if (data.containsKey('is_system')) {
      context.handle(
        _isSystemMeta,
        isSystem.isAcceptableOrUnknown(data['is_system']!, _isSystemMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      color:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}color'],
          )!,
      icon:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}icon'],
          )!,
      isSystem:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}is_system'],
          )!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class Category extends DataClass implements Insertable<Category> {
  final int id;
  final String name;
  final String color;
  final String icon;
  final bool isSystem;
  const Category({
    required this.id,
    required this.name,
    required this.color,
    required this.icon,
    required this.isSystem,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['color'] = Variable<String>(color);
    map['icon'] = Variable<String>(icon);
    map['is_system'] = Variable<bool>(isSystem);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      name: Value(name),
      color: Value(color),
      icon: Value(icon),
      isSystem: Value(isSystem),
    );
  }

  factory Category.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<String>(json['color']),
      icon: serializer.fromJson<String>(json['icon']),
      isSystem: serializer.fromJson<bool>(json['isSystem']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<String>(color),
      'icon': serializer.toJson<String>(icon),
      'isSystem': serializer.toJson<bool>(isSystem),
    };
  }

  Category copyWith({
    int? id,
    String? name,
    String? color,
    String? icon,
    bool? isSystem,
  }) => Category(
    id: id ?? this.id,
    name: name ?? this.name,
    color: color ?? this.color,
    icon: icon ?? this.icon,
    isSystem: isSystem ?? this.isSystem,
  );
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
      icon: data.icon.present ? data.icon.value : this.icon,
      isSystem: data.isSystem.present ? data.isSystem.value : this.isSystem,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('icon: $icon, ')
          ..write('isSystem: $isSystem')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, color, icon, isSystem);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.id == this.id &&
          other.name == this.name &&
          other.color == this.color &&
          other.icon == this.icon &&
          other.isSystem == this.isSystem);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> color;
  final Value<String> icon;
  final Value<bool> isSystem;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.icon = const Value.absent(),
    this.isSystem = const Value.absent(),
  });
  CategoriesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String color,
    required String icon,
    this.isSystem = const Value.absent(),
  }) : name = Value(name),
       color = Value(color),
       icon = Value(icon);
  static Insertable<Category> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? color,
    Expression<String>? icon,
    Expression<bool>? isSystem,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (icon != null) 'icon': icon,
      if (isSystem != null) 'is_system': isSystem,
    });
  }

  CategoriesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? color,
    Value<String>? icon,
    Value<bool>? isSystem,
  }) {
    return CategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      isSystem: isSystem ?? this.isSystem,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (isSystem.present) {
      map['is_system'] = Variable<bool>(isSystem.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('icon: $icon, ')
          ..write('isSystem: $isSystem')
          ..write(')'))
        .toString();
  }
}

class $BudgetsTable extends Budgets with TableInfo<$BudgetsTable, Budget> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BudgetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categories (id)',
    ),
  );
  static const VerificationMeta _amountFiatMeta = const VerificationMeta(
    'amountFiat',
  );
  @override
  late final GeneratedColumn<double> amountFiat = GeneratedColumn<double>(
    'amount_fiat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodMeta = const VerificationMeta('period');
  @override
  late final GeneratedColumn<String> period = GeneratedColumn<String>(
    'period',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 10,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    categoryId,
    amountFiat,
    period,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'budgets';
  @override
  VerificationContext validateIntegrity(
    Insertable<Budget> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('amount_fiat')) {
      context.handle(
        _amountFiatMeta,
        amountFiat.isAcceptableOrUnknown(data['amount_fiat']!, _amountFiatMeta),
      );
    } else if (isInserting) {
      context.missing(_amountFiatMeta);
    }
    if (data.containsKey('period')) {
      context.handle(
        _periodMeta,
        period.isAcceptableOrUnknown(data['period']!, _periodMeta),
      );
    } else if (isInserting) {
      context.missing(_periodMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Budget map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Budget(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      categoryId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}category_id'],
          )!,
      amountFiat:
          attachedDatabase.typeMapping.read(
            DriftSqlType.double,
            data['${effectivePrefix}amount_fiat'],
          )!,
      period:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}period'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
    );
  }

  @override
  $BudgetsTable createAlias(String alias) {
    return $BudgetsTable(attachedDatabase, alias);
  }
}

class Budget extends DataClass implements Insertable<Budget> {
  final int id;
  final int categoryId;
  final double amountFiat;
  final String period;
  final DateTime createdAt;
  const Budget({
    required this.id,
    required this.categoryId,
    required this.amountFiat,
    required this.period,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['category_id'] = Variable<int>(categoryId);
    map['amount_fiat'] = Variable<double>(amountFiat);
    map['period'] = Variable<String>(period);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  BudgetsCompanion toCompanion(bool nullToAbsent) {
    return BudgetsCompanion(
      id: Value(id),
      categoryId: Value(categoryId),
      amountFiat: Value(amountFiat),
      period: Value(period),
      createdAt: Value(createdAt),
    );
  }

  factory Budget.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Budget(
      id: serializer.fromJson<int>(json['id']),
      categoryId: serializer.fromJson<int>(json['categoryId']),
      amountFiat: serializer.fromJson<double>(json['amountFiat']),
      period: serializer.fromJson<String>(json['period']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'categoryId': serializer.toJson<int>(categoryId),
      'amountFiat': serializer.toJson<double>(amountFiat),
      'period': serializer.toJson<String>(period),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Budget copyWith({
    int? id,
    int? categoryId,
    double? amountFiat,
    String? period,
    DateTime? createdAt,
  }) => Budget(
    id: id ?? this.id,
    categoryId: categoryId ?? this.categoryId,
    amountFiat: amountFiat ?? this.amountFiat,
    period: period ?? this.period,
    createdAt: createdAt ?? this.createdAt,
  );
  Budget copyWithCompanion(BudgetsCompanion data) {
    return Budget(
      id: data.id.present ? data.id.value : this.id,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
      amountFiat:
          data.amountFiat.present ? data.amountFiat.value : this.amountFiat,
      period: data.period.present ? data.period.value : this.period,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Budget(')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('amountFiat: $amountFiat, ')
          ..write('period: $period, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, categoryId, amountFiat, period, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Budget &&
          other.id == this.id &&
          other.categoryId == this.categoryId &&
          other.amountFiat == this.amountFiat &&
          other.period == this.period &&
          other.createdAt == this.createdAt);
}

class BudgetsCompanion extends UpdateCompanion<Budget> {
  final Value<int> id;
  final Value<int> categoryId;
  final Value<double> amountFiat;
  final Value<String> period;
  final Value<DateTime> createdAt;
  const BudgetsCompanion({
    this.id = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.amountFiat = const Value.absent(),
    this.period = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  BudgetsCompanion.insert({
    this.id = const Value.absent(),
    required int categoryId,
    required double amountFiat,
    required String period,
    this.createdAt = const Value.absent(),
  }) : categoryId = Value(categoryId),
       amountFiat = Value(amountFiat),
       period = Value(period);
  static Insertable<Budget> custom({
    Expression<int>? id,
    Expression<int>? categoryId,
    Expression<double>? amountFiat,
    Expression<String>? period,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (categoryId != null) 'category_id': categoryId,
      if (amountFiat != null) 'amount_fiat': amountFiat,
      if (period != null) 'period': period,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  BudgetsCompanion copyWith({
    Value<int>? id,
    Value<int>? categoryId,
    Value<double>? amountFiat,
    Value<String>? period,
    Value<DateTime>? createdAt,
  }) {
    return BudgetsCompanion(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      amountFiat: amountFiat ?? this.amountFiat,
      period: period ?? this.period,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (amountFiat.present) {
      map['amount_fiat'] = Variable<double>(amountFiat.value);
    }
    if (period.present) {
      map['period'] = Variable<String>(period.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BudgetsCompanion(')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('amountFiat: $amountFiat, ')
          ..write('period: $period, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 100,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}key'],
          )!,
      value:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}value'],
          )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  const AppSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppSetting copyWith({String? key, String? value}) =>
      AppSetting(key: key ?? this.key, value: value ?? this.value);
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BtcPriceCacheTable extends BtcPriceCache
    with TableInfo<$BtcPriceCacheTable, BtcPriceCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BtcPriceCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _priceUsdMeta = const VerificationMeta(
    'priceUsd',
  );
  @override
  late final GeneratedColumn<double> priceUsd = GeneratedColumn<double>(
    'price_usd',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, priceUsd, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'btc_price_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<BtcPriceCacheData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('price_usd')) {
      context.handle(
        _priceUsdMeta,
        priceUsd.isAcceptableOrUnknown(data['price_usd']!, _priceUsdMeta),
      );
    } else if (isInserting) {
      context.missing(_priceUsdMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BtcPriceCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BtcPriceCacheData(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      priceUsd:
          attachedDatabase.typeMapping.read(
            DriftSqlType.double,
            data['${effectivePrefix}price_usd'],
          )!,
      fetchedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}fetched_at'],
          )!,
    );
  }

  @override
  $BtcPriceCacheTable createAlias(String alias) {
    return $BtcPriceCacheTable(attachedDatabase, alias);
  }
}

class BtcPriceCacheData extends DataClass
    implements Insertable<BtcPriceCacheData> {
  final int id;
  final double priceUsd;
  final DateTime fetchedAt;
  const BtcPriceCacheData({
    required this.id,
    required this.priceUsd,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['price_usd'] = Variable<double>(priceUsd);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  BtcPriceCacheCompanion toCompanion(bool nullToAbsent) {
    return BtcPriceCacheCompanion(
      id: Value(id),
      priceUsd: Value(priceUsd),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory BtcPriceCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BtcPriceCacheData(
      id: serializer.fromJson<int>(json['id']),
      priceUsd: serializer.fromJson<double>(json['priceUsd']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'priceUsd': serializer.toJson<double>(priceUsd),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  BtcPriceCacheData copyWith({
    int? id,
    double? priceUsd,
    DateTime? fetchedAt,
  }) => BtcPriceCacheData(
    id: id ?? this.id,
    priceUsd: priceUsd ?? this.priceUsd,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  BtcPriceCacheData copyWithCompanion(BtcPriceCacheCompanion data) {
    return BtcPriceCacheData(
      id: data.id.present ? data.id.value : this.id,
      priceUsd: data.priceUsd.present ? data.priceUsd.value : this.priceUsd,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BtcPriceCacheData(')
          ..write('id: $id, ')
          ..write('priceUsd: $priceUsd, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, priceUsd, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BtcPriceCacheData &&
          other.id == this.id &&
          other.priceUsd == this.priceUsd &&
          other.fetchedAt == this.fetchedAt);
}

class BtcPriceCacheCompanion extends UpdateCompanion<BtcPriceCacheData> {
  final Value<int> id;
  final Value<double> priceUsd;
  final Value<DateTime> fetchedAt;
  const BtcPriceCacheCompanion({
    this.id = const Value.absent(),
    this.priceUsd = const Value.absent(),
    this.fetchedAt = const Value.absent(),
  });
  BtcPriceCacheCompanion.insert({
    this.id = const Value.absent(),
    required double priceUsd,
    required DateTime fetchedAt,
  }) : priceUsd = Value(priceUsd),
       fetchedAt = Value(fetchedAt);
  static Insertable<BtcPriceCacheData> custom({
    Expression<int>? id,
    Expression<double>? priceUsd,
    Expression<DateTime>? fetchedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (priceUsd != null) 'price_usd': priceUsd,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
    });
  }

  BtcPriceCacheCompanion copyWith({
    Value<int>? id,
    Value<double>? priceUsd,
    Value<DateTime>? fetchedAt,
  }) {
    return BtcPriceCacheCompanion(
      id: id ?? this.id,
      priceUsd: priceUsd ?? this.priceUsd,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (priceUsd.present) {
      map['price_usd'] = Variable<double>(priceUsd.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BtcPriceCacheCompanion(')
          ..write('id: $id, ')
          ..write('priceUsd: $priceUsd, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }
}

class $BtcPriceHistoryTable extends BtcPriceHistory
    with TableInfo<$BtcPriceHistoryTable, BtcPriceHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BtcPriceHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<double> price = GeneratedColumn<double>(
    'price',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [date, currency, price];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'btc_price_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<BtcPriceHistoryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('price')) {
      context.handle(
        _priceMeta,
        price.isAcceptableOrUnknown(data['price']!, _priceMeta),
      );
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {date, currency};
  @override
  BtcPriceHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BtcPriceHistoryData(
      date:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}date'],
          )!,
      currency:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}currency'],
          )!,
      price:
          attachedDatabase.typeMapping.read(
            DriftSqlType.double,
            data['${effectivePrefix}price'],
          )!,
    );
  }

  @override
  $BtcPriceHistoryTable createAlias(String alias) {
    return $BtcPriceHistoryTable(attachedDatabase, alias);
  }
}

class BtcPriceHistoryData extends DataClass
    implements Insertable<BtcPriceHistoryData> {
  /// ISO date string 'YYYY-MM-DD'.
  final String date;

  /// ISO 4217 currency code, uppercased e.g. 'USD'.
  final String currency;

  /// BTC price in [currency] on [date].
  final double price;
  const BtcPriceHistoryData({
    required this.date,
    required this.currency,
    required this.price,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['date'] = Variable<String>(date);
    map['currency'] = Variable<String>(currency);
    map['price'] = Variable<double>(price);
    return map;
  }

  BtcPriceHistoryCompanion toCompanion(bool nullToAbsent) {
    return BtcPriceHistoryCompanion(
      date: Value(date),
      currency: Value(currency),
      price: Value(price),
    );
  }

  factory BtcPriceHistoryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BtcPriceHistoryData(
      date: serializer.fromJson<String>(json['date']),
      currency: serializer.fromJson<String>(json['currency']),
      price: serializer.fromJson<double>(json['price']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'date': serializer.toJson<String>(date),
      'currency': serializer.toJson<String>(currency),
      'price': serializer.toJson<double>(price),
    };
  }

  BtcPriceHistoryData copyWith({
    String? date,
    String? currency,
    double? price,
  }) => BtcPriceHistoryData(
    date: date ?? this.date,
    currency: currency ?? this.currency,
    price: price ?? this.price,
  );
  BtcPriceHistoryData copyWithCompanion(BtcPriceHistoryCompanion data) {
    return BtcPriceHistoryData(
      date: data.date.present ? data.date.value : this.date,
      currency: data.currency.present ? data.currency.value : this.currency,
      price: data.price.present ? data.price.value : this.price,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BtcPriceHistoryData(')
          ..write('date: $date, ')
          ..write('currency: $currency, ')
          ..write('price: $price')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(date, currency, price);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BtcPriceHistoryData &&
          other.date == this.date &&
          other.currency == this.currency &&
          other.price == this.price);
}

class BtcPriceHistoryCompanion extends UpdateCompanion<BtcPriceHistoryData> {
  final Value<String> date;
  final Value<String> currency;
  final Value<double> price;
  final Value<int> rowid;
  const BtcPriceHistoryCompanion({
    this.date = const Value.absent(),
    this.currency = const Value.absent(),
    this.price = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BtcPriceHistoryCompanion.insert({
    required String date,
    required String currency,
    required double price,
    this.rowid = const Value.absent(),
  }) : date = Value(date),
       currency = Value(currency),
       price = Value(price);
  static Insertable<BtcPriceHistoryData> custom({
    Expression<String>? date,
    Expression<String>? currency,
    Expression<double>? price,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (date != null) 'date': date,
      if (currency != null) 'currency': currency,
      if (price != null) 'price': price,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BtcPriceHistoryCompanion copyWith({
    Value<String>? date,
    Value<String>? currency,
    Value<double>? price,
    Value<int>? rowid,
  }) {
    return BtcPriceHistoryCompanion(
      date: date ?? this.date,
      currency: currency ?? this.currency,
      price: price ?? this.price,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (price.present) {
      map['price'] = Variable<double>(price.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BtcPriceHistoryCompanion(')
          ..write('date: $date, ')
          ..write('currency: $currency, ')
          ..write('price: $price, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AiConversationsTable extends AiConversations
    with TableInfo<$AiConversationsTable, AiConversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _promptMeta = const VerificationMeta('prompt');
  @override
  late final GeneratedColumn<String> prompt = GeneratedColumn<String>(
    'prompt',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _responseMeta = const VerificationMeta(
    'response',
  );
  @override
  late final GeneratedColumn<String> response = GeneratedColumn<String>(
    'response',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 100,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    prompt,
    response,
    model,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<AiConversation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('prompt')) {
      context.handle(
        _promptMeta,
        prompt.isAcceptableOrUnknown(data['prompt']!, _promptMeta),
      );
    } else if (isInserting) {
      context.missing(_promptMeta);
    }
    if (data.containsKey('response')) {
      context.handle(
        _responseMeta,
        response.isAcceptableOrUnknown(data['response']!, _responseMeta),
      );
    } else if (isInserting) {
      context.missing(_responseMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiConversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiConversation(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      prompt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}prompt'],
          )!,
      response:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}response'],
          )!,
      model:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}model'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
    );
  }

  @override
  $AiConversationsTable createAlias(String alias) {
    return $AiConversationsTable(attachedDatabase, alias);
  }
}

class AiConversation extends DataClass implements Insertable<AiConversation> {
  final int id;
  final String prompt;
  final String response;
  final String model;
  final DateTime createdAt;
  const AiConversation({
    required this.id,
    required this.prompt,
    required this.response,
    required this.model,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['prompt'] = Variable<String>(prompt);
    map['response'] = Variable<String>(response);
    map['model'] = Variable<String>(model);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  AiConversationsCompanion toCompanion(bool nullToAbsent) {
    return AiConversationsCompanion(
      id: Value(id),
      prompt: Value(prompt),
      response: Value(response),
      model: Value(model),
      createdAt: Value(createdAt),
    );
  }

  factory AiConversation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiConversation(
      id: serializer.fromJson<int>(json['id']),
      prompt: serializer.fromJson<String>(json['prompt']),
      response: serializer.fromJson<String>(json['response']),
      model: serializer.fromJson<String>(json['model']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'prompt': serializer.toJson<String>(prompt),
      'response': serializer.toJson<String>(response),
      'model': serializer.toJson<String>(model),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  AiConversation copyWith({
    int? id,
    String? prompt,
    String? response,
    String? model,
    DateTime? createdAt,
  }) => AiConversation(
    id: id ?? this.id,
    prompt: prompt ?? this.prompt,
    response: response ?? this.response,
    model: model ?? this.model,
    createdAt: createdAt ?? this.createdAt,
  );
  AiConversation copyWithCompanion(AiConversationsCompanion data) {
    return AiConversation(
      id: data.id.present ? data.id.value : this.id,
      prompt: data.prompt.present ? data.prompt.value : this.prompt,
      response: data.response.present ? data.response.value : this.response,
      model: data.model.present ? data.model.value : this.model,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiConversation(')
          ..write('id: $id, ')
          ..write('prompt: $prompt, ')
          ..write('response: $response, ')
          ..write('model: $model, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, prompt, response, model, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiConversation &&
          other.id == this.id &&
          other.prompt == this.prompt &&
          other.response == this.response &&
          other.model == this.model &&
          other.createdAt == this.createdAt);
}

class AiConversationsCompanion extends UpdateCompanion<AiConversation> {
  final Value<int> id;
  final Value<String> prompt;
  final Value<String> response;
  final Value<String> model;
  final Value<DateTime> createdAt;
  const AiConversationsCompanion({
    this.id = const Value.absent(),
    this.prompt = const Value.absent(),
    this.response = const Value.absent(),
    this.model = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  AiConversationsCompanion.insert({
    this.id = const Value.absent(),
    required String prompt,
    required String response,
    required String model,
    this.createdAt = const Value.absent(),
  }) : prompt = Value(prompt),
       response = Value(response),
       model = Value(model);
  static Insertable<AiConversation> custom({
    Expression<int>? id,
    Expression<String>? prompt,
    Expression<String>? response,
    Expression<String>? model,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (prompt != null) 'prompt': prompt,
      if (response != null) 'response': response,
      if (model != null) 'model': model,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  AiConversationsCompanion copyWith({
    Value<int>? id,
    Value<String>? prompt,
    Value<String>? response,
    Value<String>? model,
    Value<DateTime>? createdAt,
  }) {
    return AiConversationsCompanion(
      id: id ?? this.id,
      prompt: prompt ?? this.prompt,
      response: response ?? this.response,
      model: model ?? this.model,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (prompt.present) {
      map['prompt'] = Variable<String>(prompt.value);
    }
    if (response.present) {
      map['response'] = Variable<String>(response.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiConversationsCompanion(')
          ..write('id: $id, ')
          ..write('prompt: $prompt, ')
          ..write('response: $response, ')
          ..write('model: $model, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ImportSourcesTable extends ImportSources
    with TableInfo<$ImportSourcesTable, ImportSource> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImportSourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _columnMappingMeta = const VerificationMeta(
    'columnMapping',
  );
  @override
  late final GeneratedColumn<String> columnMapping = GeneratedColumn<String>(
    'column_mapping',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    type,
    currency,
    columnMapping,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'import_sources';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImportSource> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('column_mapping')) {
      context.handle(
        _columnMappingMeta,
        columnMapping.isAcceptableOrUnknown(
          data['column_mapping']!,
          _columnMappingMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ImportSource map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImportSource(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      type:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}type'],
          )!,
      currency:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}currency'],
          )!,
      columnMapping: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}column_mapping'],
      ),
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
    );
  }

  @override
  $ImportSourcesTable createAlias(String alias) {
    return $ImportSourcesTable(attachedDatabase, alias);
  }
}

class ImportSource extends DataClass implements Insertable<ImportSource> {
  final int id;
  final String name;
  final String type;
  final String currency;
  final String? columnMapping;
  final DateTime createdAt;
  const ImportSource({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    this.columnMapping,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    map['currency'] = Variable<String>(currency);
    if (!nullToAbsent || columnMapping != null) {
      map['column_mapping'] = Variable<String>(columnMapping);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ImportSourcesCompanion toCompanion(bool nullToAbsent) {
    return ImportSourcesCompanion(
      id: Value(id),
      name: Value(name),
      type: Value(type),
      currency: Value(currency),
      columnMapping:
          columnMapping == null && nullToAbsent
              ? const Value.absent()
              : Value(columnMapping),
      createdAt: Value(createdAt),
    );
  }

  factory ImportSource.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImportSource(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      currency: serializer.fromJson<String>(json['currency']),
      columnMapping: serializer.fromJson<String?>(json['columnMapping']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'currency': serializer.toJson<String>(currency),
      'columnMapping': serializer.toJson<String?>(columnMapping),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ImportSource copyWith({
    int? id,
    String? name,
    String? type,
    String? currency,
    Value<String?> columnMapping = const Value.absent(),
    DateTime? createdAt,
  }) => ImportSource(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    currency: currency ?? this.currency,
    columnMapping:
        columnMapping.present ? columnMapping.value : this.columnMapping,
    createdAt: createdAt ?? this.createdAt,
  );
  ImportSource copyWithCompanion(ImportSourcesCompanion data) {
    return ImportSource(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      currency: data.currency.present ? data.currency.value : this.currency,
      columnMapping:
          data.columnMapping.present
              ? data.columnMapping.value
              : this.columnMapping,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImportSource(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('currency: $currency, ')
          ..write('columnMapping: $columnMapping, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, type, currency, columnMapping, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportSource &&
          other.id == this.id &&
          other.name == this.name &&
          other.type == this.type &&
          other.currency == this.currency &&
          other.columnMapping == this.columnMapping &&
          other.createdAt == this.createdAt);
}

class ImportSourcesCompanion extends UpdateCompanion<ImportSource> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> type;
  final Value<String> currency;
  final Value<String?> columnMapping;
  final Value<DateTime> createdAt;
  const ImportSourcesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.currency = const Value.absent(),
    this.columnMapping = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ImportSourcesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String type,
    required String currency,
    this.columnMapping = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : name = Value(name),
       type = Value(type),
       currency = Value(currency);
  static Insertable<ImportSource> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? type,
    Expression<String>? currency,
    Expression<String>? columnMapping,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (currency != null) 'currency': currency,
      if (columnMapping != null) 'column_mapping': columnMapping,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ImportSourcesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? type,
    Value<String>? currency,
    Value<String?>? columnMapping,
    Value<DateTime>? createdAt,
  }) {
    return ImportSourcesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      currency: currency ?? this.currency,
      columnMapping: columnMapping ?? this.columnMapping,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (columnMapping.present) {
      map['column_mapping'] = Variable<String>(columnMapping.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportSourcesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('currency: $currency, ')
          ..write('columnMapping: $columnMapping, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ImportedTransactionsTable extends ImportedTransactions
    with TableInfo<$ImportedTransactionsTable, ImportedTransaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImportedTransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<int> sourceId = GeneratedColumn<int>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES import_sources (id)',
    ),
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountCentsMeta = const VerificationMeta(
    'amountCents',
  );
  @override
  late final GeneratedColumn<int> amountCents = GeneratedColumn<int>(
    'amount_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawDescriptionMeta = const VerificationMeta(
    'rawDescription',
  );
  @override
  late final GeneratedColumn<String> rawDescription = GeneratedColumn<String>(
    'raw_description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _importHashMeta = const VerificationMeta(
    'importHash',
  );
  @override
  late final GeneratedColumn<String> importHash = GeneratedColumn<String>(
    'import_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sourceId,
    date,
    amountCents,
    direction,
    description,
    category,
    currency,
    rawDescription,
    importHash,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'imported_transactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImportedTransaction> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('amount_cents')) {
      context.handle(
        _amountCentsMeta,
        amountCents.isAcceptableOrUnknown(
          data['amount_cents']!,
          _amountCentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountCentsMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('raw_description')) {
      context.handle(
        _rawDescriptionMeta,
        rawDescription.isAcceptableOrUnknown(
          data['raw_description']!,
          _rawDescriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_rawDescriptionMeta);
    }
    if (data.containsKey('import_hash')) {
      context.handle(
        _importHashMeta,
        importHash.isAcceptableOrUnknown(data['import_hash']!, _importHashMeta),
      );
    } else if (isInserting) {
      context.missing(_importHashMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ImportedTransaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImportedTransaction(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      sourceId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}source_id'],
          )!,
      date:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}date'],
          )!,
      amountCents:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}amount_cents'],
          )!,
      direction:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}direction'],
          )!,
      description:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}description'],
          )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
      currency:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}currency'],
          )!,
      rawDescription:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}raw_description'],
          )!,
      importHash:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}import_hash'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
    );
  }

  @override
  $ImportedTransactionsTable createAlias(String alias) {
    return $ImportedTransactionsTable(attachedDatabase, alias);
  }
}

class ImportedTransaction extends DataClass
    implements Insertable<ImportedTransaction> {
  final int id;
  final int sourceId;
  final DateTime date;
  final int amountCents;
  final String direction;
  final String description;
  final String? category;
  final String currency;
  final String rawDescription;
  final String importHash;
  final DateTime createdAt;
  const ImportedTransaction({
    required this.id,
    required this.sourceId,
    required this.date,
    required this.amountCents,
    required this.direction,
    required this.description,
    this.category,
    required this.currency,
    required this.rawDescription,
    required this.importHash,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['source_id'] = Variable<int>(sourceId);
    map['date'] = Variable<DateTime>(date);
    map['amount_cents'] = Variable<int>(amountCents);
    map['direction'] = Variable<String>(direction);
    map['description'] = Variable<String>(description);
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    map['currency'] = Variable<String>(currency);
    map['raw_description'] = Variable<String>(rawDescription);
    map['import_hash'] = Variable<String>(importHash);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ImportedTransactionsCompanion toCompanion(bool nullToAbsent) {
    return ImportedTransactionsCompanion(
      id: Value(id),
      sourceId: Value(sourceId),
      date: Value(date),
      amountCents: Value(amountCents),
      direction: Value(direction),
      description: Value(description),
      category:
          category == null && nullToAbsent
              ? const Value.absent()
              : Value(category),
      currency: Value(currency),
      rawDescription: Value(rawDescription),
      importHash: Value(importHash),
      createdAt: Value(createdAt),
    );
  }

  factory ImportedTransaction.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImportedTransaction(
      id: serializer.fromJson<int>(json['id']),
      sourceId: serializer.fromJson<int>(json['sourceId']),
      date: serializer.fromJson<DateTime>(json['date']),
      amountCents: serializer.fromJson<int>(json['amountCents']),
      direction: serializer.fromJson<String>(json['direction']),
      description: serializer.fromJson<String>(json['description']),
      category: serializer.fromJson<String?>(json['category']),
      currency: serializer.fromJson<String>(json['currency']),
      rawDescription: serializer.fromJson<String>(json['rawDescription']),
      importHash: serializer.fromJson<String>(json['importHash']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sourceId': serializer.toJson<int>(sourceId),
      'date': serializer.toJson<DateTime>(date),
      'amountCents': serializer.toJson<int>(amountCents),
      'direction': serializer.toJson<String>(direction),
      'description': serializer.toJson<String>(description),
      'category': serializer.toJson<String?>(category),
      'currency': serializer.toJson<String>(currency),
      'rawDescription': serializer.toJson<String>(rawDescription),
      'importHash': serializer.toJson<String>(importHash),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ImportedTransaction copyWith({
    int? id,
    int? sourceId,
    DateTime? date,
    int? amountCents,
    String? direction,
    String? description,
    Value<String?> category = const Value.absent(),
    String? currency,
    String? rawDescription,
    String? importHash,
    DateTime? createdAt,
  }) => ImportedTransaction(
    id: id ?? this.id,
    sourceId: sourceId ?? this.sourceId,
    date: date ?? this.date,
    amountCents: amountCents ?? this.amountCents,
    direction: direction ?? this.direction,
    description: description ?? this.description,
    category: category.present ? category.value : this.category,
    currency: currency ?? this.currency,
    rawDescription: rawDescription ?? this.rawDescription,
    importHash: importHash ?? this.importHash,
    createdAt: createdAt ?? this.createdAt,
  );
  ImportedTransaction copyWithCompanion(ImportedTransactionsCompanion data) {
    return ImportedTransaction(
      id: data.id.present ? data.id.value : this.id,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      date: data.date.present ? data.date.value : this.date,
      amountCents:
          data.amountCents.present ? data.amountCents.value : this.amountCents,
      direction: data.direction.present ? data.direction.value : this.direction,
      description:
          data.description.present ? data.description.value : this.description,
      category: data.category.present ? data.category.value : this.category,
      currency: data.currency.present ? data.currency.value : this.currency,
      rawDescription:
          data.rawDescription.present
              ? data.rawDescription.value
              : this.rawDescription,
      importHash:
          data.importHash.present ? data.importHash.value : this.importHash,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImportedTransaction(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('date: $date, ')
          ..write('amountCents: $amountCents, ')
          ..write('direction: $direction, ')
          ..write('description: $description, ')
          ..write('category: $category, ')
          ..write('currency: $currency, ')
          ..write('rawDescription: $rawDescription, ')
          ..write('importHash: $importHash, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sourceId,
    date,
    amountCents,
    direction,
    description,
    category,
    currency,
    rawDescription,
    importHash,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportedTransaction &&
          other.id == this.id &&
          other.sourceId == this.sourceId &&
          other.date == this.date &&
          other.amountCents == this.amountCents &&
          other.direction == this.direction &&
          other.description == this.description &&
          other.category == this.category &&
          other.currency == this.currency &&
          other.rawDescription == this.rawDescription &&
          other.importHash == this.importHash &&
          other.createdAt == this.createdAt);
}

class ImportedTransactionsCompanion
    extends UpdateCompanion<ImportedTransaction> {
  final Value<int> id;
  final Value<int> sourceId;
  final Value<DateTime> date;
  final Value<int> amountCents;
  final Value<String> direction;
  final Value<String> description;
  final Value<String?> category;
  final Value<String> currency;
  final Value<String> rawDescription;
  final Value<String> importHash;
  final Value<DateTime> createdAt;
  const ImportedTransactionsCompanion({
    this.id = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.date = const Value.absent(),
    this.amountCents = const Value.absent(),
    this.direction = const Value.absent(),
    this.description = const Value.absent(),
    this.category = const Value.absent(),
    this.currency = const Value.absent(),
    this.rawDescription = const Value.absent(),
    this.importHash = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ImportedTransactionsCompanion.insert({
    this.id = const Value.absent(),
    required int sourceId,
    required DateTime date,
    required int amountCents,
    required String direction,
    required String description,
    this.category = const Value.absent(),
    required String currency,
    required String rawDescription,
    required String importHash,
    this.createdAt = const Value.absent(),
  }) : sourceId = Value(sourceId),
       date = Value(date),
       amountCents = Value(amountCents),
       direction = Value(direction),
       description = Value(description),
       currency = Value(currency),
       rawDescription = Value(rawDescription),
       importHash = Value(importHash);
  static Insertable<ImportedTransaction> custom({
    Expression<int>? id,
    Expression<int>? sourceId,
    Expression<DateTime>? date,
    Expression<int>? amountCents,
    Expression<String>? direction,
    Expression<String>? description,
    Expression<String>? category,
    Expression<String>? currency,
    Expression<String>? rawDescription,
    Expression<String>? importHash,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceId != null) 'source_id': sourceId,
      if (date != null) 'date': date,
      if (amountCents != null) 'amount_cents': amountCents,
      if (direction != null) 'direction': direction,
      if (description != null) 'description': description,
      if (category != null) 'category': category,
      if (currency != null) 'currency': currency,
      if (rawDescription != null) 'raw_description': rawDescription,
      if (importHash != null) 'import_hash': importHash,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ImportedTransactionsCompanion copyWith({
    Value<int>? id,
    Value<int>? sourceId,
    Value<DateTime>? date,
    Value<int>? amountCents,
    Value<String>? direction,
    Value<String>? description,
    Value<String?>? category,
    Value<String>? currency,
    Value<String>? rawDescription,
    Value<String>? importHash,
    Value<DateTime>? createdAt,
  }) {
    return ImportedTransactionsCompanion(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      date: date ?? this.date,
      amountCents: amountCents ?? this.amountCents,
      direction: direction ?? this.direction,
      description: description ?? this.description,
      category: category ?? this.category,
      currency: currency ?? this.currency,
      rawDescription: rawDescription ?? this.rawDescription,
      importHash: importHash ?? this.importHash,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<int>(sourceId.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (amountCents.present) {
      map['amount_cents'] = Variable<int>(amountCents.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (rawDescription.present) {
      map['raw_description'] = Variable<String>(rawDescription.value);
    }
    if (importHash.present) {
      map['import_hash'] = Variable<String>(importHash.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportedTransactionsCompanion(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('date: $date, ')
          ..write('amountCents: $amountCents, ')
          ..write('direction: $direction, ')
          ..write('description: $description, ')
          ..write('category: $category, ')
          ..write('currency: $currency, ')
          ..write('rawDescription: $rawDescription, ')
          ..write('importHash: $importHash, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $WalletsTable wallets = $WalletsTable(this);
  late final $TransactionsTable transactions = $TransactionsTable(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $BudgetsTable budgets = $BudgetsTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $BtcPriceCacheTable btcPriceCache = $BtcPriceCacheTable(this);
  late final $BtcPriceHistoryTable btcPriceHistory = $BtcPriceHistoryTable(
    this,
  );
  late final $AiConversationsTable aiConversations = $AiConversationsTable(
    this,
  );
  late final $ImportSourcesTable importSources = $ImportSourcesTable(this);
  late final $ImportedTransactionsTable importedTransactions =
      $ImportedTransactionsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    wallets,
    transactions,
    categories,
    budgets,
    appSettings,
    btcPriceCache,
    btcPriceHistory,
    aiConversations,
    importSources,
    importedTransactions,
  ];
}

typedef $$WalletsTableCreateCompanionBuilder =
    WalletsCompanion Function({
      Value<int> id,
      required String label,
      required String type,
      Value<String?> xpub,
      required String color,
      Value<DateTime> createdAt,
    });
typedef $$WalletsTableUpdateCompanionBuilder =
    WalletsCompanion Function({
      Value<int> id,
      Value<String> label,
      Value<String> type,
      Value<String?> xpub,
      Value<String> color,
      Value<DateTime> createdAt,
    });

final class $$WalletsTableReferences
    extends BaseReferences<_$AppDatabase, $WalletsTable, Wallet> {
  $$WalletsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TransactionsTable, List<Transaction>>
  _transactionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.transactions,
    aliasName: $_aliasNameGenerator(db.wallets.id, db.transactions.walletId),
  );

  $$TransactionsTableProcessedTableManager get transactionsRefs {
    final manager = $$TransactionsTableTableManager(
      $_db,
      $_db.transactions,
    ).filter((f) => f.walletId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_transactionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$WalletsTableFilterComposer
    extends Composer<_$AppDatabase, $WalletsTable> {
  $$WalletsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get xpub => $composableBuilder(
    column: $table.xpub,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> transactionsRefs(
    Expression<bool> Function($$TransactionsTableFilterComposer f) f,
  ) {
    final $$TransactionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.transactions,
      getReferencedColumn: (t) => t.walletId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TransactionsTableFilterComposer(
            $db: $db,
            $table: $db.transactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$WalletsTableOrderingComposer
    extends Composer<_$AppDatabase, $WalletsTable> {
  $$WalletsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get xpub => $composableBuilder(
    column: $table.xpub,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WalletsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WalletsTable> {
  $$WalletsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get xpub =>
      $composableBuilder(column: $table.xpub, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> transactionsRefs<T extends Object>(
    Expression<T> Function($$TransactionsTableAnnotationComposer a) f,
  ) {
    final $$TransactionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.transactions,
      getReferencedColumn: (t) => t.walletId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TransactionsTableAnnotationComposer(
            $db: $db,
            $table: $db.transactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$WalletsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WalletsTable,
          Wallet,
          $$WalletsTableFilterComposer,
          $$WalletsTableOrderingComposer,
          $$WalletsTableAnnotationComposer,
          $$WalletsTableCreateCompanionBuilder,
          $$WalletsTableUpdateCompanionBuilder,
          (Wallet, $$WalletsTableReferences),
          Wallet,
          PrefetchHooks Function({bool transactionsRefs})
        > {
  $$WalletsTableTableManager(_$AppDatabase db, $WalletsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$WalletsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$WalletsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$WalletsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> xpub = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => WalletsCompanion(
                id: id,
                label: label,
                type: type,
                xpub: xpub,
                color: color,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String label,
                required String type,
                Value<String?> xpub = const Value.absent(),
                required String color,
                Value<DateTime> createdAt = const Value.absent(),
              }) => WalletsCompanion.insert(
                id: id,
                label: label,
                type: type,
                xpub: xpub,
                color: color,
                createdAt: createdAt,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$WalletsTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({transactionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (transactionsRefs) db.transactions],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (transactionsRefs)
                    await $_getPrefetchedData<
                      Wallet,
                      $WalletsTable,
                      Transaction
                    >(
                      currentTable: table,
                      referencedTable: $$WalletsTableReferences
                          ._transactionsRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$WalletsTableReferences(
                                db,
                                table,
                                p0,
                              ).transactionsRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.walletId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$WalletsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WalletsTable,
      Wallet,
      $$WalletsTableFilterComposer,
      $$WalletsTableOrderingComposer,
      $$WalletsTableAnnotationComposer,
      $$WalletsTableCreateCompanionBuilder,
      $$WalletsTableUpdateCompanionBuilder,
      (Wallet, $$WalletsTableReferences),
      Wallet,
      PrefetchHooks Function({bool transactionsRefs})
    >;
typedef $$TransactionsTableCreateCompanionBuilder =
    TransactionsCompanion Function({
      Value<int> id,
      required int walletId,
      required DateTime date,
      required String description,
      required int amountSats,
      required double amountFiat,
      required String fiatCurrency,
      Value<String?> category,
      required String source,
      Value<bool> isBitcoin,
      Value<String?> notes,
      required String dedupHash,
      Value<DateTime> createdAt,
      Value<String?> recurringPeriod,
      Value<DateTime?> recurringAnchorDate,
    });
typedef $$TransactionsTableUpdateCompanionBuilder =
    TransactionsCompanion Function({
      Value<int> id,
      Value<int> walletId,
      Value<DateTime> date,
      Value<String> description,
      Value<int> amountSats,
      Value<double> amountFiat,
      Value<String> fiatCurrency,
      Value<String?> category,
      Value<String> source,
      Value<bool> isBitcoin,
      Value<String?> notes,
      Value<String> dedupHash,
      Value<DateTime> createdAt,
      Value<String?> recurringPeriod,
      Value<DateTime?> recurringAnchorDate,
    });

final class $$TransactionsTableReferences
    extends BaseReferences<_$AppDatabase, $TransactionsTable, Transaction> {
  $$TransactionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $WalletsTable _walletIdTable(_$AppDatabase db) =>
      db.wallets.createAlias(
        $_aliasNameGenerator(db.transactions.walletId, db.wallets.id),
      );

  $$WalletsTableProcessedTableManager get walletId {
    final $_column = $_itemColumn<int>('wallet_id')!;

    final manager = $$WalletsTableTableManager(
      $_db,
      $_db.wallets,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_walletIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TransactionsTableFilterComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountSats => $composableBuilder(
    column: $table.amountSats,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amountFiat => $composableBuilder(
    column: $table.amountFiat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fiatCurrency => $composableBuilder(
    column: $table.fiatCurrency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isBitcoin => $composableBuilder(
    column: $table.isBitcoin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dedupHash => $composableBuilder(
    column: $table.dedupHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recurringPeriod => $composableBuilder(
    column: $table.recurringPeriod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get recurringAnchorDate => $composableBuilder(
    column: $table.recurringAnchorDate,
    builder: (column) => ColumnFilters(column),
  );

  $$WalletsTableFilterComposer get walletId {
    final $$WalletsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.walletId,
      referencedTable: $db.wallets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WalletsTableFilterComposer(
            $db: $db,
            $table: $db.wallets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TransactionsTableOrderingComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountSats => $composableBuilder(
    column: $table.amountSats,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amountFiat => $composableBuilder(
    column: $table.amountFiat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fiatCurrency => $composableBuilder(
    column: $table.fiatCurrency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isBitcoin => $composableBuilder(
    column: $table.isBitcoin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dedupHash => $composableBuilder(
    column: $table.dedupHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recurringPeriod => $composableBuilder(
    column: $table.recurringPeriod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get recurringAnchorDate => $composableBuilder(
    column: $table.recurringAnchorDate,
    builder: (column) => ColumnOrderings(column),
  );

  $$WalletsTableOrderingComposer get walletId {
    final $$WalletsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.walletId,
      referencedTable: $db.wallets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WalletsTableOrderingComposer(
            $db: $db,
            $table: $db.wallets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TransactionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amountSats => $composableBuilder(
    column: $table.amountSats,
    builder: (column) => column,
  );

  GeneratedColumn<double> get amountFiat => $composableBuilder(
    column: $table.amountFiat,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fiatCurrency => $composableBuilder(
    column: $table.fiatCurrency,
    builder: (column) => column,
  );

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<bool> get isBitcoin =>
      $composableBuilder(column: $table.isBitcoin, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get dedupHash =>
      $composableBuilder(column: $table.dedupHash, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get recurringPeriod => $composableBuilder(
    column: $table.recurringPeriod,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get recurringAnchorDate => $composableBuilder(
    column: $table.recurringAnchorDate,
    builder: (column) => column,
  );

  $$WalletsTableAnnotationComposer get walletId {
    final $$WalletsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.walletId,
      referencedTable: $db.wallets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WalletsTableAnnotationComposer(
            $db: $db,
            $table: $db.wallets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TransactionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TransactionsTable,
          Transaction,
          $$TransactionsTableFilterComposer,
          $$TransactionsTableOrderingComposer,
          $$TransactionsTableAnnotationComposer,
          $$TransactionsTableCreateCompanionBuilder,
          $$TransactionsTableUpdateCompanionBuilder,
          (Transaction, $$TransactionsTableReferences),
          Transaction,
          PrefetchHooks Function({bool walletId})
        > {
  $$TransactionsTableTableManager(_$AppDatabase db, $TransactionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$TransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$TransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () =>
                  $$TransactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> walletId = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<int> amountSats = const Value.absent(),
                Value<double> amountFiat = const Value.absent(),
                Value<String> fiatCurrency = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<bool> isBitcoin = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> dedupHash = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> recurringPeriod = const Value.absent(),
                Value<DateTime?> recurringAnchorDate = const Value.absent(),
              }) => TransactionsCompanion(
                id: id,
                walletId: walletId,
                date: date,
                description: description,
                amountSats: amountSats,
                amountFiat: amountFiat,
                fiatCurrency: fiatCurrency,
                category: category,
                source: source,
                isBitcoin: isBitcoin,
                notes: notes,
                dedupHash: dedupHash,
                createdAt: createdAt,
                recurringPeriod: recurringPeriod,
                recurringAnchorDate: recurringAnchorDate,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int walletId,
                required DateTime date,
                required String description,
                required int amountSats,
                required double amountFiat,
                required String fiatCurrency,
                Value<String?> category = const Value.absent(),
                required String source,
                Value<bool> isBitcoin = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                required String dedupHash,
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> recurringPeriod = const Value.absent(),
                Value<DateTime?> recurringAnchorDate = const Value.absent(),
              }) => TransactionsCompanion.insert(
                id: id,
                walletId: walletId,
                date: date,
                description: description,
                amountSats: amountSats,
                amountFiat: amountFiat,
                fiatCurrency: fiatCurrency,
                category: category,
                source: source,
                isBitcoin: isBitcoin,
                notes: notes,
                dedupHash: dedupHash,
                createdAt: createdAt,
                recurringPeriod: recurringPeriod,
                recurringAnchorDate: recurringAnchorDate,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$TransactionsTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({walletId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                T extends TableManagerState<
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic
                >
              >(state) {
                if (walletId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.walletId,
                            referencedTable: $$TransactionsTableReferences
                                ._walletIdTable(db),
                            referencedColumn:
                                $$TransactionsTableReferences
                                    ._walletIdTable(db)
                                    .id,
                          )
                          as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TransactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TransactionsTable,
      Transaction,
      $$TransactionsTableFilterComposer,
      $$TransactionsTableOrderingComposer,
      $$TransactionsTableAnnotationComposer,
      $$TransactionsTableCreateCompanionBuilder,
      $$TransactionsTableUpdateCompanionBuilder,
      (Transaction, $$TransactionsTableReferences),
      Transaction,
      PrefetchHooks Function({bool walletId})
    >;
typedef $$CategoriesTableCreateCompanionBuilder =
    CategoriesCompanion Function({
      Value<int> id,
      required String name,
      required String color,
      required String icon,
      Value<bool> isSystem,
    });
typedef $$CategoriesTableUpdateCompanionBuilder =
    CategoriesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> color,
      Value<String> icon,
      Value<bool> isSystem,
    });

final class $$CategoriesTableReferences
    extends BaseReferences<_$AppDatabase, $CategoriesTable, Category> {
  $$CategoriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$BudgetsTable, List<Budget>> _budgetsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.budgets,
    aliasName: $_aliasNameGenerator(db.categories.id, db.budgets.categoryId),
  );

  $$BudgetsTableProcessedTableManager get budgetsRefs {
    final manager = $$BudgetsTableTableManager(
      $_db,
      $_db.budgets,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_budgetsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSystem => $composableBuilder(
    column: $table.isSystem,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> budgetsRefs(
    Expression<bool> Function($$BudgetsTableFilterComposer f) f,
  ) {
    final $$BudgetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.budgets,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BudgetsTableFilterComposer(
            $db: $db,
            $table: $db.budgets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSystem => $composableBuilder(
    column: $table.isSystem,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<bool> get isSystem =>
      $composableBuilder(column: $table.isSystem, builder: (column) => column);

  Expression<T> budgetsRefs<T extends Object>(
    Expression<T> Function($$BudgetsTableAnnotationComposer a) f,
  ) {
    final $$BudgetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.budgets,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BudgetsTableAnnotationComposer(
            $db: $db,
            $table: $db.budgets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoriesTable,
          Category,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (Category, $$CategoriesTableReferences),
          Category,
          PrefetchHooks Function({bool budgetsRefs})
        > {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<bool> isSystem = const Value.absent(),
              }) => CategoriesCompanion(
                id: id,
                name: name,
                color: color,
                icon: icon,
                isSystem: isSystem,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String color,
                required String icon,
                Value<bool> isSystem = const Value.absent(),
              }) => CategoriesCompanion.insert(
                id: id,
                name: name,
                color: color,
                icon: icon,
                isSystem: isSystem,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$CategoriesTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({budgetsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (budgetsRefs) db.budgets],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (budgetsRefs)
                    await $_getPrefetchedData<
                      Category,
                      $CategoriesTable,
                      Budget
                    >(
                      currentTable: table,
                      referencedTable: $$CategoriesTableReferences
                          ._budgetsRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$CategoriesTableReferences(
                                db,
                                table,
                                p0,
                              ).budgetsRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.categoryId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoriesTable,
      Category,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (Category, $$CategoriesTableReferences),
      Category,
      PrefetchHooks Function({bool budgetsRefs})
    >;
typedef $$BudgetsTableCreateCompanionBuilder =
    BudgetsCompanion Function({
      Value<int> id,
      required int categoryId,
      required double amountFiat,
      required String period,
      Value<DateTime> createdAt,
    });
typedef $$BudgetsTableUpdateCompanionBuilder =
    BudgetsCompanion Function({
      Value<int> id,
      Value<int> categoryId,
      Value<double> amountFiat,
      Value<String> period,
      Value<DateTime> createdAt,
    });

final class $$BudgetsTableReferences
    extends BaseReferences<_$AppDatabase, $BudgetsTable, Budget> {
  $$BudgetsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CategoriesTable _categoryIdTable(_$AppDatabase db) =>
      db.categories.createAlias(
        $_aliasNameGenerator(db.budgets.categoryId, db.categories.id),
      );

  $$CategoriesTableProcessedTableManager get categoryId {
    final $_column = $_itemColumn<int>('category_id')!;

    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BudgetsTableFilterComposer
    extends Composer<_$AppDatabase, $BudgetsTable> {
  $$BudgetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amountFiat => $composableBuilder(
    column: $table.amountFiat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get period => $composableBuilder(
    column: $table.period,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BudgetsTableOrderingComposer
    extends Composer<_$AppDatabase, $BudgetsTable> {
  $$BudgetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amountFiat => $composableBuilder(
    column: $table.amountFiat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get period => $composableBuilder(
    column: $table.period,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BudgetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BudgetsTable> {
  $$BudgetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get amountFiat => $composableBuilder(
    column: $table.amountFiat,
    builder: (column) => column,
  );

  GeneratedColumn<String> get period =>
      $composableBuilder(column: $table.period, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BudgetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BudgetsTable,
          Budget,
          $$BudgetsTableFilterComposer,
          $$BudgetsTableOrderingComposer,
          $$BudgetsTableAnnotationComposer,
          $$BudgetsTableCreateCompanionBuilder,
          $$BudgetsTableUpdateCompanionBuilder,
          (Budget, $$BudgetsTableReferences),
          Budget,
          PrefetchHooks Function({bool categoryId})
        > {
  $$BudgetsTableTableManager(_$AppDatabase db, $BudgetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$BudgetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$BudgetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$BudgetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> categoryId = const Value.absent(),
                Value<double> amountFiat = const Value.absent(),
                Value<String> period = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => BudgetsCompanion(
                id: id,
                categoryId: categoryId,
                amountFiat: amountFiat,
                period: period,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int categoryId,
                required double amountFiat,
                required String period,
                Value<DateTime> createdAt = const Value.absent(),
              }) => BudgetsCompanion.insert(
                id: id,
                categoryId: categoryId,
                amountFiat: amountFiat,
                period: period,
                createdAt: createdAt,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$BudgetsTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({categoryId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                T extends TableManagerState<
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic
                >
              >(state) {
                if (categoryId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.categoryId,
                            referencedTable: $$BudgetsTableReferences
                                ._categoryIdTable(db),
                            referencedColumn:
                                $$BudgetsTableReferences
                                    ._categoryIdTable(db)
                                    .id,
                          )
                          as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$BudgetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BudgetsTable,
      Budget,
      $$BudgetsTableFilterComposer,
      $$BudgetsTableOrderingComposer,
      $$BudgetsTableAnnotationComposer,
      $$BudgetsTableCreateCompanionBuilder,
      $$BudgetsTableUpdateCompanionBuilder,
      (Budget, $$BudgetsTableReferences),
      Budget,
      PrefetchHooks Function({bool categoryId})
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () =>
                  $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;
typedef $$BtcPriceCacheTableCreateCompanionBuilder =
    BtcPriceCacheCompanion Function({
      Value<int> id,
      required double priceUsd,
      required DateTime fetchedAt,
    });
typedef $$BtcPriceCacheTableUpdateCompanionBuilder =
    BtcPriceCacheCompanion Function({
      Value<int> id,
      Value<double> priceUsd,
      Value<DateTime> fetchedAt,
    });

class $$BtcPriceCacheTableFilterComposer
    extends Composer<_$AppDatabase, $BtcPriceCacheTable> {
  $$BtcPriceCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get priceUsd => $composableBuilder(
    column: $table.priceUsd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BtcPriceCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $BtcPriceCacheTable> {
  $$BtcPriceCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get priceUsd => $composableBuilder(
    column: $table.priceUsd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BtcPriceCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $BtcPriceCacheTable> {
  $$BtcPriceCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get priceUsd =>
      $composableBuilder(column: $table.priceUsd, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$BtcPriceCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BtcPriceCacheTable,
          BtcPriceCacheData,
          $$BtcPriceCacheTableFilterComposer,
          $$BtcPriceCacheTableOrderingComposer,
          $$BtcPriceCacheTableAnnotationComposer,
          $$BtcPriceCacheTableCreateCompanionBuilder,
          $$BtcPriceCacheTableUpdateCompanionBuilder,
          (
            BtcPriceCacheData,
            BaseReferences<
              _$AppDatabase,
              $BtcPriceCacheTable,
              BtcPriceCacheData
            >,
          ),
          BtcPriceCacheData,
          PrefetchHooks Function()
        > {
  $$BtcPriceCacheTableTableManager(_$AppDatabase db, $BtcPriceCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$BtcPriceCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () =>
                  $$BtcPriceCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$BtcPriceCacheTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<double> priceUsd = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
              }) => BtcPriceCacheCompanion(
                id: id,
                priceUsd: priceUsd,
                fetchedAt: fetchedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required double priceUsd,
                required DateTime fetchedAt,
              }) => BtcPriceCacheCompanion.insert(
                id: id,
                priceUsd: priceUsd,
                fetchedAt: fetchedAt,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BtcPriceCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BtcPriceCacheTable,
      BtcPriceCacheData,
      $$BtcPriceCacheTableFilterComposer,
      $$BtcPriceCacheTableOrderingComposer,
      $$BtcPriceCacheTableAnnotationComposer,
      $$BtcPriceCacheTableCreateCompanionBuilder,
      $$BtcPriceCacheTableUpdateCompanionBuilder,
      (
        BtcPriceCacheData,
        BaseReferences<_$AppDatabase, $BtcPriceCacheTable, BtcPriceCacheData>,
      ),
      BtcPriceCacheData,
      PrefetchHooks Function()
    >;
typedef $$BtcPriceHistoryTableCreateCompanionBuilder =
    BtcPriceHistoryCompanion Function({
      required String date,
      required String currency,
      required double price,
      Value<int> rowid,
    });
typedef $$BtcPriceHistoryTableUpdateCompanionBuilder =
    BtcPriceHistoryCompanion Function({
      Value<String> date,
      Value<String> currency,
      Value<double> price,
      Value<int> rowid,
    });

class $$BtcPriceHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $BtcPriceHistoryTable> {
  $$BtcPriceHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BtcPriceHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $BtcPriceHistoryTable> {
  $$BtcPriceHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BtcPriceHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $BtcPriceHistoryTable> {
  $$BtcPriceHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<double> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);
}

class $$BtcPriceHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BtcPriceHistoryTable,
          BtcPriceHistoryData,
          $$BtcPriceHistoryTableFilterComposer,
          $$BtcPriceHistoryTableOrderingComposer,
          $$BtcPriceHistoryTableAnnotationComposer,
          $$BtcPriceHistoryTableCreateCompanionBuilder,
          $$BtcPriceHistoryTableUpdateCompanionBuilder,
          (
            BtcPriceHistoryData,
            BaseReferences<
              _$AppDatabase,
              $BtcPriceHistoryTable,
              BtcPriceHistoryData
            >,
          ),
          BtcPriceHistoryData,
          PrefetchHooks Function()
        > {
  $$BtcPriceHistoryTableTableManager(
    _$AppDatabase db,
    $BtcPriceHistoryTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () =>
                  $$BtcPriceHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$BtcPriceHistoryTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$BtcPriceHistoryTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> date = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<double> price = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BtcPriceHistoryCompanion(
                date: date,
                currency: currency,
                price: price,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String date,
                required String currency,
                required double price,
                Value<int> rowid = const Value.absent(),
              }) => BtcPriceHistoryCompanion.insert(
                date: date,
                currency: currency,
                price: price,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BtcPriceHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BtcPriceHistoryTable,
      BtcPriceHistoryData,
      $$BtcPriceHistoryTableFilterComposer,
      $$BtcPriceHistoryTableOrderingComposer,
      $$BtcPriceHistoryTableAnnotationComposer,
      $$BtcPriceHistoryTableCreateCompanionBuilder,
      $$BtcPriceHistoryTableUpdateCompanionBuilder,
      (
        BtcPriceHistoryData,
        BaseReferences<
          _$AppDatabase,
          $BtcPriceHistoryTable,
          BtcPriceHistoryData
        >,
      ),
      BtcPriceHistoryData,
      PrefetchHooks Function()
    >;
typedef $$AiConversationsTableCreateCompanionBuilder =
    AiConversationsCompanion Function({
      Value<int> id,
      required String prompt,
      required String response,
      required String model,
      Value<DateTime> createdAt,
    });
typedef $$AiConversationsTableUpdateCompanionBuilder =
    AiConversationsCompanion Function({
      Value<int> id,
      Value<String> prompt,
      Value<String> response,
      Value<String> model,
      Value<DateTime> createdAt,
    });

class $$AiConversationsTableFilterComposer
    extends Composer<_$AppDatabase, $AiConversationsTable> {
  $$AiConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get prompt => $composableBuilder(
    column: $table.prompt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get response => $composableBuilder(
    column: $table.response,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AiConversationsTableOrderingComposer
    extends Composer<_$AppDatabase, $AiConversationsTable> {
  $$AiConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get prompt => $composableBuilder(
    column: $table.prompt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get response => $composableBuilder(
    column: $table.response,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AiConversationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiConversationsTable> {
  $$AiConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get prompt =>
      $composableBuilder(column: $table.prompt, builder: (column) => column);

  GeneratedColumn<String> get response =>
      $composableBuilder(column: $table.response, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$AiConversationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AiConversationsTable,
          AiConversation,
          $$AiConversationsTableFilterComposer,
          $$AiConversationsTableOrderingComposer,
          $$AiConversationsTableAnnotationComposer,
          $$AiConversationsTableCreateCompanionBuilder,
          $$AiConversationsTableUpdateCompanionBuilder,
          (
            AiConversation,
            BaseReferences<
              _$AppDatabase,
              $AiConversationsTable,
              AiConversation
            >,
          ),
          AiConversation,
          PrefetchHooks Function()
        > {
  $$AiConversationsTableTableManager(
    _$AppDatabase db,
    $AiConversationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () =>
                  $$AiConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$AiConversationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$AiConversationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> prompt = const Value.absent(),
                Value<String> response = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => AiConversationsCompanion(
                id: id,
                prompt: prompt,
                response: response,
                model: model,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String prompt,
                required String response,
                required String model,
                Value<DateTime> createdAt = const Value.absent(),
              }) => AiConversationsCompanion.insert(
                id: id,
                prompt: prompt,
                response: response,
                model: model,
                createdAt: createdAt,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AiConversationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AiConversationsTable,
      AiConversation,
      $$AiConversationsTableFilterComposer,
      $$AiConversationsTableOrderingComposer,
      $$AiConversationsTableAnnotationComposer,
      $$AiConversationsTableCreateCompanionBuilder,
      $$AiConversationsTableUpdateCompanionBuilder,
      (
        AiConversation,
        BaseReferences<_$AppDatabase, $AiConversationsTable, AiConversation>,
      ),
      AiConversation,
      PrefetchHooks Function()
    >;
typedef $$ImportSourcesTableCreateCompanionBuilder =
    ImportSourcesCompanion Function({
      Value<int> id,
      required String name,
      required String type,
      required String currency,
      Value<String?> columnMapping,
      Value<DateTime> createdAt,
    });
typedef $$ImportSourcesTableUpdateCompanionBuilder =
    ImportSourcesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> type,
      Value<String> currency,
      Value<String?> columnMapping,
      Value<DateTime> createdAt,
    });

final class $$ImportSourcesTableReferences
    extends BaseReferences<_$AppDatabase, $ImportSourcesTable, ImportSource> {
  $$ImportSourcesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<
    $ImportedTransactionsTable,
    List<ImportedTransaction>
  >
  _importedTransactionsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.importedTransactions,
        aliasName: $_aliasNameGenerator(
          db.importSources.id,
          db.importedTransactions.sourceId,
        ),
      );

  $$ImportedTransactionsTableProcessedTableManager
  get importedTransactionsRefs {
    final manager = $$ImportedTransactionsTableTableManager(
      $_db,
      $_db.importedTransactions,
    ).filter((f) => f.sourceId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _importedTransactionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ImportSourcesTableFilterComposer
    extends Composer<_$AppDatabase, $ImportSourcesTable> {
  $$ImportSourcesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get columnMapping => $composableBuilder(
    column: $table.columnMapping,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> importedTransactionsRefs(
    Expression<bool> Function($$ImportedTransactionsTableFilterComposer f) f,
  ) {
    final $$ImportedTransactionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.importedTransactions,
      getReferencedColumn: (t) => t.sourceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportedTransactionsTableFilterComposer(
            $db: $db,
            $table: $db.importedTransactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ImportSourcesTableOrderingComposer
    extends Composer<_$AppDatabase, $ImportSourcesTable> {
  $$ImportSourcesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get columnMapping => $composableBuilder(
    column: $table.columnMapping,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ImportSourcesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ImportSourcesTable> {
  $$ImportSourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get columnMapping => $composableBuilder(
    column: $table.columnMapping,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> importedTransactionsRefs<T extends Object>(
    Expression<T> Function($$ImportedTransactionsTableAnnotationComposer a) f,
  ) {
    final $$ImportedTransactionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.importedTransactions,
          getReferencedColumn: (t) => t.sourceId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ImportedTransactionsTableAnnotationComposer(
                $db: $db,
                $table: $db.importedTransactions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ImportSourcesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ImportSourcesTable,
          ImportSource,
          $$ImportSourcesTableFilterComposer,
          $$ImportSourcesTableOrderingComposer,
          $$ImportSourcesTableAnnotationComposer,
          $$ImportSourcesTableCreateCompanionBuilder,
          $$ImportSourcesTableUpdateCompanionBuilder,
          (ImportSource, $$ImportSourcesTableReferences),
          ImportSource,
          PrefetchHooks Function({bool importedTransactionsRefs})
        > {
  $$ImportSourcesTableTableManager(_$AppDatabase db, $ImportSourcesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$ImportSourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () =>
                  $$ImportSourcesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$ImportSourcesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<String?> columnMapping = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ImportSourcesCompanion(
                id: id,
                name: name,
                type: type,
                currency: currency,
                columnMapping: columnMapping,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String type,
                required String currency,
                Value<String?> columnMapping = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ImportSourcesCompanion.insert(
                id: id,
                name: name,
                type: type,
                currency: currency,
                columnMapping: columnMapping,
                createdAt: createdAt,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$ImportSourcesTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({importedTransactionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (importedTransactionsRefs) db.importedTransactions,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (importedTransactionsRefs)
                    await $_getPrefetchedData<
                      ImportSource,
                      $ImportSourcesTable,
                      ImportedTransaction
                    >(
                      currentTable: table,
                      referencedTable: $$ImportSourcesTableReferences
                          ._importedTransactionsRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$ImportSourcesTableReferences(
                                db,
                                table,
                                p0,
                              ).importedTransactionsRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.sourceId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ImportSourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ImportSourcesTable,
      ImportSource,
      $$ImportSourcesTableFilterComposer,
      $$ImportSourcesTableOrderingComposer,
      $$ImportSourcesTableAnnotationComposer,
      $$ImportSourcesTableCreateCompanionBuilder,
      $$ImportSourcesTableUpdateCompanionBuilder,
      (ImportSource, $$ImportSourcesTableReferences),
      ImportSource,
      PrefetchHooks Function({bool importedTransactionsRefs})
    >;
typedef $$ImportedTransactionsTableCreateCompanionBuilder =
    ImportedTransactionsCompanion Function({
      Value<int> id,
      required int sourceId,
      required DateTime date,
      required int amountCents,
      required String direction,
      required String description,
      Value<String?> category,
      required String currency,
      required String rawDescription,
      required String importHash,
      Value<DateTime> createdAt,
    });
typedef $$ImportedTransactionsTableUpdateCompanionBuilder =
    ImportedTransactionsCompanion Function({
      Value<int> id,
      Value<int> sourceId,
      Value<DateTime> date,
      Value<int> amountCents,
      Value<String> direction,
      Value<String> description,
      Value<String?> category,
      Value<String> currency,
      Value<String> rawDescription,
      Value<String> importHash,
      Value<DateTime> createdAt,
    });

final class $$ImportedTransactionsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ImportedTransactionsTable,
          ImportedTransaction
        > {
  $$ImportedTransactionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ImportSourcesTable _sourceIdTable(_$AppDatabase db) =>
      db.importSources.createAlias(
        $_aliasNameGenerator(
          db.importedTransactions.sourceId,
          db.importSources.id,
        ),
      );

  $$ImportSourcesTableProcessedTableManager get sourceId {
    final $_column = $_itemColumn<int>('source_id')!;

    final manager = $$ImportSourcesTableTableManager(
      $_db,
      $_db.importSources,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sourceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ImportedTransactionsTableFilterComposer
    extends Composer<_$AppDatabase, $ImportedTransactionsTable> {
  $$ImportedTransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawDescription => $composableBuilder(
    column: $table.rawDescription,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get importHash => $composableBuilder(
    column: $table.importHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ImportSourcesTableFilterComposer get sourceId {
    final $$ImportSourcesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceId,
      referencedTable: $db.importSources,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportSourcesTableFilterComposer(
            $db: $db,
            $table: $db.importSources,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ImportedTransactionsTableOrderingComposer
    extends Composer<_$AppDatabase, $ImportedTransactionsTable> {
  $$ImportedTransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawDescription => $composableBuilder(
    column: $table.rawDescription,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get importHash => $composableBuilder(
    column: $table.importHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ImportSourcesTableOrderingComposer get sourceId {
    final $$ImportSourcesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceId,
      referencedTable: $db.importSources,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportSourcesTableOrderingComposer(
            $db: $db,
            $table: $db.importSources,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ImportedTransactionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ImportedTransactionsTable> {
  $$ImportedTransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => column,
  );

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get rawDescription => $composableBuilder(
    column: $table.rawDescription,
    builder: (column) => column,
  );

  GeneratedColumn<String> get importHash => $composableBuilder(
    column: $table.importHash,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ImportSourcesTableAnnotationComposer get sourceId {
    final $$ImportSourcesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceId,
      referencedTable: $db.importSources,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportSourcesTableAnnotationComposer(
            $db: $db,
            $table: $db.importSources,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ImportedTransactionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ImportedTransactionsTable,
          ImportedTransaction,
          $$ImportedTransactionsTableFilterComposer,
          $$ImportedTransactionsTableOrderingComposer,
          $$ImportedTransactionsTableAnnotationComposer,
          $$ImportedTransactionsTableCreateCompanionBuilder,
          $$ImportedTransactionsTableUpdateCompanionBuilder,
          (ImportedTransaction, $$ImportedTransactionsTableReferences),
          ImportedTransaction,
          PrefetchHooks Function({bool sourceId})
        > {
  $$ImportedTransactionsTableTableManager(
    _$AppDatabase db,
    $ImportedTransactionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$ImportedTransactionsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$ImportedTransactionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$ImportedTransactionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> sourceId = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<int> amountCents = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<String> rawDescription = const Value.absent(),
                Value<String> importHash = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ImportedTransactionsCompanion(
                id: id,
                sourceId: sourceId,
                date: date,
                amountCents: amountCents,
                direction: direction,
                description: description,
                category: category,
                currency: currency,
                rawDescription: rawDescription,
                importHash: importHash,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int sourceId,
                required DateTime date,
                required int amountCents,
                required String direction,
                required String description,
                Value<String?> category = const Value.absent(),
                required String currency,
                required String rawDescription,
                required String importHash,
                Value<DateTime> createdAt = const Value.absent(),
              }) => ImportedTransactionsCompanion.insert(
                id: id,
                sourceId: sourceId,
                date: date,
                amountCents: amountCents,
                direction: direction,
                description: description,
                category: category,
                currency: currency,
                rawDescription: rawDescription,
                importHash: importHash,
                createdAt: createdAt,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$ImportedTransactionsTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({sourceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                T extends TableManagerState<
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic
                >
              >(state) {
                if (sourceId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.sourceId,
                            referencedTable:
                                $$ImportedTransactionsTableReferences
                                    ._sourceIdTable(db),
                            referencedColumn:
                                $$ImportedTransactionsTableReferences
                                    ._sourceIdTable(db)
                                    .id,
                          )
                          as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ImportedTransactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ImportedTransactionsTable,
      ImportedTransaction,
      $$ImportedTransactionsTableFilterComposer,
      $$ImportedTransactionsTableOrderingComposer,
      $$ImportedTransactionsTableAnnotationComposer,
      $$ImportedTransactionsTableCreateCompanionBuilder,
      $$ImportedTransactionsTableUpdateCompanionBuilder,
      (ImportedTransaction, $$ImportedTransactionsTableReferences),
      ImportedTransaction,
      PrefetchHooks Function({bool sourceId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$WalletsTableTableManager get wallets =>
      $$WalletsTableTableManager(_db, _db.wallets);
  $$TransactionsTableTableManager get transactions =>
      $$TransactionsTableTableManager(_db, _db.transactions);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$BudgetsTableTableManager get budgets =>
      $$BudgetsTableTableManager(_db, _db.budgets);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$BtcPriceCacheTableTableManager get btcPriceCache =>
      $$BtcPriceCacheTableTableManager(_db, _db.btcPriceCache);
  $$BtcPriceHistoryTableTableManager get btcPriceHistory =>
      $$BtcPriceHistoryTableTableManager(_db, _db.btcPriceHistory);
  $$AiConversationsTableTableManager get aiConversations =>
      $$AiConversationsTableTableManager(_db, _db.aiConversations);
  $$ImportSourcesTableTableManager get importSources =>
      $$ImportSourcesTableTableManager(_db, _db.importSources);
  $$ImportedTransactionsTableTableManager get importedTransactions =>
      $$ImportedTransactionsTableTableManager(_db, _db.importedTransactions);
}
