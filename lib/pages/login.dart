import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../components/my_button.dart';
import '../components/my_textfield.dart';
import '../components/squaretile.dart';
import '../services/auth_service.dart';
import 'authentic.dart';
import 'forgotpasswordpage.dart';

class LoginPage extends StatefulWidget {
  final Function()? onTap;
  const LoginPage({super.key, required this.onTap});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;

  void signUserIn() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    // Validate input
    if (email.isEmpty || password.isEmpty) {
      _showDialog('Missing Fields', 'Please enter both email and password.');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      _showSnackBar(
        'Invalid Email Format',
        'Please enter a valid email address.',
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      print("Trying to sign in with email: $email");
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      setState(() {
        isLoading = false;
      });

      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthenticPage()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        isLoading = false;
      });

      if (e.code == 'user-not-found' || e.code == 'invalid-email') {
        _showDialog('Login Failed', 'Please use UMPSA email to login.');
      } else if (e.code == 'wrong-password') {
        _showSnackBar('Incorrect Password', 'Please try again.');
      } else {
        _showDialog('Login Failed', e.message ?? 'Unknown error occurred.');
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      print("Unexpected error: $e");
      _showSnackBar('Error', 'Unexpected error: $e');
    }
  }

  void _showDialog(String title, String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  void _showSnackBar(String title, String message) {
    final snackBar = SnackBar(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(message),
        ],
      ),
      behavior: SnackBarBehavior.floating,
    );
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 60),
                    Image.asset(
                      'lib/assets/images/logo.png', // path to your image
                      width: 150,
                      height: 180,
                      fit: BoxFit.cover,
                    ),

                    const SizedBox(height: 20),
                    Text(
                      'Welcome back, UMPSA Sporties!',
                      style: TextStyle(
                        color: const Color.fromARGB(255, 0, 0, 0),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 40),
                    MyTextField(
                      controller: emailController,
                      hintText: 'Email address',
                      obscureText: false,
                    ),
                    const SizedBox(height: 20),
                    MyTextField(
                      controller: passwordController,
                      hintText: 'Password',
                      obscureText: true,
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 25.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => forgetPasswordPage(),
                                ),
                              );
                            },
                            child: Text(
                              'Forgot Password?',
                              style: TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 25),
                    MyButton(onTap: signUserIn, text: 'Sign In'),
                    const SizedBox(height: 50),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 25.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Divider(
                              thickness: 0.5,
                              color: Colors.grey[400],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10.0,
                            ),
                            child: Text(
                              'Or continue with',
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              thickness: 0.5,
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 25),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Transform.translate(
                          offset: Offset(1, 0), // move 10 pixels to the right
                          child: SquareTile(
                            imagePath: 'lib/assets/images/google.png',
                            onTap: () async {
                              setState(() => isLoading = true);

                              try {
                                final userCredential =
                                    await AuthService().signInWithGoogle();
                                if (userCredential != null) {
                                  print(
                                    "Logged in with: \\${userCredential.user?.email}",
                                  );
                                  if (context.mounted) {
                                    Navigator.of(context).pushAndRemoveUntil(
                                      MaterialPageRoute(builder: (_) => const AuthenticPage()),
                                      (route) => false,
                                    );
                                  }
                                }
                              } on FirebaseAuthException catch (e) {
                                if (e.code == 'invalid-email-domain') {
                                  _showDialog(
                                    'Invalid Email',
                                    'Please use your UMPSA email (@adab.umpsa.edu.my) to sign in.',
                                  );
                                } else {
                                  _showDialog(
                                    'Login Failed',
                                    e.message ?? 'Unknown error occurred.',
                                  );
                                }
                              } catch (e) {
                                _showDialog(
                                  'Error',
                                  'An unexpected error occurred: $e',
                                );
                              } finally {
                                setState(() => isLoading = false);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 25),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Not a member?',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: widget.onTap,
                          child: const Text(
                            'Register now',
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
            // Display a loading indicator when isLoading is true
            if (isLoading)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
