// lib/main.dart
// ─────────────────────────────────────────────────────────────────
// Production app entry point.
//
// Startup order (critical):
//  1. Flutter engine
//  2. Firebase Core
//  3. Crashlytics (catch errors from step 4 onward)
//  4. Firebase App Check (block unauthenticated API calls)
//  5. Firestore offline persistence
//  6. runApp
// ─────────────────────────────────────────────────────────────────

import 'services/auth_service.dart';
import 'services/progress_service.dart';
import 'services/analytics_service.dart';
import 'services/crashlytics_service.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/chapter_screen.dart';
import 'screens/camera_screen.dart';
import 'screens/progress_screen.dart';
import 'screens/doubt_solver_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/doubt_history_screen.dart';
import 'screens/legal/privacy_policy_screen.dart';
import 'screens/legal/terms_screen.dart';
import 'screens/legal/account_deletion_screen.dart';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global widget error fallback (prevents red-screen crash loops in release).
  ErrorWidget.builder = (details) {
    return Material(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Something went wrong.\n\n${details.exception}',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  };

  runZonedGuarded(
    () => runApp(const AppBootstrap()),
    (error, stack) async {
      // Firebase may not be initialized yet. Record best-effort.
      try {
        await CrashlyticsService.instance.logNonFatal(
          error,
          stack,
          reason: 'runZonedGuarded',
        );
      } catch (_) {
        // ignore
      }
    },
  );
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late final Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initialize();
  }

  Future<void> _initialize() async {
    // ── 1. Firebase Core ────────────────────────────────────────
    //
    // NOTE:
    // We intentionally initialize Firebase WITHOUT firebase_options.dart here.
    // This keeps the project buildable with only:
    //   • android/app/google-services.json
    //   • ios/Runner/GoogleService-Info.plist
    //
    await Firebase.initializeApp();

    // ── 2. Crashlytics ──────────────────────────────────────────
    await CrashlyticsService.instance.initialize();

    // ── 3. Firebase App Check ───────────────────────────────────
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.deviceCheck,
    );

    // ── 4. Firestore offline persistence ────────────────────────
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: _FatalStartupError(error: snap.error),
          );
        }
        if (snap.connectionState != ConnectionState.done) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: _SplashScreen(),
          );
        }

        return MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthService()),
            ChangeNotifierProvider(create: (_) => ProgressService()),
          ],
          child: MaterialApp(
            title: 'CBSE Maths Tutor',
            debugShowCheckedModeBanner: false,

            // Attach Analytics navigator observer for automatic screen tracking
            navigatorObservers: [AnalyticsService.instance.observer],

            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
              useMaterial3: true,
              fontFamily: 'Roboto',
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.indigo,
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
              fontFamily: 'Roboto',
            ),
            themeMode: ThemeMode.system,

            // Auth-gated home
            home: Consumer<AuthService>(
              builder: (context, auth, _) {
                switch (auth.state) {
                  case AuthState.authenticated:
                    return const DashboardScreen();
                  case AuthState.idle:
                  case AuthState.error:
                    return const LoginScreen();
                  default:
                    return const LoginScreen();
                }
              },
            ),

            routes: {
              '/login': (_) => const LoginScreen(),
              '/dashboard': (_) => const DashboardScreen(),
              '/chapter': (_) => const ChapterScreen(),
              '/camera': (_) => const CameraScreen(),
              '/progress': (_) => const ProgressScreen(),
              '/doubt_solver': (_) => const DoubtSolverScreen(),
              '/doubts': (_) => const DoubtHistoryScreen(),
              '/profile': (_) => const ProfileScreen(),

              // Legal
              '/privacy': (_) => const PrivacyPolicyScreen(),
              '/terms': (_) => const TermsScreen(),
              '/account_deletion': (_) => const AccountDeletionScreen(),
            },
            onUnknownRoute: (settings) => MaterialPageRoute(
              builder: (_) => _UnknownRouteScreen(routeName: settings.name),
            ),
          ),
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('CBSE Maths Tutor', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class _FatalStartupError extends StatelessWidget {
  final Object? error;
  const _FatalStartupError({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 52, color: Colors.red),
              const SizedBox(height: 12),
              const Text(
                'App failed to start',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnknownRouteScreen extends StatelessWidget {
  final String? routeName;
  const _UnknownRouteScreen({required this.routeName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Page not found'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 52),
              const SizedBox(height: 12),
              Text(
                'Unknown route: ${routeName ?? '(null)'}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/dashboard',
                    (_) => false,
                  ),
                  child: const Text('Go to Dashboard'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
