import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../components/my_button.dart';
import '../components/my_textfield.dart';
import '../components/squaretile.dart';
import '../services/auth_service.dart';

class RegisterPage extends StatefulWidget {
  final Function()? onTap;
  const RegisterPage({super.key, required this.onTap});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
  
}

class _RegisterPageState extends State<RegisterPage> {
  bool isLoading = false;

  // Controllers to manage user input from text fields
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  // Dispose controllers to free up memory when widget is destroyed
  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  // Function to handle user registration
void signUserUp() async {
  final email = emailController.text.trim();
  final password = passwordController.text.trim();
  final confirmPassword = confirmPasswordController.text.trim();

  if (email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
    _showDialog('Missing Fields', 'Please enter email, password, and confirm password.');
    return;
  }

  if (!email.endsWith('@adab.umpsa.edu.my')) {
    _showDialog('Invalid Email Domain', 'Please use your UMPSA email (@adab.umpsa.edu.my).');
    return;
  }

  if (password != confirmPassword) {
    _showDialog('Password Mismatch', 'Password and Confirm Password do not match.');
    return;
  }

  // Show loading spinner
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(child: CircularProgressIndicator()),
  );

  try {
    await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    Navigator.pop(context); // remove spinner
  } on FirebaseAuthException catch (e) {
    Navigator.pop(context);

    String errorMessage;
    switch (e.code) {
      case 'email-already-in-use':
        errorMessage = 'This email is already in use.';
        break;
      case 'invalid-email':
        errorMessage = 'This email address format is not valid.';
        break;
      case 'weak-password':
        errorMessage = 'The password is too weak.';
        break;
      default:
        errorMessage = 'Error: ${e.message ?? "Unknown error occurred."}';
    }

    _showDialog('Registration Failed', errorMessage);
  } catch (e) {
    Navigator.pop(context);
    _showDialog('Unexpected Error', 'Unexpected error: $e');
  }
}

  // Reusable method to show dialogs
void _showDialog(String title, String message) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 25),

                // User icon
            
                    const SizedBox(height: 20),
                    Image.asset(
      'lib/assets/images/logo.png', // path to your image
      width: 150,
      height: 180,
      fit: BoxFit.cover,
    ),

                // Welcome text
                const Text(
                  'Hi, Let\'s create an account for you',
                  style: TextStyle(
                    color: Color.fromARGB(255, 0, 0, 0),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 40),

                // Email TextField
                MyTextField(
                  controller: emailController,
                  hintText: 'Email address',
                  obscureText: false,
                ),
                const SizedBox(height: 20),

                // Password TextField
                MyTextField(
                  controller: passwordController,
                  hintText: 'Password',
                  obscureText: true,
                ),
                const SizedBox(height: 10),

                // Confirm Password TextField
                MyTextField(
                  controller: confirmPasswordController,
                  hintText: 'Confirm Password',
                  obscureText: true,
                ),

                const SizedBox(height: 25),

                // Sign Up Button
                MyButton(onTap: signUserUp, text: 'Sign Up'),
                const SizedBox(height: 35),

                // Divider with "or continue with"
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Divider(thickness: 0.5, color: Colors.grey[400]),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10.0),
                        child: Text(
                          'Or continue with',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ),
                      Expanded(
                        child: Divider(thickness: 0.5, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 50),
                

                // Third-party login buttons (Google)
                Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Transform.translate(
                        offset: Offset(1, -25), // move n pixels to the right and upwards 
                        
                        child: SquareTile(
                          
  imagePath: 'lib/assets/images/google.png',
  onTap: () async {
    setState(() => isLoading = true);

    try {
      final userCredential = await AuthService().signInWithGoogle();
      if (userCredential != null) {
        print("Logged in with: ${userCredential.user?.email}");
        // TODO: Navigate to home page after successful login
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-email-domain') {
        _showDialog(
          'Invalid Email',
          'Please use your UMPSA email (@adab.umpsa.edu.my) to sign in.',
        );
      } else {
        _showDialog('Login Failed', e.message ?? 'Unknown error occurred.');
      }
    } catch (e) {
      _showDialog('Error', 'An unexpected error occurred: $e');
    } finally {
      setState(() => isLoading = false);
    }
  },
),

                        ),
                        

                      ],
                    ),
                const SizedBox(height: 20),

                // Redirect to login page
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Have an account?',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: widget.onTap,
                      child: const Text(
                        'Login now',
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
