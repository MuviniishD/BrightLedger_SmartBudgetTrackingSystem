import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';

// Services
import 'services/auth_service.dart';
import 'services/firestore_service.dart';

// ViewModels
import 'viewmodels/auth_viewmodel.dart';
import 'viewmodels/home_viewmodel.dart';
import 'viewmodels/add_viewmodel.dart';
import 'viewmodels/records_viewmodel.dart';
import 'viewmodels/stats_viewmodel.dart';
import 'viewmodels/account_viewmodel.dart';
import 'viewmodels/financial_chat_viewmodel.dart';

// Utils & Theme
import 'utils/app_theme.dart';
import 'utils/tab_notifier.dart';
import 'services/notification_service.dart';

// Views
import 'views/login_screen.dart';
import 'views/main_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // This is the specific command to tell Firebase to completely REMOVE and DISABLE reCAPTCHA verification!
  await FirebaseAuth.instance.setSettings(appVerificationDisabledForTesting: true);

  // Initialize daily reminder notifications
  final notificationService = NotificationService();
  await notificationService.initialize();
  await notificationService.scheduleDailyReminder(hour: 9, minute: 0);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Initialise core services
    final authService = AuthService();
    final firestoreService = FirestoreService();

    return MultiProvider(
      providers: [
        Provider<AuthService>.value(value: authService),
        Provider<FirestoreService>.value(value: firestoreService),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(
          create: (_) => AuthViewModel(authService, firestoreService),
        ),
        ChangeNotifierProvider(
          create: (_) => HomeViewModel(firestoreService),
        ),
        ChangeNotifierProvider(
          create: (_) => AddViewModel(firestoreService),
        ),
        ChangeNotifierProvider(
          create: (_) => RecordsViewModel(firestoreService),
        ),
        ChangeNotifierProvider(
          create: (_) => StatsViewModel(firestoreService),
        ),
        ChangeNotifierProvider(
          create: (_) => AccountViewModel(authService, firestoreService),
        ),
        ChangeNotifierProvider(
          create: (_) => FinancialChatViewModel(),
        ),
        ChangeNotifierProvider(
          create: (_) => TabNotifier(),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Bright Ledger',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return StreamBuilder(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // If user is authenticated, route to MainShell, else to LoginScreen
        if (snapshot.hasData && snapshot.data != null) {
          return const MainShell();
        }

        return const LoginScreen();
      },
    );
  }
}
