import 'package:drift/drift.dart';
import 'import_sources_table.dart';

class DescriptionCategoryMappings extends Table {
  IntColumn get id => integer().autoIncrement()();
  // Stored lowercase-trimmed for case-insensitive lookup
  TextColumn get description => text()();
  IntColumn get sourceId => integer().references(ImportSources, #id)();
  TextColumn get category => text()();
}
