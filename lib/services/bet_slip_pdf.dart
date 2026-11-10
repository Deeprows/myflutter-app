import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// One selection on the slip, taken from the AI analysis picks.
class BetSlipPick {
  final String market;
  final String pick;
  final String confidence;
  final String matchTitle;
  final String league;
  final DateTime? kickoff;
  const BetSlipPick({
    required this.market,
    required this.pick,
    required this.confidence,
    this.matchTitle = '',
    this.league = '',
    this.kickoff,
  });
}

/// Builds a printable bet slip (A5 PDF) from an AI analysis and opens the
/// system print / save-as-PDF / share sheet.
class BetSlipPdf {
  BetSlipPdf._();

  // The built-in PDF fonts cover Latin-1 only; fold other characters so a club
  // like "Beşiktaş" or "Łódź" never prints as empty boxes.
  static const _fold = {
    'ş': 's', 'Ş': 'S', 'ğ': 'g', 'Ğ': 'G', 'ı': 'i', 'İ': 'I',
    'ł': 'l', 'Ł': 'L', 'ź': 'z', 'ż': 'z', 'ś': 's', 'ń': 'n',
    'ć': 'c', 'č': 'c', 'Č': 'C', 'ě': 'e', 'ř': 'r', 'š': 's',
    'Š': 'S', 'ž': 'z', 'Ž': 'Z', 'ő': 'o', 'ű': 'u', 'ą': 'a',
    'ę': 'e', 'đ': 'd', 'Đ': 'D', 'ō': 'o', 'ū': 'u', 'ā': 'a',
    '–': '-', '—': '-', '‘': "'", '’': "'", '“': '"', '”': '"',
    '…': '...', '•': '-',
  };

  static String _latin(String input) {
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      if (rune < 256) {
        out.write(ch);
      } else {
        out.write(_fold[ch] ?? '');
      }
    }
    return out.toString();
  }

  static String _date(DateTime d) {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${m[d.month - 1]} ${d.year}, $h:$mi';
  }

  static Future<void> print({
    required String matchTitle,
    required String league,
    required DateTime? kickoff,
    required List<BetSlipPick> picks,
  }) async {
    final now = DateTime.now();
    final slipNo = 'DR-${now.millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
    const ink = PdfColors.grey900;
    const soft = PdfColors.grey600;

    pw.Widget cell(String text, {bool bold = false, double size = 10}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: pw.Text(
            _latin(text),
            style: pw.TextStyle(
              fontSize: size,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: ink,
            ),
          ),
        );

    pw.Widget blankLine(String label) => pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(right: 8),
            padding: const pw.EdgeInsets.all(8),
            height: 44,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey500, width: 0.8),
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 8, color: soft),
            ),
          ),
        );

    final doc = pw.Document(title: 'Deeprowss bet slip $slipNo');
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(26),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'DEEPROWSS BET SLIP',
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: ink,
                  ),
                ),
                pw.Text(
                  slipNo,
                  style: const pw.TextStyle(fontSize: 9, color: soft),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 1.2, color: ink),
            pw.SizedBox(height: 6),
            pw.Text(
              _latin(matchTitle),
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: ink,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              _latin(
                [
                  if (league.trim().isNotEmpty) league.trim(),
                  if (kickoff != null) 'Kick-off ${_date(kickoff)}',
                ].join('  |  '),
              ),
              style: const pw.TextStyle(fontSize: 9.5, color: soft),
            ),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.6),
              columnWidths: const {
                0: pw.FixedColumnWidth(22),
                1: pw.FlexColumnWidth(2.2),
                2: pw.FlexColumnWidth(2.4),
                3: pw.FixedColumnWidth(46),
                4: pw.FixedColumnWidth(40),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    cell('#', bold: true, size: 9),
                    cell('Market', bold: true, size: 9),
                    cell('Selection', bold: true, size: 9),
                    cell('Conf.', bold: true, size: 9),
                    cell('Odds', bold: true, size: 9),
                  ],
                ),
                for (var i = 0; i < picks.length; i++)
                  pw.TableRow(
                    children: [
                      cell('${i + 1}', size: 9),
                      cell(picks[i].market, size: 9.5),
                      cell(picks[i].pick, bold: true, size: 9.5),
                      cell(picks[i].confidence.toUpperCase(), size: 8),
                      cell('', size: 9),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Row(
              children: [
                blankLine('Bookmaker / booking code'),
                blankLine('Stake'),
                blankLine('Potential win'),
              ],
            ),
            pw.Spacer(),
            pw.Divider(color: PdfColors.grey400),
            pw.Text(
              'Generated ${_date(now)} from a Deeprowss AI analysis. Picks are '
              'informational only, results are never guaranteed, and odds must '
              'be filled in from your bookmaker. 18+ only. Bet responsibly and '
              'never stake more than you can afford to lose.',
              style: const pw.TextStyle(fontSize: 7.5, color: soft),
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(
      name: 'deeprowss-bet-slip-$slipNo.pdf',
      format: PdfPageFormat.a5,
      onLayout: (_) async => doc.save(),
    );
  }
  /// Prints a combined slip containing selections from multiple matches.
  static Future<void> printSelected({required List<BetSlipPick> picks}) async {
    if (picks.isEmpty) return;
    final now = DateTime.now();
    final slipNo = 'DR-${now.millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
    const ink = PdfColors.grey900;
    const soft = PdfColors.grey600;
    pw.Widget cell(String text, {bool bold = false, double size = 9}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      child: pw.Text(_latin(text), style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: ink)),
    );
    final doc = pw.Document(title: 'Deeprowss bet slip $slipNo');
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('DEEPROWSS BET SLIP', style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: ink)),
          pw.Text(slipNo, style: const pw.TextStyle(fontSize: 9, color: soft)),
        ]),
        pw.SizedBox(height: 5), pw.Divider(thickness: 1.2, color: ink),
        pw.SizedBox(height: 4),
        pw.Text('${picks.length} selections', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: ink)),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey500, width: .6),
          columnWidths: const {0: pw.FixedColumnWidth(22), 1: pw.FlexColumnWidth(2.5), 2: pw.FlexColumnWidth(1.8), 3: pw.FlexColumnWidth(2.3), 4: pw.FixedColumnWidth(48)},
          children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
              cell('#', bold: true), cell('Match / League', bold: true), cell('Market', bold: true), cell('Selection', bold: true), cell('Conf.', bold: true, size: 8),
            ]),
            for (var i = 0; i < picks.length; i++) pw.TableRow(children: [
              cell('${i + 1}'),
              cell([picks[i].matchTitle, if (picks[i].league.trim().isNotEmpty) picks[i].league, if (picks[i].kickoff != null) _date(picks[i].kickoff!)].join('\n'), size: 8.5),
              cell(picks[i].market, size: 8.5), cell(picks[i].pick, bold: true, size: 9), cell(picks[i].confidence.toUpperCase(), size: 7.5),
            ]),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Row(children: [
          for (final label in ['Bookmaker / booking code', 'Stake', 'Potential win'])
            pw.Expanded(child: pw.Container(margin: const pw.EdgeInsets.only(right: 8), padding: const pw.EdgeInsets.all(8), height: 46, decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey500), borderRadius: pw.BorderRadius.all(pw.Radius.circular(4))), child: pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: soft)))),
        ]),
        pw.SizedBox(height: 18),
        pw.Text('Generated ${_date(now)} from Deeprowss AI analysis. Picks are informational only; outcomes are uncertain and no results are guaranteed. Odds must be filled in separately. 18+ only. Bet responsibly.', style: const pw.TextStyle(fontSize: 8, color: soft)),
      ],
    ));
    await Printing.layoutPdf(name: 'deeprowss-bet-slip-$slipNo.pdf', format: PdfPageFormat.a4, onLayout: (_) async => doc.save());
  }

}
