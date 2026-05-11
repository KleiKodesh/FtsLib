import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Bottom sheet showing query syntax help.
/// Mirrors the C# SearchHelpWindow.
class SyntaxHelpSheet extends StatelessWidget {
  const SyntaxHelpSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title
              const Text(
                'תחביר חיפוש',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A)),
              ),
              const SizedBox(height: 12),

              // Table
              Expanded(
                child: ListView(
                  controller: controller,
                  children: [
                    _tableHeader(),
                    _row(false, '*מילה*',
                        'כוכבית — תחיליות וסופיות.\n'
                        'דוגמה: ישר* → ישראל, ישרים…   *לום → שלום, עולם…'),
                    _row(true, 'מיל?ה',
                        'שאלתית — התו שלפני הסימן שאלה אופציונלי.\n'
                        'דוגמה: שלו?ם → שלום או שלם'),
                    _row(false, 'מילה~',
                        'טילדה — חיפוש מטושטש, מרחק עריכה 1.\n'
                        'דוגמה: יצחק~ → יצחק, ביצחק, ליצחק…'),
                    _row(true, 'מילה~2  /  מילה~3',
                        'טילדה עם מספר — מרחק עריכה מותאם (1–3).\n'
                        'דוגמה: משה~2 → משה, למשה, ממשה…'),
                    _row(false, 'א | ב',
                        'מקף אנכי — OR: מספיק שאחת מהמילים תופיע.\n'
                        'דוגמה: משה | אהרן תורה → (משה או אהרן) וגם תורה'),

                    const SizedBox(height: 14),
                    Divider(color: Colors.grey[300]),
                    const SizedBox(height: 10),

                    const Text('הערות נוספות',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF888888))),
                    const SizedBox(height: 6),

                    _tableHeader(),
                    _row(false, 'שרשרת OR',
                        'א | ב | ג תורה → (א או ב או ג) וגם תורה.'),
                    _row(true, 'קבוצות נפרדות',
                        'א | ב ג | ד → (א או ב) וגם (ג או ד).'),
                    _row(false, 'כוכבית + שאלתית',
                        'ניתן לשלב באותה מילה, למשל שלו?ם*.'),
                    _row(true, 'טילדה + כוכבית',
                        'לא ניתן לשלב — הכוכבית/שאלתית גוברת.',
                        danger: true),
                    const SizedBox(height: 24),
                  ],
                ),
              ),

              // Close button
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E6DA4),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                    elevation: 0,
                  ),
                  child: const Text('סגור'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tableHeader() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE8EEF5),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 140,
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Text('תבנית',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333))),
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Text('משמעות ודוגמה',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(bool even, String pattern, String description,
      {bool danger = false}) {
    return Container(
      color: even ? const Color(0xFFF7F9FC) : Colors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                pattern,
                style: TextStyle(
                  fontFamily: 'Courier New',
                  fontSize: 13,
                  color: danger
                      ? const Color(0xFFC0392B)
                      : const Color(0xFF1A5490),
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: danger
                      ? const Color(0xFFC0392B)
                      : const Color(0xFF333333),
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
