import 'package:flutter/material.dart';

import 'sync_screen.dart';
import 'sync_service.dart';
import 'db.dart';
import 'license_service.dart';
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

            double invKg = 0, invValue = 0;
            for (final l in lots) {
              final rem = (l['remaining'] as num).toDouble();
              invKg += rem;
              invValue += rem * (l['price'] as num).toDouble();
            }

            double todayRevenue = 0, monthRevenue = 0, monthProfit = 0, monthProfitUsd = 0;
            final fx = LicenseService.I.isFx.value;
            int todayCount = 0;
            for (final s in sales) {
              final date = DateTime.parse(s['date'] as String);
              final net = (s['net_weight'] as num).toDouble();
              final price = (s['price'] as num).toDouble();
              final revenue = net * price;
              final items = s['items'] as List;
              final cost = items.fold<double>(
                  0, (a, it) => a + (it['weight'] as num) * (it['cost_price'] as num));
              if (_sameDay(date, now)) {
                todayRevenue += revenue;
                todayCount++;
              }
              if (!date.isBefore(startOfMonth)) {
                monthRevenue += revenue;
                monthProfit += revenue - cost;
                final u = fx ? saleUsd(s) : null;
                if (u != null) monthProfitUsd += u.profit;
              }
            }

            final overdue = dues.where((d) => daysUntil(d.date) < 0).toList();
            final soon =
                dues.where((d) => daysUntil(d.date) >= 0 && daysUntil(d.date) <= 7).toList();
            double overdueAmt = overdue.fold(0.0, (s, d) => s + d.amount);
            double soonAmt = soon.fold(0.0, (s, d) => s + d.amount);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _quickActions(context),
                const SizedBox(height: 16),
                sectionTitle(context, 'امروز'),
                Card(
                  color: scheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      infoRow('فروش امروز', '${faNum(todayCount)} مورد'),
                      infoRow('مبلغ فروش امروز', '${faNum(todayRevenue, dec: 0)} تومان'),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                sectionTitle(context, 'این ماه'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      infoRow('مبلغ فروش ماه', '${faNum(monthRevenue, dec: 0)} تومان'),
                      infoRow('سود ماه', '${faNum(monthProfit, dec: 0)} تومان',
                          valueColor:
                              monthProfit >= 0 ? Colors.green.shade800 : scheme.error),
                      if (fx)
                        infoRow('سود دلاری ماه', faUsd(monthProfitUsd),
                            valueColor: monthProfitUsd >= 0 ? Colors.green.shade800 : scheme.error),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                sectionTitle(context, 'موجودی انبار'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      infoRow('وزن موجودی', '${faNum(invKg)} کیلو'),
                      infoRow('ارزش خرید موجودی', '${faNum(invValue, dec: 0)} تومان'),
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
                          Expanded(child: sectionTitle(context, 'سررسیدها')),
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
