import 'package:flutter/material.dart';

import 'sync_screen.dart';
import 'sync_service.dart';
import 'db.dart';
import 'license_service.dart';
import 'messages_card.dart';
import 'dues_screen.dart';
import 'ledger.dart';
import 'purchase_form.dart';
import 'sale_form.dart';
import 'utils.dart';
import 'widgets.dart';

/// صفحهٔ اصلی: یک نگاه سریع به وضعیت امروز + دسترسی به کارهای پرتکرار
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('پسته بازار')),
      body: ValueListenableBuilder<int>(
        valueListenable: AppDb.I.version,
        builder: (_, __, ___) => FutureBuilder(
          future: Future.wait([
            AppDb.I.lots(),
            AppDb.I.sales(),
            loadDues(),
          ]),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final lots = snap.data![0] as List<Map<String, dynamic>>;
            final sales = snap.data![1] as List<Map<String, dynamic>>;
            final dues = snap.data![2] as List<DueItem>;

            final now = DateTime.now();
            final startOfMonth = DateTime(now.year, now.month, 1);

            double invKg = 0;
            for (final l in lots) {
              invKg += (l['remaining'] as num).toDouble();
            }

            // حریم خصوصی: در صفحهٔ اصلی فقط مقدارِ فروش (کیلوگرم) و موجودی دیده می‌شود؛ سود و زیان فقط در صفحهٔ «سود و زیان» (قابل قفل)
            double todayKg = 0, monthKg = 0;
            int todayCount = 0;
            for (final s in sales) {
              final date = DateTime.parse(s['date'] as String);
              final net = (s['net_weight'] as num).toDouble();
              if (_sameDay(date, now)) {
                todayKg += net;
                todayCount++;
              }
              if (!date.isBefore(startOfMonth)) monthKg += net;
            }

            final overdue = dues.where((d) => daysUntil(d.date) < 0).toList();
            final soon =
                dues.where((d) => daysUntil(d.date) >= 0 && daysUntil(d.date) <= 7).toList();
            double overdueAmt = overdue.fold(0.0, (s, d) => s + d.amount);
            double soonAmt = soon.fold(0.0, (s, d) => s + d.amount);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const MessagesCard(),
                _quickActions(context),
                const SizedBox(height: 16),
                // موجودی انبار: درشت و پررنگ
                Card(
                  color: scheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                    child: Column(children: [
                      Text('موجودی انبار (خالص)', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text('${faNum(invKg)} کیلو',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                sectionTitle(context, 'فروش'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      infoRow('فروش امروز', '${faNum(todayCount)} مورد • ${faNum(todayKg)} کیلو (خالص)'),
                      infoRow('فروش این ماه', '${faNum(monthKg)} کیلو (خالص)'),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const DuesScreen())),
                  child: Card(
                    color: overdue.isNotEmpty ? scheme.errorContainer : null,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Expanded(
                              child: Text('سررسیدها',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                          const Icon(Icons.chevron_left),
                        ]),
                        if (overdue.isEmpty && soon.isEmpty)
                          const Text('چیزی سررسید نزدیک ندارد')
                        else ...[
                          if (overdue.isNotEmpty)
                            infoRow('عقب‌افتاده', '${faNum(overdue.length)} مورد • ${faNum(overdueAmt, dec: 0)} تومان',
                                valueColor: scheme.error),
                          if (soon.isNotEmpty)
                            infoRow('تا ۷ روز آینده',
                                '${faNum(soon.length)} مورد • ${faNum(soonAmt, dec: 0)} تومان'),
                        ],
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const SyncScreen())),
                  child: ValueListenableBuilder<SyncInfo>(
                    valueListenable: SyncService.I.info,
                    builder: (context, info, _) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          Icon(info.failed > 0
                              ? Icons.error_outline
                              : info.offline
                                  ? Icons.cloud_off
                                  : info.pending > 0
                                      ? Icons.cloud_sync_outlined
                                      : Icons.cloud_done_outlined),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(info.failed > 0
                                ? 'همگام‌سازی: ${faNum(info.failed)} مورد خطادار'
                                : info.offline
                                    ? 'آفلاین — ${faNum(info.pending)} تغییر در صف ارسال'
                                    : info.pending > 0
                                        ? 'همگام‌سازی: ${faNum(info.pending)} تغییر در صف ارسال'
                                        : 'همگام‌سازی: به‌روز است'),
                          ),
                          const Icon(Icons.chevron_left),
                        ]),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _quickActions(BuildContext context) {
    return Row(children: [
      Expanded(
        child: FilledButton.icon(
          onPressed: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseForm())),
          icon: const Icon(Icons.shopping_cart_outlined),
          label: const Text('خرید جدید'),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: FilledButton.icon(
          onPressed: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SaleForm())),
          icon: const Icon(Icons.sell_outlined),
          label: const Text('فروش جدید'),
        ),
      ),
    ]);
  }
}
