import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/repo.dart';
import 'screens/home.dart';
import 'screens/lock_screen.dart';
import 'screens/onboarding.dart';
import 'services/lock.dart';
import 'services/notifications.dart';
import 'services/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  final repo = await Repo.open();
  await Notifier.init();
  await repo.processRecurring();
  final lock = LockController(settings);
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: repo),
      ChangeNotifierProvider.value(value: lock),
    ],
    child: const SilentWalletApp(),
  ));
}

class SilentWalletApp extends StatelessWidget {
  const SilentWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    ThemeData theme(Brightness b) => ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF2E7D6B),
          brightness: b,
        );
    return MaterialApp(
      title: 'Silent Wallet',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: settings.themeMode,
      home: const _Gate(),
    );
  }
}

class _Gate extends StatefulWidget {
  const _Gate();
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<Repo>().processRecurring();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final lock = context.watch<LockController>();
    if (!settings.onboarded) return const OnboardingScreen();
    return Stack(children: [
      const HomeScreen(),
      if (lock.locked) const Positioned.fill(child: LockScreen()),
    ]);
  }
}
