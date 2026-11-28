import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memory_taker/main.dart';
import 'package:memory_taker/model/watch_entry.dart';

void main() {
  testWidgets('date picker accepts a year without inventing a visible day', (
    tester,
  ) async {
    ({DateTime date, DatePrecision precision})? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showDialog<({DateTime date, DatePrecision precision})>(
                  context: context,
                  builder: (_) => const PartialDatePicker(
                    initialDate: null,
                    initialPrecision: DatePrecision.day,
                  ),
                );
              },
              child: const Text('选择'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('只到年'));
    await tester.enterText(find.byType(TextField), '2024');
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(selected?.precision, DatePrecision.year);
    expect(selected?.date, DateTime(2024));
  });
}
