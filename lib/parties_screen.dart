import 'package:flutter/material.dart';

import 'db.dart';
import 'ledger.dart';
import 'payment_screen.dart';
import 'receipt_screen.dart';
import 'utils.dart';
import 'widgets.dart';

/// حساب طرف‌ها: برای هر فروشنده/خریدار، جمع خرید و فروش و بدهی/طلب باقی‌مانده
class PartiesScreen extends StatefulWidget {
  const PartiesScreen({super.key});
  @override
  State<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends State<PartiesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حساب طرف‌ها')),
      body: ValueListenableBuilder<int>(
        valueListenable: AppDb.I.version,
        builder: (_, __, ___) => FutureBuilder<List<PartyAccount>>(
          future: loadParties(),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('خطا: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final all = snap.data!;
            if (all.isEmpty) {
              return const Center(child: Text('هنوز خرید یا فروشی ثبت نشده'));
            }
            double weOwe = 0, theyOwe = 0;
            for (final a in all) {
              if (a.weOwe > 0) weOwe += a.weOwe;
              if (a.theyOwe > 0) theyOwe += a.theyOwe;
            }
            final q = partyKey(_query);
            final list = q.isEmpty ? all : all.where((a) => a.key.contains(q)).toList();
            final scheme = Theme.of(context).colorScheme;
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                Card(
                  color: scheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      infoRow('جمع طلب‌ها (از خریدارها)', '${faNum(theyOwe, dec: 0)} تومان',
                          valueColor: Colors.green.shade800),
                      infoRow('جمع بدهی‌ها (به فروشنده‌ها)', '${faNum(weOwe, dec: 0)} تومان',
                          valueColor: Colors.red.shade800),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'جستجوی نام',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 8),
                for (final a in list) _tile(context, a),
                if (list.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(24), child: Center(child: Text('موردی پیدا نشد'))),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, PartyAccount a) {
    final settled = a.net.abs() < 1;
    final color = settled
        ? Colors.black54
        : (a.net > 0 ? Colors.green.shade800 : Colors.red.shade800);
    final lines = <String>[
      if (a.bought > 0) 'خرید ${faNum(a.bought, dec: 0)}',
      if (a.sold > 0) 'فروش ${faNum(a.sold, dec: 0)}',
    ].join('  •  ');
    return Card(
      key: ValueKey('party${a.key}'),
      child: ListTile(
        title: Text(a.name),
        subtitle: Text(lines),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(settled ? 'تسویه' : faNum(a.net.abs(), dec: 0),
                style: TextStyle(fontWeight: FontWeight.w700, color: color)),
            Text(settled ? '' : (a.net > 0 ? 'طلب ما' : 'بدهی ما'),
                style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => PartyDetailScreen(partyKeyValue: a.key))),
      ),
    );
  }
}

class PartyDetailScreen extends StatelessWidget {
  final String partyKeyValue;
  const PartyDetailScreen({super.key, required this.partyKeyValue});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppDb.I.version,
      builder: (_, __, ___) => FutureBuilder<List<PartyAccount>>(
        future: loadParties(),
        builder: (context, snap) {
          PartyAccount? a;
          if (snap.hasData) {
            for (final x in snap.data!) {
              if (x.key == partyKeyValue) a = x;
            }
          }
          return Scaffold(
            appBar: AppBar(title: Text(partyKeyValue.isEmpty ? 'بدون نام' : partyKeyValue)),
            body: a == null
                ? const Center(child: CircularProgressIndicator())
                : _body(context, a),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, PartyAccount a) {
    final scheme = Theme.of(context).colorScheme;
    final settled = a.net.abs() < 1;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Card(
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              if (a.bought > 0) ...[
                infoRow('جمع خرید از او', '${faNum(a.bought, dec: 0)} تومان'),
                infoRow('پرداخت‌شده به او', '${faNum(a.paid, dec: 0)} تومان'),
                infoRow('بدهی ما به او', '${faNum(a.weOwe, dec: 0)} تومان',
                    valueColor: a.weOwe > 0.5 ? Colors.red.shade800 : null),
              ],
              if (a.bought > 0 && a.sold > 0) const Divider(),
              if (a.sold > 0) ...[
                infoRow('جمع فروش به او', '${faNum(a.sold, dec: 0)} تومان'),
                infoRow('دریافت‌شده از او', '${faNum(a.received, dec: 0)} تومان'),
                infoRow('طلب ما از او', '${faNum(a.theyOwe, dec: 0)} تومان',
                    valueColor: a.theyOwe > 0.5 ? Colors.green.shade800 : null),
              ],
              if (a.bought > 0 && a.sold > 0) ...[
                const Divider(),
                infoRow(
                  settled ? 'تراز نهایی' : (a.net > 0 ? 'تراز نهایی: او به ما بدهکار است' : 'تراز نهایی: ما به او بدهکاریم'),
                  settled ? 'تسویه' : '${faNum(a.net.abs(), dec: 0)} تومان',
                ),
              ],
            ]),
          ),
        ),
        sectionTitle(context, 'خرید و فروش‌ها'),
        for (final e in a.entries) _entry(context, a, e),
      ],
    );
  }

  Widget _entry(BuildContext context, PartyAccount a, PartyEntry e) {
    final open = e.remaining > 0.5;
    return Card(
      key: ValueKey('${e.isPurchase}${e.id}'),
      child: ListTile(
        leading: Icon(e.isPurchase ? Icons.shopping_cart_outlined : Icons.sell_outlined),
        title: Text('${e.isPurchase ? 'خرید' : 'فروش'} ${e.label} • ${faNum(e.weight)} کیلو'),
        subtitle: Text(
          '${jalaliDateFromDt(e.date)}\n'
          'مبلغ ${faNum(e.total, dec: 0)} • تسویه‌شده ${faNum(e.settled, dec: 0)}'
          '${open ? ' • مانده ${faNum(e.remaining, dec: 0)}' : ' • تسویه کامل'}',
          style: TextStyle(color: open ? Theme.of(context).colorScheme.error : null),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_left),
        onTap: () {
          if (e.isPurchase) {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => PaymentScreen(
                        purchaseId: e.id, purchaseLabel: '${e.label} - ${jalaliDateFromDt(e.date)}')));
          } else {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ReceiptScreen(
                        saleId: e.id, saleLabel: '${a.name} - ${jalaliDateFromDt(e.date)}')));
          }
        },
      ),
    );
  }
}
