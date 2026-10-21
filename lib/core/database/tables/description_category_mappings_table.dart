import 'package:drift/drift.dart';
import 'import_sources_table.dart';

/// One learned category per description per source.
///
/// Unique so the write can be a single upsert: it used to be a delete followed
/// by an insert, awaited per row, which is two round-trips for every line of
/// every import and could leave duplicates behind if two imports interleaved.
@TableIndex(
  name: 'idx_description_mappings_source_description',
  columns: {#sourceId, #description},
  unique: true,
)
class DescriptionCategoryMappings extends Table {
  IntColumn get id => integer().autoIncrement()();
  // Stored lowercase-trimmed for case-insensitive lookup
  TextColumn get description => text()();
  IntColumn get sourceId => integer().references(ImportSources, #id)();
  TextColumn get category => text()();
}
