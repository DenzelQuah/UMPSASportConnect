import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../pages/feedback.dart';
import '../pages/skillreview.dart';

class MyDrawer extends StatefulWidget {
  const MyDrawer({super.key});

  @override
  State<MyDrawer> createState() => _MyDrawerState();
}

class _MyDrawerState extends State<MyDrawer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(-1.0, 0.0), // Slide in from left
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward(); // Start the animation
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: SlideTransition(
        position: _slideAnimation,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Logo and Menu Items
            Column(
              children: [
                DrawerHeader(
                  child: Center(
                    child: Image.asset(
                      'lib/assets/images/logo.png', // path to your image
                      width: 150,
                      height: 180,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

                _buildDrawerItem(
                  title: 'H O M E',
                  icon: Icons.home,
                  onTap: () => Navigator.pop(context),
                ),

                _buildDrawerItem(
                  title: 'S K I L L R E V I E W',
                  icon: Icons.reviews,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => SkillReviewPage()),
                    );
                  },
                ),

                _buildDrawerItem(
                  title: 'F E E D B A C K',
                  icon: Icons.feedback_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => FeedbackPage()),
                    );
                  },
                ),
              ],
            ),

            // Logout
            Padding(
              padding: const EdgeInsets.only(left: 20.0, bottom: 25.0, top: 20),
              child: ListTile(
                title: const Text('L O G O U T'),
                leading: const Icon(Icons.login_outlined),
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  Navigator.pushReplacementNamed(context, '/login');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 25.0),
      child: ListTile(
        title: Text(title),
        leading: Icon(icon),
        onTap: onTap,
      ),
    );
  }
}
