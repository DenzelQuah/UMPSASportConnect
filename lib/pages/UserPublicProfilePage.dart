import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'communication.dart';


class UserPublicProfilePage extends StatelessWidget {
  final Map<String, dynamic> user;

  const UserPublicProfilePage({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 0, 25, 116),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(user['username'] ?? 'User'),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Profile Avatar with border and shadow
              Center(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      ),
                    ],
                    border: Border.all(color: Colors.teal, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage:
                        user['profileImageUrl'] != null &&
                                user['profileImageUrl'].toString().isNotEmpty
                            ? NetworkImage(user['profileImageUrl'])
                            : null,
                    child:
                        (user['profileImageUrl'] == null ||
                                user['profileImageUrl'].toString().isEmpty)
                            ? Icon(
                              Icons.person,
                              size: 60,
                              color: Colors.grey.shade400,
                            )
                            : null,
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Info Card with section title
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Text(
                          user['username'] ?? '',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Center(
                        child: Text(
                          user['email'] ?? '',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Divider(),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          'About',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.teal,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      _publicProfileInfoRow(
                        Icons.info_outline,
                        user['bio']?.toString().isNotEmpty == true
                            ? user['bio']
                            : 'No bio added.',
                      ),
                      const SizedBox(height: 8),
                      _publicProfileInfoRow(
                        Icons.phone,
                        user['phone']?.toString().isNotEmpty == true
                            ? user['phone']
                            : 'No phone added.',
                      ),
                      const SizedBox(height: 8),
                      _publicProfileInfoRow(
                        Icons.school,
                        user['faculty']?.toString().isNotEmpty == true
                            ? user['faculty']
                            : 'No faculty added.',
                      ),
                      const SizedBox(height: 8),
                      _publicProfileInfoRow(
                        Icons.calendar_today,
                        user['semester']?.toString().isNotEmpty == true
                            ? user['semester']
                            : 'No semester added.',
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // Sports Chips with section title
              if (user['sports'] != null &&
                  user['sports'] is List &&
                  user['sports'].isNotEmpty)
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text(
                            'Sports',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.teal,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          children: [
                            for (final sport in user['sports'])
                              Chip(
                                avatar: Icon(
                                  _getSportIcon(sport),
                                  color: Colors.teal,
                                  size: 18,
                                ),
                                label: Text(
                                  sport,
                                  style: TextStyle(color: Colors.teal),
                                ),
                                backgroundColor: Colors.teal.withOpacity(0.08),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 18),

          // Skill Reviews Card with section title
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 2,
                child: ExpansionTile(
                  initiallyExpanded: true,
                  leading: Icon(Icons.military_tech, color: Colors.teal),
                  title: Text(
                    'Skill Reviews',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  children: [
                    FutureBuilder<QuerySnapshot>(
                      future:
                          FirebaseFirestore.instance
                              .collection('sportSkillReviews')
                              .where('uid', isEqualTo: user['id'])
                              .get(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text('No skill reviews submitted yet.'),
                          );
                        }
                        final reviews = snapshot.data!.docs;
                        return ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: reviews.length,
                          separatorBuilder: (context, index) => const Divider(),
                          itemBuilder: (context, index) {
                            final review =
                                reviews[index].data() as Map<String, dynamic>;
                            return ListTile(
                              leading: Icon(
                                _getSportIcon(review['sport']),
                                color: Colors.teal,
                              ),
                              title: Text(
                                review['sport'] ?? 'Unknown Sport',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Level: ${review['skillLevel'] ?? 'N/A'}',
                                  ),
                                  if (review['yearsOfPlaying'] != null)
                                    Text(
                                      'Years of Playing: ${review['yearsOfPlaying']}',
                                    ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Debug Info Card (Remove this in production)
              if (true) // Set to false in production
                Card(
                  color: Colors.grey.shade100,
                  child: ExpansionTile(
                    title: Text('Debug Info', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    children: [
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('User ID: ${_getUserId()}', style: TextStyle(fontSize: 12)),
                            Text('All user keys: ${user.keys.toList()}', style: TextStyle(fontSize: 12)),
                            Text('Has valid ID: ${_hasValidUserId()}', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 18),

              // Chat Button with improved error handling
              Center(
                child: ElevatedButton.icon(
                  onPressed: () => _startChat(context),
                  icon: const Icon(Icons.chat),
                  label: const Text('Chat Together'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.secondary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // IMPROVED: Better method to get user ID with multiple fallbacks
  String? _getUserId() {
    // Try different possible keys for user ID
    return user['id']?.toString() ?? 
            user['uid']?.toString() ?? 
            user['userId']?.toString() ??
            user['documentId']?.toString();
  }

  // IMPROVED: Check if we have a valid user ID
  bool _hasValidUserId() {
    final userId = _getUserId();
    return userId != null && userId.isNotEmpty;
  }

  // IMPROVED: Enhanced chat functionality with better error handling and user ID resolution
  Future<void> _startChat(BuildContext context) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Check if current user is authenticated
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        Navigator.of(context).pop(); // Close loading dialog
        _showErrorSnackBar(context, 'Please log in to start a chat');
        return;
      }

      // IMPROVED: Try to get user ID with multiple fallbacks
      String? targetUserId = _getUserId();

      // If still no ID, try to find user by email as last resort
      if (targetUserId == null || targetUserId.isEmpty) {
        targetUserId = await _findUserIdByEmail();
      }

      // Final check for valid user ID
      if (targetUserId == null || targetUserId.isEmpty) {
        Navigator.of(context).pop(); // Close loading dialog
        _showErrorSnackBar(context, 'Cannot find user ID. User data: ${user.keys.toList()}');
        return;
      }

      // Don't allow chatting with yourself
      if (currentUser.uid == targetUserId) {
        Navigator.of(context).pop(); // Close loading dialog
        _showWarningSnackBar(context, 'You cannot chat with yourself');
        return;
      }

      // Generate chat ID
      final chatId = _getChatId(currentUser.uid, targetUserId);
      
      // Defensive check for chatId
      if (chatId.isEmpty) {
        Navigator.of(context).pop(); // Close loading dialog if open
        _showErrorSnackBar(context, 'Invalid chat ID. Please try again.');
        return;
      }
      print('Navigating to CommunicationPage with chatId: ' + chatId);
      // Create or get existing chat document
      await _createOrGetChat(chatId, currentUser.uid, targetUserId);

      // Close loading dialog
      Navigator.of(context).pop();

      // Navigate to communication page
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CommunicationPage(chatId: chatId),
        ),
      );

    } catch (e) {
      // Close loading dialog if still open
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      
      print('Chat error: $e');
      _showErrorSnackBar(context, 'Error starting chat: ${e.toString()}');
    }
  }

  // IMPROVED: Try to find user ID by email as fallback
  Future<String?> _findUserIdByEmail() async {
    try {
      final email = user['email']?.toString();
      if (email == null || email.isEmpty) return null;

      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.first.id;
      }
    } catch (e) {
      print('Error finding user by email: $e');
    }
    return null;
  }

  // IMPROVED: Create or get existing chat document with better user data handling
  Future<void> _createOrGetChat(String chatId, String currentUserId, String targetUserId) async {
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);
    final chatDoc = await chatRef.get();

    if (!chatDoc.exists) {
      // Get current user data
      final currentUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .get();
      
      final currentUserData = currentUserDoc.data() ?? {};

      // Get target user data from Firestore to ensure we have complete data
      final targetUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(targetUserId)
          .get();
      
      final targetUserData = targetUserDoc.data() ?? user; // Fallback to passed user data

      final currentUsername = currentUserData['username'] ?? 'Unknown';
      final targetUsername = targetUserData['username'] ?? user['username'] ?? 'Unknown';

      // Create new chat document with all required fields
      Map<String, dynamic> participantDetailsMap = {};
      participantDetailsMap[currentUserId] = {
        'username': currentUsername,
        'profileImageUrl': currentUserData['profileImageUrl'] ?? '',
      };
      participantDetailsMap[targetUserId] = {
        'username': targetUsername,
        'profileImageUrl': targetUserData['profileImageUrl'] ?? user['profileImageUrl'] ?? '',
      };

      // Debug the participant details
      print('Current user ID: $currentUserId, Target user ID: $targetUserId');
      print('Participant details: $participantDetailsMap');

      // Create a string-keyed map for Firestore
      Map<String, dynamic> firestoreParticipantDetails = {};
      participantDetailsMap.forEach((key, value) {
        firestoreParticipantDetails[key.toString()] = value;
      });

      await chatRef.set({
        'chatId': chatId,
        'participants': [currentUserId, targetUserId],
        'participantDetails': firestoreParticipantDetails,
        'lastMessage': 'Chat started',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'lastSenderName': currentUsername,
        'lastSenderId': currentUserId,
        'unreadCount_$currentUserId': 0,
        'unreadCount_$targetUserId': 1,
        'profileImageUrl': targetUserData['profileImageUrl'] ?? user['profileImageUrl'] ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'eventId': null, // null for direct user chat
        'eventName': '$currentUsername & $targetUsername', // Show both usernames for direct chat
        'createdBy': currentUserId,
        'type': 'direct', // Indicate this is a direct chat
      });
      
      // Debug print to verify the chat was created correctly
      print('Created chat $chatId between $currentUsername and $targetUsername');
    }
  }

  // Helper methods for showing different types of messages
  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showWarningSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Helper for info rows
  Widget _publicProfileInfoRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.teal),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: TextStyle(fontSize: 15))),
      ],
    );
  }
}

// Helper to generate a unique chatId for two users
String _getChatId(String uid1, String uid2) {
  final ids = [uid1, uid2]..sort();
  return ids.join('_');
}

// Helper to get sport icon based on sport name
IconData _getSportIcon(String? sport) {
  switch (sport) {
    case 'Badminton':
      return Icons.sports_tennis;
    case 'Basketball':
      return Icons.sports_basketball;
    case 'Football':
      return Icons.sports_soccer;
    case 'Tennis':
      return Icons.sports_tennis;
    case 'Pétanque':
      return Icons.sports_golf;
    case 'Lawn Bowls':
      return Icons.sports_golf;
    case 'Sepak Takraw':
      return Icons.sports_volleyball;
    case 'Volleyball':
      return Icons.sports_volleyball;
    case 'Chess':
      return Icons.extension;
    case 'Ten-pin Bowling':
      return Icons.sports;
    case 'Netball':
      return Icons.sports_handball;
    case 'Table Tennis':
      return Icons.sports_tennis;
    case 'Handball':
      return Icons.sports_handball;
    case 'E-sport':
      return Icons.sports_esports;
    default:
      return Icons.sports;
  }
}