import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_lock.dart';
import 'backup_screen.dart';
import 'due_alert.dart';
import 'db_crypto.dart';
import 'dues_screen.dart';
import 'home_screen.dart';
import 'inventory_screen.dart';
import 'license_gate_screen.dart';
import 'live_query.dart';
import 'notify_service.dart';
import 'parties_screen.dart';
import 'purchases_screen.dart';
import 'renew_banner.dart';
import 'reports_screen.dart';
import 'sales_screen.dart';
import 'subscription_screen.dart';
import 'sync_service.dart';

void main() {
  // چترِ ایمنیِ سراسری: اگر جایی خطایی بدون try/catch رها شود (مثلاً یک استثنای
  // پیش‌بینی‌نشده‌ی دیتابیس)، به‌جای گم‌شدنِ بی‌صدا یا کرش کل اپ، حداقل لاگ می‌شود
  // و در حالت دیباگ روی کنسول دیده می‌شود.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    };

    if (Platform.isWindows || Platform.isLinux) {
      // دسکتاپ: دیتابیس SQLite از طریق FFI، و فایل‌ها در پوشهٔ داده‌های کاربر (نه کنار برنامه)
      databaseFactory = databaseFactoryFfi;
      final support = await getApplicationSupportDirectory();
      final dbDir = Directory(p.join(support.path, 'databases'));
      if (!await dbDir.exists()) await dbDir.create(recursive: true);
      await databaseFactory.setDatabasesPath(dbDir.path);
    }
    await DbCrypto.init();
    if (DbCrypto.initError != null) {
      runApp(_FatalApp(DbCrypto.initError!));
      return;
    }

    await AppLock.I.load();
    await NotifyService.I.init();
    // همگام‌سازی خودکار با سرور (ارسال تغییرات آفلاین + دریافت تغییرات سایر دستگاه‌ها)
    // نکته: یادآوری‌های سررسید بعد از ورود/باز شدن دیتابیس حساب در LicenseGate زمان‌بندی می‌شود.
    SyncService.I.start();
    runApp(const PestehApp());
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

/// خطای راه‌اندازیِ غیرقابل‌ادامه (مثلاً نبودن کلید رمزگشایی) — به‌جای ساختن دیتابیس خالی
class _FatalApp extends StatelessWidget {
  final String message;
  const _FatalApp(this.message);
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('پسته بازار\n\n$message', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.8)),
              ),
            ),
          ),
        ),
      );
}

class PestehApp extends StatelessWidget {
  const PestehApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'پسته بازار',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF5B7F2A), useMaterial3: true),
      builder: (context, child) {
        final body = Directionality(textDirection: TextDirection.rtl, child: child!);
        if (!Platform.isWindows) return body;
        // ویندوز: صفحه‌ها برای عرض گوشی طراحی شده‌اند؛ روی مانیتور بزرگ وسط و با عرض مناسب نمایش داده می‌شوند
        return ColoredBox(
          color: const Color(0xFFE9EDE6),
          child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1280), child: body)),
        );
      },
      home: const LicenseGate(child: RenewBannerHost(child: DueAlertHost(child: AppLockHost(child: HomeShell())))),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _i = activeTab.value;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _pages = [
    HomeScreen(),
    PurchasesScreen(),
    SalesScreen(),
    InventoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      body: IndexedStack(index: _i, children: _pages),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'moreMenu',
        tooltip: 'بیشتر (سررسید، طرف‌حساب، گزارش، اشتراک)',
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        child: const Icon(Icons.menu),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('پسته بازار', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.event_note_outlined),
                title: const Text('سررسیدها'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const DuesScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.people_alt_outlined),
                title: const Text('طرف‌حساب‌ها'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PartiesScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.assessment_outlined),
                title: const Text('گزارش سود و زیان'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()));
                },
              ),
              if (Platform.isWindows) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('پشتیبان‌گیری'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('قفل برنامه'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SecurityScreen()));
                  },
                ),
              ],
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('اشتراک من'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
                },
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (v) {
          activeTab.value = v; // تب جدید در صورت نیاز داده‌هایش را تازه می‌کند
          setState(() => _i = v);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'خانه'),
          NavigationDestination(icon: Icon(Icons.shopping_cart_outlined), label: 'خرید'),
          NavigationDestination(icon: Icon(Icons.sell_outlined), label: 'فروش'),
          NavigationDestination(icon: Icon(Icons.warehouse_outlined), label: 'موجودی'),
        ],
      ),
    );
  }
}
