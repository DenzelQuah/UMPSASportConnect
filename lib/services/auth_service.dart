import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Sign in with Google with UMPSA domain restriction
  Future<UserCredential?> signInWithGoogle() async {
    try {
      print('Starting Google Sign-In...');
      // Force account picker by signing out first
      await _googleSignIn.signOut();
      print('Signed out of previous Google session.');

      // Begin sign-in process
      final GoogleSignInAccount? gUser = await _googleSignIn.signIn();
      if (gUser == null) {
        print('User cancelled Google Sign-In');
        return null;
      }
      print('Google user selected: \\${gUser.email}');

      // ✅ Restrict to UMPSA email domain (update comment for new project name)
      if (!gUser.email.endsWith('@adab.umpsa.edu.my')) {
        print('Email domain not allowed: \\${gUser.email}');
        // Show a dialog or throw with a clear message
        throw FirebaseAuthException(
          code: 'invalid-email-domain',
          message: 'Please use UMPSA Email to login.',
        );
      }

      // Obtain auth details
      final GoogleSignInAuthentication gAuth = await gUser.authentication;
      print('Google authentication obtained.');

      // Create new credential
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken,
        idToken: gAuth.idToken,
      );
      print('Firebase credential created.');

      // Sign in with Firebase
      final result = await _auth.signInWithCredential(credential);
      print('Firebase sign-in successful for: \\${result.user?.email}');
      return result;
    } catch (e, stack) {
      print('Google Sign-In Error: $e');
      print('Stack trace: $stack');
      rethrow; // Allow UI to handle errors with try-catch
    }
  }

  // Silent sign-in (if needed)
  Future<UserCredential?> signInSilently() async {
    try {
      final GoogleSignInAccount? gUser = await _googleSignIn.signInSilently();
      if (gUser == null) return null;

      if (!gUser.email.endsWith('@adab.umpsa.edu.my')) {
        throw FirebaseAuthException(
          code: 'invalid-email-domain',
          message: 'Please use your UMPSA email to sign in.',
        );
      }

      final GoogleSignInAuthentication gAuth = await gUser.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken,
        idToken: gAuth.idToken,
      );

      return await _auth.signInWithCredential(credential);
    } catch (e) {
      print('Silent Sign-In Error: $e');
      return null;
    }
  }

  // Sign out from Firebase and Google
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    print('User signed out successfully.');
  }

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Stream to listen to auth changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();
}
