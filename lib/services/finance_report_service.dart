import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/finance_model.dart';

class FinanceReportService {
  static const _primary = PdfColor.fromInt(0xFF713131);
  static const _green = PdfColor.fromInt(0xFF27AE60);
  static const _red = PdfColor.fromInt(0xFFE74C3C);
  static const _grey = PdfColor.fromInt(0xFF786E6E);
  static const _text = PdfColor.fromInt(0xFF2D1515);
  static const _headerBg = PdfColor.fromInt(0xFFF7F0F0);
  static const _border = PdfColor.fromInt(0xFFE6DCDC);

  static String monthLabel(String ym) {
    final s = DateFormat('MMMM yyyy', 'fr_FR').format(DateTime.parse('$ym-01'));
    return s[0].toUpperCase() + s.substring(1);
  }

  static List<String> availableMonths(List<FinanceOrder> orders, List<FinanceSale> sales) {
    final set = <String>{DateFormat('yyyy-MM').format(DateTime.now())};
    for (final d in [...orders.map((o) => o.date), ...sales.map((s) => s.date)]) {
      if (d.length >= 7) set.add(d.substring(0, 7));
    }
    return set.toList()..sort((a, b) => b.compareTo(a));
  }

  static Future<void> shareMonthlyReport({
    required String month,
    required List<FinanceOrder> orders,
    required List<FinanceSale> sales,
  }) async {
    final bytes = await _build(month, orders, sales);
    await Printing.sharePdf(bytes: bytes, filename: 'Recap-finances-$month.pdf');
  }

  static String _fmt(double n) => n.toStringAsFixed(2);

  static String _fmtDate(String s) {
    final d = DateTime.tryParse(s);
    return d == null ? s : DateFormat('dd/MM/yyyy').format(d);
  }

  static Future<Uint8List> _build(String month, List<FinanceOrder> orders, List<FinanceSale> sales) async {
    final mOrders = orders.where((o) => o.date.startsWith(month)).toList()..sort((a, b) => a.date.compareTo(b.date));
    final mSales = sales.where((s) => s.date.startsWith(month)).toList()..sort((a, b) => a.date.compareTo(b.date));
    final totalOrders = mOrders.fold<double>(0, (s, o) => s + o.amount);
    final totalSales = mSales.fold<double>(0, (s, v) => s + v.total);
    final profit = totalSales - totalOrders;
    final margin = totalSales > 0 ? (profit / totalSales * 100).round() : 0;
    final label = monthLabel(month);

    // Built-in PDF fonts cannot render the euro sign, so embed Nunito (same font as the web app).
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: await PdfGoogleFonts.nunitoRegular(),
        bold: await PdfGoogleFonts.nunitoBold(),
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Récapitulatif $label', style: const pw.TextStyle(fontSize: 8, color: _grey)),
            pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _grey)),
          ],
        ),
        build: (ctx) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            color: _primary,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Récapitulatif financier',
                        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                    pw.SizedBox(height: 4),
                    pw.Text(label, style: const pw.TextStyle(fontSize: 12, color: PdfColors.white)),
                  ],
                ),
                pw.Text('Édité le ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.white)),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            children: [
              _card('Revenus (ventes)', '${_fmt(totalSales)} €', _green,
                  '${mSales.length} vente${mSales.length > 1 ? 's' : ''}'),
              pw.SizedBox(width: 8),
              _card('Dépenses (commandes)', '${_fmt(totalOrders)} €', _red,
                  '${mOrders.length} commande${mOrders.length > 1 ? 's' : ''}'),
              pw.SizedBox(width: 8),
              _card('Bénéfice net', '${profit >= 0 ? '+' : ''}${_fmt(profit)} €', profit >= 0 ? _green : _red,
                  profit >= 0 ? 'Positif' : 'Négatif'),
              pw.SizedBox(width: 8),
              _card('Marge', '$margin %', _primary, "sur le chiffre d'affaires"),
            ],
          ),
          pw.SizedBox(height: 20),
          ..._table(
            title: 'Ventes',
            headers: ['Date', 'Produit', 'Qté', 'Prix unit.', 'Total'],
            widths: const {0: pw.FixedColumnWidth(70), 2: pw.FixedColumnWidth(40), 3: pw.FixedColumnWidth(75), 4: pw.FixedColumnWidth(75)},
            rightCols: const {2, 3, 4},
            rows: mSales
                .map((s) => [
                      _fmtDate(s.date),
                      s.productName,
                      s.qty.toStringAsFixed(s.qty % 1 == 0 ? 0 : 1),
                      '${_fmt(s.unitPrice)} €',
                      '${_fmt(s.total)} €',
                    ])
                .toList(),
            totalLabel: 'Total revenus',
            total: totalSales,
            color: _green,
            emptyText: 'Aucune vente ce mois-ci.',
          ),
          pw.SizedBox(height: 20),
          ..._table(
            title: 'Commandes de matière',
            headers: ['Date', 'Fournisseur', 'Description', 'Montant'],
            widths: const {0: pw.FixedColumnWidth(70), 1: pw.FixedColumnWidth(110), 3: pw.FixedColumnWidth(80)},
            rightCols: const {3},
            rows: mOrders
                .map((o) => [
                      _fmtDate(o.date),
                      o.supplier.isNotEmpty ? o.supplier : '—',
                      o.description.isNotEmpty ? o.description : '—',
                      '${_fmt(o.amount)} €',
                    ])
                .toList(),
            totalLabel: 'Total dépenses',
            total: totalOrders,
            color: _red,
            emptyText: 'Aucune commande ce mois-ci.',
          ),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _card(String title, String value, PdfColor color, String sub) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: color, width: 3),
              left: const pw.BorderSide(color: _border, width: 0.5),
              right: const pw.BorderSide(color: _border, width: 0.5),
              bottom: const pw.BorderSide(color: _border, width: 0.5),
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title.toUpperCase(), style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: _grey)),
              pw.SizedBox(height: 4),
              pw.Text(value, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: color)),
              pw.SizedBox(height: 2),
              pw.Text(sub, style: const pw.TextStyle(fontSize: 7, color: _grey)),
            ],
          ),
        ),
      );

  static List<pw.Widget> _table({
    required String title,
    required List<String> headers,
    required Map<int, pw.TableColumnWidth> widths,
    required Set<int> rightCols,
    required List<List<String>> rows,
    required String totalLabel,
    required double total,
    required PdfColor color,
    required String emptyText,
  }) =>
      [
        pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _primary)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: headers.map((h) => h.toUpperCase()).toList(),
          data: rows,
          border: null,
          headerDecoration: const pw.BoxDecoration(color: _headerBg),
          headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _grey),
          cellStyle: const pw.TextStyle(fontSize: 9, color: _text),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFCF9F9)),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          columnWidths: {
            for (var i = 0; i < headers.length; i++) i: widths[i] ?? const pw.FlexColumnWidth(),
          },
          headerAlignments: {for (final i in rightCols) i: pw.Alignment.centerRight},
          cellAlignments: {for (final i in rightCols) i: pw.Alignment.centerRight},
        ),
        if (rows.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text(emptyText, style: const pw.TextStyle(fontSize: 9, color: _grey)),
          ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
          decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: color, width: 1))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(totalLabel, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: color)),
              pw.Text('${_fmt(total)} €', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: color)),
            ],
          ),
        ),
      ];
}
