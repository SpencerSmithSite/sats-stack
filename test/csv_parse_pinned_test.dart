/// What the statement parser returns for awkward CSV, pinned to what csv 6
/// returned, so a change of csv version cannot change how files read.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/services/import_service.dart';

const corpus = <String, String>{
  'plain':
      'Date,Description,Amount\n2026-01-02,Coffee,-3.50\n2026-01-03,Pay,1000\n',
  'crlf': 'Date,Description,Amount\r\n2026-01-02,Coffee,-3.50\r\n',
  'cr': 'Date,Description,Amount\r2026-01-02,Coffee,-3.50\r',
  'bom': '\uFEFFDate,Amount\n2026-01-02,5\n',
  'semicolon': 'Datum;Omschrijving;Bedrag\n02-01-2026;Koffie;-3,50\n',
  'tab': 'Date\tDesc\tAmount\n2026-01-02\tA\t1\n',
  'pipe': 'Date|Desc|Amount\n2026-01-02|A|1\n',
  'quoted':
      'Date,Description,Amount\n2026-01-02,"Coffee, large",-3.50\n2026-01-03,"He said ""hi""",2\n',
  'newline_in_quotes': 'Date,Description,Amount\n2026-01-02,"two\nlines",1\n',
  'empty_lines': 'Date,Amount\n\n2026-01-02,5\n\n\n2026-01-03,6\n',
  'blank_fields': 'Date,Desc,Amount\n2026-01-02,,5\n,,\n',
  'title_line':
      'Account statement for 1234\nDate,Desc,Amount\n2026-01-02,A,1\n',
  'sep_hint': 'sep=;\nDate;Desc;Amount\n2026-01-02;A;1\n',
  'no_trailing_newline': 'Date,Amount\n2026-01-02,5',
  'quote_mid_field': 'Date,Desc,Amount\n2026-01-02,A "B" C,1\n',
  'ragged': 'Date,Desc,Amount\n2026-01-02,A\n2026-01-03,B,2,extra\n',
  'leading_zeros': 'Ref,Amount\n00123,007.50\n',
  'spaces': 'Date , Desc , Amount\n 2026-01-02 , A , 1 \n',
  'only_header': 'Date,Desc,Amount\n',
  'empty': '',
  'whitespace_line': 'Date,Amount\n   \n2026-01-02,5\n',
};

/// As csv 6 parsed each of [corpus].
const expected = <String, List<List<String>>>{
  'plain': [
    ['Date', 'Description', 'Amount'],
    ['2026-01-02', 'Coffee', '-3.50'],
    ['2026-01-03', 'Pay', '1000'],
  ],
  'crlf': [
    ['Date', 'Description', 'Amount'],
    ['2026-01-02', 'Coffee', '-3.50'],
  ],
  'cr': [
    ['Date', 'Description', 'Amount'],
    ['2026-01-02', 'Coffee', '-3.50'],
  ],
  'bom': [
    ['Date', 'Amount'],
    ['2026-01-02', '5'],
  ],
  'semicolon': [
    ['Datum', 'Omschrijving', 'Bedrag'],
    ['02-01-2026', 'Koffie', '-3,50'],
  ],
  'tab': [
    ['Date', 'Desc', 'Amount'],
    ['2026-01-02', 'A', '1'],
  ],
  'pipe': [
    ['Date', 'Desc', 'Amount'],
    ['2026-01-02', 'A', '1'],
  ],
  'quoted': [
    ['Date', 'Description', 'Amount'],
    ['2026-01-02', 'Coffee, large', '-3.50'],
    ['2026-01-03', 'He said "hi"', '2'],
  ],
  'newline_in_quotes': [
    ['Date', 'Description', 'Amount'],
    ['2026-01-02', 'two\nlines', '1'],
  ],
  'empty_lines': [
    ['Date', 'Amount'],
    [''],
    ['2026-01-02', '5'],
    [''],
    [''],
    ['2026-01-03', '6'],
  ],
  'blank_fields': [
    ['Date', 'Desc', 'Amount'],
    ['2026-01-02', '', '5'],
    ['', '', ''],
  ],
  'title_line': [
    ['Account statement for 1234'],
    ['Date', 'Desc', 'Amount'],
    ['2026-01-02', 'A', '1'],
  ],
  'sep_hint': [
    ['sep=', ''],
    ['Date', 'Desc', 'Amount'],
    ['2026-01-02', 'A', '1'],
  ],
  'no_trailing_newline': [
    ['Date', 'Amount'],
    ['2026-01-02', '5'],
  ],
  'quote_mid_field': [
    ['Date', 'Desc', 'Amount'],
    ['2026-01-02', 'A "B" C', '1'],
  ],
  'ragged': [
    ['Date', 'Desc', 'Amount'],
    ['2026-01-02', 'A'],
    ['2026-01-03', 'B', '2', 'extra'],
  ],
  'leading_zeros': [
    ['Ref', 'Amount'],
    ['00123', '007.50'],
  ],
  'spaces': [
    ['Date ', ' Desc ', ' Amount'],
    [' 2026-01-02 ', ' A ', ' 1 '],
  ],
  'only_header': [
    ['Date', 'Desc', 'Amount'],
  ],
  'empty': [],
  'whitespace_line': [
    ['Date', 'Amount'],
    ['   '],
    ['2026-01-02', '5'],
  ],
};

void main() {
  for (final name in corpus.keys) {
    test(name, () {
      expect(ImportService.parseCsvRows(corpus[name]!), expected[name]);
    });
  }
}
