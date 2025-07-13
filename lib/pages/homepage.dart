import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/drawable.dart';
import 'UserListPage.dart';
import 'UserPublicProfilePage.dart';
import 'chat.dart';
import 'communication.dart';
import 'event.dart';
import 'host.dart';
import 'hostrequest.dart';
import 'profile.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final user = FirebaseAuth.instance.currentUser;
  int _currentIndex = 0;
  String? username;
  String? profileImageUrl;
  late final AnimationController _animationController;
  int _refreshKey = 0; // Moved to class level

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    _checkAndPromptUsername();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animationController.forward();

    // Check for any pending notifications that should navigate the user to chats
    _checkPendingNavigationNotifications();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // --------------------------- Firebase Auth ---------------------------

  void logout() {
    FirebaseAuth.instance.signOut();
  }
  
  void refreshRecentActivity() {
    setState(() {
      _refreshKey++;
    });
  }

  Future<void> _fetchUserData() async {
    final uid = user!.uid;
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    if (userDoc.exists) {
      final data = userDoc.data()!;
      setState(() {
        username = data['username'];
        profileImageUrl = data['profileImageUrl'];
      });
    }
  }

  Future<void> _checkAndPromptUsername() async {
    final uid = user!.uid;
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    if (!userDoc.exists ||
        (userDoc.data()?['username'] == null ||
            userDoc.data()!['username'].toString().isEmpty)) {
      _askForUsername(uid);
    }
  }

  Future<void> _askForUsername(String uid) async {
    final TextEditingController controller = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Text("Set Your Username"),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: "Username"),
            ),
            actions: [
              ElevatedButton(
                onPressed: () async {
                  final enteredUsername = controller.text.trim();
                  if (enteredUsername.isNotEmpty) {
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .set({
                          'username': enteredUsername,
                          'email': user!.email,
                        }, SetOptions(merge: true));

                    if (!mounted) return;
                    setState(() {
                      username = enteredUsername;
                    });

                    Navigator.pop(context); // Close the input dialog

                    // Show welcome dialog
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder:
                          (context) => AlertDialog(
                            content: Row(
                              children: [
                                const Icon(
                                  Icons.waving_hand_outlined,
                                  size: 28,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text("Welcome, $enteredUsername!"),
                                ),
                              ],
                            ),
                            actions: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      if (!context.mounted) return;
                                      Navigator.of(
                                        context,
                                        rootNavigator: true,
                                      ).pop();
                                    },
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                    );
                    // Auto-close after 2 seconds
                    Future.delayed(const Duration(seconds: 2), () {
                      if (!context.mounted) return;
                      Navigator.of(context, rootNavigator: true).pop();
                    });
                  }
                },
                child: const Text("Save"),
              ),
            ],
          ),
    );
  }

  Future<List<Map<String, dynamic>>> fetchAllUsersExceptCurrent() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final snapshot = await FirebaseFirestore.instance.collection('users').get();

    return snapshot.docs
        .where((doc) => doc.id != currentUser?.uid)
        .map((doc) => {...doc.data(), 'id': doc.id})
        .toList();
  }


// Replace the global fetchUpcomingEvents function at the bottom of your file with this:
Future<List<Map<String, dynamic>>> fetchUpcomingEvents() async {
  final snapshot = await FirebaseFirestore.instance.collection('events').get();
  final now = DateTime.now();

  return snapshot.docs
      .map((doc) {
        final data = doc.data();
        final dateStr = data['date'] ?? '';
        final startTimeStr = data['startTime'] ?? '';
        final endTimeStr = data['endTime'] ?? '';

        try {
          final date = DateFormat('dd-MM-yyyy').parse(dateStr).toLocal();
          final startTime = DateFormat('h:mm a').parse(startTimeStr).toLocal();
          final endTime = DateFormat('h:mm a').parse(endTimeStr).toLocal();

          final startDateTime = DateTime(
            date.year,
            date.month,
            date.day,
            startTime.hour,
            startTime.minute,
          );
          DateTime endDateTime = DateTime(
            date.year,
            date.month,
            date.day,
            endTime.hour,
            endTime.minute,
          );

          // Handle overnight events
          if (endTime.isBefore(startTime)) {
            endDateTime = endDateTime.add(Duration(days: 1));
          }

          // Determine status inline instead of calling _getEventStatus
          String status;
          if (now.isBefore(startDateTime)) {
            status = 'Upcoming';
          } else if (now.isAfter(startDateTime) && now.isBefore(endDateTime)) {
            status = 'Ongoing';
          } else {
            status = 'Finished';
          }

          if (status == 'Upcoming') {
            return {...data, 'id': doc.id};
          }
        } catch (e) {
          return null;
        }
        return null;
      })
      .whereType<Map<String, dynamic>>()
      .toList();
}

  // --------------------------- UI Build ---------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 255), // primary
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 0, 25, 116),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfilePage(onTap: () {}),
                  ),
                ).then((_) {
                  // Refresh user data when returning from profile page
                  _fetchUserData();
                });
              },
              child: CircleAvatar(
                backgroundImage:
                    profileImageUrl != null && profileImageUrl!.isNotEmpty
                        ? NetworkImage(profileImageUrl!)
                        : const AssetImage("assets/default_profile.png")
                            as ImageProvider,
                radius: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Welcome, ${username?.isNotEmpty == true ? username : 'User'}",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: logout,
            icon: const Icon(Icons.logout, color: Colors.white),
          ),
        ],
        elevation: 4,
      ),
      drawer: MyDrawer(),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white,
              const Color.fromARGB(
                255,
                0,
                25,
                116,
              ).withOpacity(0.06), // secondary hint
              Colors.amber.withOpacity(0.08), // secondaryContainer accent
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _refreshHomePage,
          color: const Color.fromARGB(255, 0, 25, 116),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 80),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              // Banner
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 5),
                child: SizedBox(
                  height: 300, // Increased height for a bigger dashboard slider
                  child: _AutoSlidingImageSlider(),
                ),
              ),
              const SizedBox(height: 20),
              // Activity Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.flash_on, color: Colors.orangeAccent), // tertiary
                    const SizedBox(width: 8),
                    Text(
                      'Activity',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: const Color.fromARGB(255, 0, 25, 116), // secondary
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _modernShortcutBox(
                      label: 'Events',
                      icon: Icons.event,
                      color: const Color.fromARGB(255, 0, 25, 116),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) => EventPage(
                                  onTap: () {},
                                  event: {},
                                  eventId: '',
                                  searchQuery: '',
                                ),
                          ),
                        ).then((_) => setState(() => _currentIndex = 0));
                      },
                    ),
                    const SizedBox(width: 16),
                    _modernShortcutBox(
                      label: 'Chat',
                      icon: Icons.chat,
                      color: Colors.orangeAccent,
                      onTap:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => ChatPage()),
                          ).then((_) => setState(() => _currentIndex = 0)),
                    ),
                    const SizedBox(width: 16),
                    _modernShortcutBox(
                      label: 'Manage Requests',
                      icon:
                          Icons
                              .how_to_reg, // Changed icon to represent request management
                      color: Colors.amber,
                      onTap:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const HostRequestsPage(),
                            ),
                          ).then((_) => setState(() => _currentIndex = 0)),
                    ),
                    const SizedBox(width: 16),
                    _modernShortcutBox(
                      label: 'Host',
                      icon: Icons.add_box_rounded,
                      color: const Color.fromARGB(
                        255,
                        108,
                        124,
                        120,
                      ), // tertiaryContainer
                      onTap:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const HostPage(),
                            ),
                          ).then((_) => setState(() => _currentIndex = 0)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 21),

              // Recent Activity Header & Card Combined
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  color: Colors.blueGrey.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Recent Activity Header
                        Row(
                          children: [
                            Icon(
                              Icons.history,
                              color: Colors.blueGrey.shade700,
                              size: 28,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Recent Activity',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Recent Activity List - Using FutureBuilder for upcoming events
                        FutureBuilder<List<Map<String, dynamic>>>(
                          key: ValueKey(_refreshKey), // Add this line for refresh functionality
                          future: fetchUpcomingEvents(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (snapshot.hasError) {
                              return const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('Failed to load events.'),
                              );
                            }
                            final events = snapshot.data ?? [];
                            if (events.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('No upcoming events.'),
                              );
                            }
                            return Column(
                              children:
                                  events.take(3).map((event) {
                                    return Card(
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: ListTile(
                                        leading:
                                            event['imageUrl'] != null &&
                                                    event['imageUrl']
                                                        .toString()
                                                        .isNotEmpty
                                                ? ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        8,
                                                      ),
                                                  child: Image.network(
                                                    event['imageUrl'],
                                                    width: 50,
                                                    height: 50,
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) => const Icon(
                                                          Icons.event,
                                                        ),
                                                  ),
                                                )
                                                : const Icon(Icons.event),
                                        title: Text(event['eventName'] ?? 'Unknown Event'),
                                        subtitle: Text(
                                          '${event['sport']} • ${event['date']} at ${event['startTime']}',
                                        ),
                                        trailing: const Icon(
                                          Icons.arrow_forward,
                                        ),
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder:
                                                  (context) => EventPage(
                                                    event: event,
                                                    onTap: () {},
                                                    eventId: event['id'],
                                                    searchQuery:
                                                        event['eventName'] ?? '',
                                                  ),
                                            ),
                                          ).then((_) {
                                            setState(() {
                                              _currentIndex = 0;
                                              _refreshKey++; // This will trigger the FutureBuilder to rebuild
                                            });
                                          });
                                        },
                                      ),
                                    );
                                  }).toList(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Browse Users Header and Users List Combined
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Card(
                  color: Colors.blueGrey.shade50,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.people_alt_rounded,
                                  color: Colors.blueGrey.shade700,
                                  size: 22,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'BROWSE USERS',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const UserListPage(),
                                  ),
                                );
                              },
                              child: const Text('View All'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.blueGrey.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 120,
                          child: FutureBuilder<List<Map<String, dynamic>>>(
                            future: fetchAllUsersExceptCurrent(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              } else if (snapshot.hasError) {
                                return const Center(
                                  child: Text('Error loading users.'),
                                );
                              } else if (!snapshot.hasData ||
                                  snapshot.data!.isEmpty) {
                                return const Center(
                                  child: Text('No other users found.'),
                                );
                              }
                              final users = snapshot.data!;
                              final displayedUsers = users.take(10).toList();
                              return ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: displayedUsers.length,
                                separatorBuilder:
                                    (context, index) => const SizedBox(width: 12),
                                itemBuilder: (context, index) {
                                  final user = displayedUsers[index];
                                  final profileImage = user['profileImageUrl'];
                                  return GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (context) => UserPublicProfilePage(
                                                user: user,
                                              ),
                                        ),
                                      );
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 150),
                                      curve: Curves.easeInOut,
                                      width: 100,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black12,
                                            blurRadius: 8,
                                            offset: Offset(0, 4),
                                          ),
                                        ],
                                        border: Border.all(
                                          color: Colors.grey.shade200,
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                        horizontal: 8,
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          CircleAvatar(
                                            backgroundImage:
                                                profileImage != null &&
                                                        profileImage
                                                            .toString()
                                                            .isNotEmpty
                                                ? NetworkImage(profileImage)
                                                : const AssetImage(
                                                      "assets/default_profile.png",
                                                    )
                                                    as ImageProvider,
                                            radius: 28,
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            user['username'] ?? 'Unnamed',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                              color: Colors.black87,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      bottomNavigationBar: CurvedNavigationBar(
        backgroundColor: const Color.fromARGB(255, 0, 25, 116), // secondary
        color: Colors.white, // primary
        items: const [
          Icon(
            Icons.home,
            color: Color.fromARGB(255, 0, 25, 116),
          ), // secondaryContainer accent
          Icon(Icons.event, color: Color.fromARGB(255, 0, 25, 116)), // tertiary
          Icon(Icons.add, color: Color.fromARGB(255, 0, 25, 116)), // secondary
          Icon(Icons.chat, color: Color.fromARGB(255, 0, 25, 116)), // tertiary
          Icon(
            Icons.people_alt_sharp,
            color: Color.fromARGB(255, 0, 25, 116),
          ), // tertiaryContainer
        ],
        index: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });

          switch (index) {
            case 0:
              break;
            case 1:
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) =>
                          EventPage(onTap: () {}, event: {}, eventId: ''),
                ),
              ).then((_) => setState(() => _currentIndex = 0));
              break;
            case 2:
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HostPage()),
              ).then((_) => setState(() => _currentIndex = 0));
              break;
            case 3:
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ChatPage()),
              ).then((_) => setState(() => _currentIndex = 0));
              break;
            case 4:
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfilePage(onTap: () {}),
                ),
              ).then((_) => setState(() => _currentIndex = 0));
              break;
          }
        },
      ),
    );
  }

  // --------------------------- Body View ---------------------------

  // IMAGE SLIDER
  Widget imageSlider() {
    final List<String> imagePaths = [
      'lib/assets/images/dashboard1.png',
      'lib/assets/images/logo.png',
      'lib/assets/images/logo.png',
    ];

    return SizedBox(
      height: 240,
      child: PageView.builder(
        itemCount: imagePaths.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                imagePaths[index],
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          );
        },
      ),
    );
  }

  // Modern shortcut button
  Widget _modernShortcutBox({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 90,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.10),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.85),
              radius: 24,
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // Check for notifications that should navigate the user to specific chats
  Future<void> _checkPendingNavigationNotifications() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;
      
      // Query for unread notifications that require navigation
      final notificationsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .where('actionType', isEqualTo: 'navigate_to_chat')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();
          
      if (notificationsSnapshot.docs.isNotEmpty) {
        final notification = notificationsSnapshot.docs.first;
        final notificationData = notification.data();
        final chatId = notificationData['actionData'] as String?;
        
        if (chatId != null && chatId.isNotEmpty) {
          // Mark notification as read
          await notification.reference.update({'read': true});
          
          // Navigate to the chat after a short delay to let the UI render
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!mounted) return;
            
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CommunicationPage(chatId: chatId),
              ),
            ).then((_) => setState(() => _currentIndex = 0));
            
            // Show confirmation message
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('You\'ve been added to ${notificationData['eventName'] ?? 'an event'} chat!'),
                duration: const Duration(seconds: 3),
              ),
            );
          });
        }
      }
    } catch (e) {
      print('Error checking pending notifications: $e');
    }
  }

  // Add a refresh function that updates all necessary data
  Future<void> _refreshHomePage() async {
    try {
      // Show refresh indicator with delay to provide visual feedback
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Refresh user data
      await _fetchUserData();
      
      // Check for any pending navigation notifications
      await _checkPendingNavigationNotifications();
      
      // Trigger rebuild of all future builders by updating the refresh key
      setState(() {
        _refreshKey++;
      });
      
      // Optional: Show a snackbar to confirm refresh
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Page refreshed'),
            duration: Duration(seconds: 1),
            backgroundColor: Color.fromARGB(255, 0, 25, 116),
          ),
        );
      }
    } catch (e) {
      // Handle any errors during refresh
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refresh failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _AutoSlidingImageSlider extends StatefulWidget {
  @override
  _AutoSlidingImageSliderState createState() => _AutoSlidingImageSliderState();
}

class _AutoSlidingImageSliderState extends State<_AutoSlidingImageSlider> {
  final List<String> imagePaths = [
    'lib/assets/images/dashboard1.png',
    'lib/assets/images/logo.png',
    'lib/assets/images/logo.png',
  ];
  final PageController _pageController = PageController();
  late int _currentPage;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _currentPage = 0;
    _timer = Timer.periodic(const Duration(seconds: 3), (Timer timer) {
      if (!mounted) return;
      setState(() {
        if (_currentPage < imagePaths.length - 1) {
          _currentPage++;
        } else {
          _currentPage = 0;
        }
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: PageView.builder(
        controller: _pageController,
        itemCount: imagePaths.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withAlpha((0.2 * 255).toInt()),
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(imagePaths[index], fit: BoxFit.contain),
              ),
            ),
          );
        },
      ),
    );
  }
}

Future<List<Map<String, dynamic>>> fetchUpcomingEvents() async {
  final snapshot = await FirebaseFirestore.instance.collection('events').get();
  final now = DateTime.now();

  return snapshot.docs
      .map((doc) {
        final data = doc.data();
        final dateStr = data['date'] ?? '';
        final startTimeStr = data['startTime'] ?? '';
        final endTimeStr = data['endTime'] ?? '';

        try {
          final date = DateFormat('dd-MM-yyyy').parse(dateStr).toLocal();
          final startTime = DateFormat('h:mm a').parse(startTimeStr).toLocal();
          final endTime = DateFormat('h:mm a').parse(endTimeStr).toLocal();

          final startDateTime = DateTime(
            date.year,
            date.month,
            date.day,
            startTime.hour,
            startTime.minute,
          );
          DateTime endDateTime = DateTime(
            date.year,
            date.month,
            date.day,
            endTime.hour,
            endTime.minute,
          );

          if (endTime.isBefore(startTime)) {
            endDateTime = endDateTime.add(Duration(days: 1));
          }

          final status =
              now.isBefore(startDateTime)
                  ? 'Upcoming'
                  : now.isAfter(endDateTime)
                  ? 'Finished'
                  : 'Ongoing';

          if (status == 'Upcoming') {
            return {...data, 'id': doc.id};
          }
        } catch (e) {
          return null;
        }
        return null;
      })
      .whereType<Map<String, dynamic>>()
      .toList();
}
