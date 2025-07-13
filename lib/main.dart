import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'pages/authentic.dart';
import 'pages/login_or_register.dart';
import 'pages/splash_page.dart';
import 'services/notification_service.dart';

// Global navigator key for notifications
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Initialize notification service if user is logged in
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser != null) {
    await NotificationService().initialize();
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // Add navigator key for notifications
      debugShowCheckedModeBanner: false,
      home: const SplashPage(), // CHANGE: Start with splash page
      title: 'UMPSA Sport Connect FYP',
      theme: FlexThemeData.light(
        primary: const Color(0xFF0A192F), // dark blue for text/icons
        primaryContainer: const Color(0xFFF6F8FA), // very light grey for backgrounds
        secondary: const Color(0xFF0077B6), // blue accent
        secondaryContainer: const Color(0xFFE3F2FD), // light blue
        tertiary: Colors.orangeAccent,
        tertiaryContainer: const Color(0xFF6C7C78), // muted green/grey

        surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
        blendLevel: 9,
        subThemesData: const FlexSubThemesData(
          blendOnLevel: 10,
          blendOnColors: false,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
      darkTheme: FlexThemeData.dark(
        primary: const Color(0xFF64B5F6), // lighter blue for dark mode
        primaryContainer: const Color(0xFF1A1A1A), // dark grey for backgrounds
        secondary: const Color(0xFF42A5F5), // blue accent for dark mode
        secondaryContainer: const Color(0xFF263238), // dark blue-grey
        tertiary: Colors.orangeAccent,
        tertiaryContainer: const Color(0xFF455A64), // muted blue-grey

        surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
        blendLevel: 9,
        subThemesData: const FlexSubThemesData(
          blendOnLevel: 10,
          blendOnColors: false,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
    );
  }
}

// Alternative approach: Create a wrapper widget that handles the auth flow
class AppWrapper extends StatelessWidget {
  const AppWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show splash first, then navigate based on auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashPage();
        }
        
        // Initialize notification service when user logs in
        if (snapshot.hasData && snapshot.data != null) {
          NotificationService().initialize();
          return const AuthenticPage();
        }
        return const LoginOrRegisterPage();
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // Add your home page content here
          ],
        ),
      ),
    );
  }
}