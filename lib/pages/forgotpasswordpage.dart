import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class forgetPasswordPage extends StatefulWidget {
  const forgetPasswordPage({super.key});

  @override
  State<forgetPasswordPage> createState() => _ForgetPasswordPageState();
}

class _ForgetPasswordPageState extends State<forgetPasswordPage> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _isValidEmail = false;

  @override
  void initState() {
    super.initState();
    // Listen to email field changes to validate email format
    _emailController.addListener(_validateEmail);
  }

  @override
  void dispose() {
    _emailController.removeListener(_validateEmail);
    _emailController.dispose();
    super.dispose();
  }

  // Validate email format - only allow @adab.umpsa.edu.my domain
  bool _isEmailValid(String email) {
    return RegExp(r'^[\w-\.]+@adab\.umpsa\.edu\.my$').hasMatch(email);
  }

  // Validate email format only
  void _validateEmail() {
    final email = _emailController.text.trim();
    setState(() {
      _isValidEmail = email.isNotEmpty && _isEmailValid(email);
    });
  }

  // Check if user exists by attempting to create account (more reliable method)
  Future<bool> _checkUserExistsByCreation(String email) async {
    try {
      // Try to create a user with this email - if it succeeds, user didn't exist
      UserCredential credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: email,
            password: 'TEMP_PASSWORD_TO_CHECK_123!@#',
          );

      // If we get here, user didn't exist before, so we need to delete this temp user
      await credential.user?.delete();

      // Return false because user didn't exist originally
      return false;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'email-already-in-use':
          // This means the user already exists!
          return true;
        case 'invalid-email':
          throw FirebaseAuthException(
            code: 'invalid-email',
            message: 'The email address is not valid.',
          );
        case 'weak-password':
          // This shouldn't happen with our password, but if it does,
          // it means the email validation passed, so user might not exist
          return false;
        default:
          // For other errors, assume user exists to be safe
          return true;
      }
    } catch (e) {
      print('Unexpected error in _checkUserExistsByCreation: $e');
      return true;
    }
  }

  // Password reset function with proper user existence validation
  Future<void> passwordReset() async {
    final email = _emailController.text.trim();

    // Validate email format
    if (email.isEmpty) {
      _showErrorDialog('Please enter your email address');
      return;
    }

    if (!_isValidEmail) {
      _showErrorDialog('Please enter a valid @adab.umpsa.edu.my email address');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Set language to English for consistent error messages
      await FirebaseAuth.instance.setLanguageCode('en');

      // Check if user exists using the creation method
      print('Checking if user exists: $email');
      bool userExists = await _checkUserExistsByCreation(email);

      if (!userExists) {
        _showErrorDialog(
          'User Not Found',
          'No ADAB UMPSA account found with this email address.\n\n'
              'Please check:\n'
              '• Your email spelling is correct\n'
              '• You have registered an account with this email\n',
        );
        return;
      }

      print('User exists, sending password reset email...');

      // User exists, now send the password reset email
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      // Show success dialog
      await _showSuccessDialog(email);

      // Navigate back to login page after success
      if (mounted) {
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      String errorTitle = 'Error';

      print('FirebaseAuthException in passwordReset: ${e.code} - ${e.message}');

      switch (e.code) {
        case 'user-not-found':
          errorTitle = 'User Not Found';
          errorMessage =
              'No ADAB UMPSA account found with this email address.\n\n'
              'Please check:\n'
              '• Your email spelling is correct\n'
              '• You have registered an account with this email\n'
              '• Contact your administrator if you need assistance';
          break;
        case 'invalid-email':
          errorMessage =
              'The email address format is invalid. Please enter a valid @adab.umpsa.edu.my email address.';
          break;
        case 'too-many-requests':
          errorMessage =
              'Too many password reset requests. Please wait a few minutes before trying again.';
          break;
        case 'user-disabled':
          errorMessage =
              'This account has been disabled. Please contact your administrator for assistance.';
          break;
        case 'network-request-failed':
          errorMessage =
              'Network connection failed. Please check your internet connection and try again.';
          break;
        default:
          errorMessage =
              'Error: ${e.message ?? 'An unexpected error occurred'}';
      }

      _showErrorDialog(errorTitle, errorMessage);
    } catch (e) {
      print('Unexpected error in passwordReset: $e');
      // Handle any other unexpected errors
      _showErrorDialog(
        'Error',
        'An unexpected error occurred. Please try again later.\n\n'
            'If the problem persists, please contact technical support.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Show success dialog
  Future<void> _showSuccessDialog(String email) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 10),
              Text('Reset Email Sent'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A password reset link has been sent to:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 8),
              Text(
                email,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              SizedBox(height: 16),
              Text('Please check:'),
              Text('• Your inbox'),
              Text('• Your spam/junk folder'),
              SizedBox(height: 16),
              Text(
                'The link will expire in 1 hour.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'OK',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  // Show error dialog with title and message
  void _showErrorDialog(String title, [String? message]) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error, color: Colors.red, size: 28),
              SizedBox(width: 10),
              Text(title),
            ],
          ),
          content: SingleChildScrollView(child: Text(message ?? title)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'OK',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 0, 25, 116),
        title: const Text('Reset Password'),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // instruction text
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25.0),
            child: const Text(
              'Enter Your Email Address to Reset Password',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
          ),

          const SizedBox(height: 10),

          const Text(
            'We will send you a link to reset your password',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),

          const SizedBox(height: 30),

          // email input field with validation indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25.0),
            child: TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: _isValidEmail ? Colors.green : Colors.grey,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(
                    color: Colors.deepPurple,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                hintText: 'Email (e.g., student@adab.umpsa.edu.my)',
                fillColor: Colors.grey[200],
                filled: true,
                prefixIcon: const Icon(Icons.email),
                suffixIcon:
                    _emailController.text.isNotEmpty
                        ? Icon(
                          _isValidEmail ? Icons.check_circle : Icons.error,
                          color: _isValidEmail ? Colors.green : Colors.red,
                        )
                        : null,
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Status text
          if (_emailController.text.isNotEmpty)
            Text(
              _isValidEmail
                  ? 'Valid ADAB UMPSA email ✓'
                  : 'Please use @adab.umpsa.edu.my email',
              style: TextStyle(
                color: _isValidEmail ? Colors.green : Colors.red,
                fontSize: 12,
              ),
            ),

          const SizedBox(height: 20),

          // reset button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25.0),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: MaterialButton(
                onPressed:
                    (_isLoading || !_isValidEmail) ? null : passwordReset,
                color:
                    _isValidEmail ? Colors.deepPurple[200] : Colors.grey[300],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                          'Reset Password',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Additional help text
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25.0),
            child: Text(
              'Having trouble? Make sure you\'re using the email address you registered with.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
