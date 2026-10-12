import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'utils.dart';

/// برچسب‌های جهت تراکنش که در جدول PDF نشان داده می‌شود
typedef DirectionLabels = ({String from, String fromName, String to, String toName});

/// مسیر فونت فارسی داخل assets پروژه — این دو فایل باید توسط خودتان اضافه شوند
/// (به README یا توضیحات پایین فایل مراجعه کنید). با این روش نیازی به اینترنت
/// در زمان اجرا نیست؛ فونت همراه خود اپ نصب می‌شود.
const String _kFontRegularAsset = 'assets/fonts/Vazirmatn-Regular.ttf';
const String _kFontBoldAsset = 'assets/fonts/Vazirmatn-Bold.ttf';

/// نیم‌فاصلهٔ فارسی در فونت PDF به‌صورت علامت خراب نمایش داده می‌شد (مثلاً «پرداخت‌کننده»)؛
/// برای رندر درست در PDF نیم‌فاصله با فاصلهٔ معمولی جایگزین می‌شود.
String pdfText(String s) => s.replaceAll('\u200c', ' ');

const String _kIconAsset = 'assets/images/pesteh-bazar-icon.png';

class PdfService {
  static pw.Font? _regular;
  static pw.Font? _bold;
  static pw.MemoryImage? _icon;

  static Future<void> _ensureIcon() async {
    if (_icon != null) return;
    try {
      final d = await rootBundle.load(_kIconAsset);
      _icon = pw.MemoryImage(d.buffer.asUint8List());
    } catch (_) {}
  }

  /// پای همهٔ صفحه‌ها: آیکون و نام «پسته بازار»
  static pw.Widget _brandFooter() => pw.Container(
        alignment: pw.Alignment.center,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
          if (_icon != null) pw.Image(_icon!, width: 16, height: 16),
          if (_icon != null) pw.SizedBox(width: 5),
          pw.Text(pdfText('پسته بازار'), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ]),
      );

  /// فونت فارسی را از assets داخل خود اپ بارگیری می‌کند (آفلاین، بدون اینترنت)
  static Future<void> _ensureFonts() async {
    if (_regular != null && _bold != null) {
      await _ensureIcon();
      return;
    }
    try {
      final regularData = await rootBundle.load(_kFontRegularAsset);
      final boldData = await rootBundle.load(_kFontBoldAsset);
      _regular = pw.Font.ttf(regularData);
      _bold = pw.Font.ttf(boldData);
      await _ensureIcon();
    } catch (e) {
      throw Exception(
          'فونت فارسی پیدا نشد. فایل‌های $_kFontRegularAsset و $_kFontBoldAsset را '
          'در پروژه قرار دهید و در pubspec.yaml به‌عنوان asset معرفی کنید.');
    }
  }

  static pw.ThemeData _theme() => pw.ThemeData.withFont(base: _regular, bold: _bold);

  static Future<File> _saveDoc(pw.Document doc, String filename) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(await doc.save());
    return file;
  }

  static Future<void> share(File file) async {
    final bytes = await file.readAsBytes();
    if (Platform.isWindows) {
      // ویندوز: پنجرهٔ چاپ (پرینتر لیزری/حرارتی یا «Microsoft Print to PDF» برای ذخیره)
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: p.basename(file.path));
      return;
    }
    await Printing.sharePdf(bytes: bytes, filename: p.basename(file.path));
  }

  static Future<File> buildStockCard({
    required String code,
    required double totalWeight,
    required double netWeight,
    required double smallSacks,
    required double largeSacks,
  }) async {
    await _ensureFonts();
    final doc = pw.Document(theme: _theme());
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a6,
      margin: const pw.EdgeInsets.all(14),
      textDirection: pw.TextDirection.rtl,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text('کارتکس انبار', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          pw.Divider(),
          _kv('کد پسته', code, bold: true),
          _kv('وزن کل', '${faNum(totalWeight)} کیلو'),
          _kv('وزن خالص', '${faNum(netWeight)} کیلو'),
          _kv('تعداد گونی', faNum(smallSacks + largeSacks)),
          _kv('تعداد گونی کوچک', faNum(smallSacks)),
          _kv('تعداد گونی بزرگ', faNum(largeSacks)),
          pw.Spacer(),
          _brandFooter(),
        ],
      ),
    ));
    return _saveDoc(doc, 'stock_card_$code.pdf');
  }

  static pw.Widget _kv(String k, String v, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(pdfText(k), style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text(pdfText(v), style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        ),
      );

  /// رسید تراکنش‌های پرداخت (خرید) یا دریافت (فروش) برای یک رکورد مشخص
  static Future<File> buildPaymentLedger({
    required String title,
    required String pesteCode,
    required String totalLabel,
    required double total,
    required double settled,
    required double remaining,
    required String? payType,
    required String? stagedType,
    required List<Map<String, dynamic>> lump,
    required List<Map<String, dynamic>> credit,
    required List<Map<String, dynamic>> cheque,
    required DirectionLabels directionLabels,
  }) async {
    await _ensureFonts();
    final doc = pw.Document(theme: _theme());
    final now = DateTime.now();

    List<List<String>> rows = [];
    if (payType == 'lump') {
      rows = [
        ['وضعیت', 'تاریخ', directionLabels.toName, directionLabels.fromName, 'مبلغ (تومان)'],
        for (final r in lump)
          [
            (r['paid'] as int? ?? 1) == 1 ? 'تسویه شده' : 'ثبت‌شده',
            jalaliDate(r['date'] as String),
            '${r['seller_name'] ?? r['receiver_name'] ?? '-'}',
            '${r['payer_name'] ?? '-'}',
            faNum(r['amount'] as num, dec: 0),
          ],
      ];
    } else if (payType == 'staged' && stagedType == 'credit') {
      rows = [
        ['وضعیت', 'سررسید', directionLabels.toName, directionLabels.fromName, 'مبلغ (تومان)'],
        for (final r in credit)
          [
            (r['paid'] as int) == 1 ? 'تسویه شده' : 'باقیمانده',
            jalaliDate(r['due_date'] as String),
            '${r['seller_name'] ?? r['receiver_name'] ?? '-'}',
            '${r['payer_name'] ?? '-'}',
            faNum(r['amount'] as num, dec: 0),
          ],
      ];
    } else if (payType == 'staged' && stagedType == 'cheque') {
      rows = [
        ['وضعیت', 'بانک', 'شماره چک', 'سررسید', 'مبلغ (تومان)'],
        for (final r in cheque)
          [
            (r['paid'] as int) == 1 ? 'تسویه شده' : 'باقیمانده',
            '${r['bank_name'] ?? '-'}',
            '${r['cheque_no'] ?? '-'}',
            jalaliDate(r['due_date'] as String),
            faNum(r['amount'] as num, dec: 0),
          ],
      ];
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        header: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(pdfText(title), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text(pdfText('تاریخ تهیه گزارش: ${jalaliDateFromDt(now)}'), style: const pw.TextStyle(fontSize: 9)),
          pw.Divider(),
        ]),
        footer: (ctx) => _brandFooter(),
        build: (ctx) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(children: [
              _kv('کد پسته', pesteCode.isEmpty ? '-' : pesteCode, bold: true),
              _kv(totalLabel, '${faNum(total, dec: 0)} تومان', bold: true),
              _kv('تسویه شده', '${faNum(settled, dec: 0)} تومان'),
              _kv(remaining >= 0 ? 'باقیمانده' : 'اضافه‌پرداخت', '${faNum(remaining.abs(), dec: 0)} تومان'),
            ]),
          ),
          pw.SizedBox(height: 16),
          if (rows.length > 1)
            pw.Table.fromTextArray(
              headers: rows.first.map(pdfText).toList(),
              data: rows.skip(1).map((r) => r.map(pdfText).toList()).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerRight,
              headerAlignment: pw.Alignment.centerRight,
              border: pw.TableBorder.all(width: 0.4),
            )
          else
            pw.Text(pdfText('تراکنشی ثبت نشده است')),
        ],
      ),
    );

    final fname = 'ledger_${now.millisecondsSinceEpoch}.pdf';
    return _saveDoc(doc, fname);
  }

  /// گزارش کلی همه‌ی تراکنش‌های پرداخت یا دریافت در یک بازه‌ی زمانی
  static Future<File> buildGlobalReport({
    required String title,
    required String periodLabel,
    required double grandTotal,
    required List<List<String>> tableRows, // ردیف اول = عنوان ستون‌ها
  }) async {
    await _ensureFonts();
    final doc = pw.Document(theme: _theme());
    final now = DateTime.now();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        header: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(pdfText(title), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text(pdfText(periodLabel), style: const pw.TextStyle(fontSize: 10)),
          pw.Text(pdfText('تاریخ تهیه گزارش: ${jalaliDateFromDt(now)}'), style: const pw.TextStyle(fontSize: 9)),
          pw.Divider(),
        ]),
        footer: (ctx) => _brandFooter(),
        build: (ctx) => [
          _kv('جمع کل', '${faNum(grandTotal, dec: 0)} تومان', bold: true),
          pw.SizedBox(height: 12),
          if (tableRows.length > 1)
            pw.Table.fromTextArray(
              headers: tableRows.first.map(pdfText).toList(),
              data: tableRows.skip(1).map((r) => r.map(pdfText).toList()).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerRight,
              headerAlignment: pw.Alignment.centerRight,
              border: pw.TableBorder.all(width: 0.4),
            )
          else
            pw.Text(pdfText('در این بازه تراکنشی یافت نشد')),
        ],
      ),
    );

    final fname = 'report_${now.millisecondsSinceEpoch}.pdf';
    return _saveDoc(doc, fname);
  }

  /// فاکتور خرید یا فروش (A4). [withUsd] = فاکتور «تومانی/ارزی» که فی و مبلغ دلاری و نرخ دلار را هم درج می‌کند.
  static Future<File> buildInvoice({
    required bool isSale,
    required bool withUsd,
    required String number,
    required String dateLabel,
    required String sellerName,
    required String buyerName,
    required String category,
    required String type,
    required String code,
    required double totalWeight,
    required double smallSacks,
    required double largeSacks,
    required double netWeight,
    required double unitPrice, // تومان به‌ازای هر کیلو
    required List<List<String>> specs, // [عنوان، مقدار]
    double? usdRate, // تومان به‌ازای هر دلار
    double? paidAmount, // مبلغ پرداخت‌شده/دریافت‌شده (تومان)؛ null = بدون بخش پرداخت (مثلاً بار مخلوط)
    String? note,
  }) async {
    await _ensureFonts();
    final doc = pw.Document(theme: _theme());
    final now = DateTime.now();
    final amount = netWeight * unitPrice;
    final unitUsd = (withUsd && usdRate != null && usdRate > 0) ? unitPrice / usdRate : null;
    final amountUsd = unitUsd == null ? null : netWeight * unitUsd;

    final headers = <String>[
      'ردیف', 'دسته', 'نوع', 'کد پسته', 'وزن خالص (کیلو)', 'فی (تومان)', 'مبلغ (تومان)',
      if (withUsd) ...['فی (دلار)', 'مبلغ (دلار)'],
    ];
    final row = <String>[
      faNum(1, dec: 0), category, type, code, faNum(netWeight), faNum(unitPrice, dec: 0), faNum(amount, dec: 0),
      if (withUsd) ...[unitUsd == null ? '-' : faNum(unitUsd, dec: 4), amountUsd == null ? '-' : faNum(amountUsd)],
    ];

    pw.Widget sign(String label) => pw.Expanded(
          child: pw.Container(
            height: 56,
            margin: const pw.EdgeInsets.symmetric(horizontal: 6),
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5), borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Text(pdfText(label), style: const pw.TextStyle(fontSize: 9)),
          ),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        textDirection: pw.TextDirection.rtl,
        footer: (ctx) => _brandFooter(),
        build: (ctx) => [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(pdfText(isSale ? 'فاکتور فروش' : 'فاکتور خرید'),
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.Text(pdfText(withUsd ? 'نوع فاکتور: تومانی / ارزی' : 'نوع فاکتور: تومانی'),
                style: const pw.TextStyle(fontSize: 10)),
          ]),
          pw.Divider(),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(children: [
              _kv('شماره فاکتور', number, bold: true),
              _kv('تاریخ', dateLabel),
              _kv('فروشنده', sellerName.isEmpty ? '-' : sellerName),
              _kv('خریدار', buyerName.isEmpty ? '-' : buyerName),
              if (withUsd && usdRate != null) _kv('نرخ دلار (تومان)', faNum(usdRate, dec: 0)),
            ]),
          ),
          pw.SizedBox(height: 14),
          pw.Table.fromTextArray(
            headers: headers.map(pdfText).toList(),
            data: [row.map(pdfText).toList()],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerRight,
            headerAlignment: pw.Alignment.centerRight,
            border: pw.TableBorder.all(width: 0.4),
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(children: [
              _kv('وزن کل (با گونی)', '${faNum(totalWeight)} کیلو'),
              _kv('گونی کوچک / بزرگ', '${faNum(smallSacks)} / ${faNum(largeSacks)}'),
              _kv('وزن خالص', '${faNum(netWeight)} کیلو'),
            ]),
          ),
          if (specs.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text(pdfText('مشخصات جنس'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
            pw.SizedBox(height: 4),
            pw.Table.fromTextArray(
              headers: [pdfText('مشخصه'), pdfText('مقدار')],
              data: [for (final r in specs) [pdfText(r[0]), pdfText(r[1])]],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerRight,
              headerAlignment: pw.Alignment.centerRight,
              border: pw.TableBorder.all(width: 0.4),
            ),
          ],
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(width: 1), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(children: [
              _kv('جمع کل (تومان)', '${faNum(amount, dec: 0)} تومان', bold: true),
              if (withUsd) _kv('جمع کل (دلار)', amountUsd == null ? '-' : faUsd(amountUsd), bold: true),
              if (paidAmount != null) ...[
                pw.Divider(),
                _kv('مبلغ پرداخت‌شده (تومان)', '${faNum(paidAmount, dec: 0)} تومان'),
                _kv('مانده حساب (تومان)', '${faNum(amount - paidAmount, dec: 0)} تومان', bold: true),
              ],
            ]),
          ),
          if (note != null && note.trim().isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(pdfText('توضیحات: $note'), style: const pw.TextStyle(fontSize: 9)),
          ],
          pw.SizedBox(height: 22),
          pw.Row(children: [sign('امضای فروشنده'), sign('امضای خریدار')]),
          pw.SizedBox(height: 8),
          pw.Text(pdfText('تاریخ صدور: ${jalaliDateFromDt(now)}'), style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );

    final safe = number.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return _saveDoc(doc, 'invoice_${safe}_${now.millisecondsSinceEpoch}.pdf');
  }
}
