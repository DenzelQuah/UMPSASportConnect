import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'communication.dart';

// Notification logic should be handled globally, not just in ChatPage.
// Use a background message handler or a global listener for Firestore updates.
// Here's a simple example using a global Firestore listener in a singleton service:

class ChatNotificationService {
  static final ChatNotificationService _instance =
      ChatNotificationService._internal();
  factory ChatNotificationService() => _instance;
  ChatNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  StreamSubscription<QuerySnapshot>? _chatSubscription;

  void initialize(String currentUserId) {
    // Initialize notifications
    const initializationSettingsAndroid = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    _notificationsPlugin.initialize(initializationSettings);

    // Listen for new messages in all chats where the user is a participant
    _chatSubscription?.cancel();
    _chatSubscription = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: currentUserId)
        .snapshots()
        .listen((snapshot) {
          for (var doc in snapshot.docs) {
            final data = doc.data();
            // Only notify if the last message is not from the current user and is unseen
            if (data['lastSenderId'] != currentUserId &&
                data['lastMessage'] != null) {
              // You can add more logic to avoid duplicate notifications
              _showNotification(
                data['eventName'] ?? 'New Message',
                data['lastMessage'] ?? 'You have a new message.',
              );
            }
          }
        });
  }

  void dispose() {
    _chatSubscription?.cancel();
  }

  void _showNotification(String title, String body) async {
    const androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'new_message_channel',
      'New Messages',
      channelDescription: 'Notification channel for new messages',
      importance: Importance.max,
      priority: Priority.high,
    );
    const platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );
    await _notificationsPlugin.show(0, title, body, platformChannelSpecifics);
  }
}

// In your main.dart or app entry point, after user login:
void setupChatNotifications() {
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    ChatNotificationService().initialize(user.uid);
  }
}

class ChatPage extends StatelessWidget {
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  ChatPage({super.key}) {
    // Initialize local notifications
    const initializationSettingsAndroid = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    flutterLocalNotificationsPlugin.initialize(initializationSettings);

    // Request notification permissions
    _requestNotificationPermissions();
  }

  Future<void> _requestNotificationPermissions() async {
    final status = await Permission.notification.request();
    if (status.isGranted) {
      debugPrint('Notification permission granted.');
    } else {
      debugPrint('Notification permission denied.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatsStream =
        FirebaseFirestore.instance
            .collection('chats')
            .where('participants', arrayContains: currentUserId)
            .orderBy('lastMessageTime', descending: true)
            .snapshots();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 0, 25, 116),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("Chats"),
        centerTitle: true,
        elevation: 0,
      ),
      body: Container(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: StreamBuilder<QuerySnapshot>(
          stream: chatsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: \\${snapshot.error}'));
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(child: Text("No chat groups available."));
            }
            final chatDocs = snapshot.data!.docs;
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              separatorBuilder: (context, i) => const SizedBox(height: 4),
              itemCount: chatDocs.length,
              itemBuilder: (context, idx) {
                final doc = chatDocs[idx];
                final chatData = doc.data() as Map<String, dynamic>?;
                if (chatData == null) return const SizedBox();
                
                // Debug print to see what data is available
                print('Chat data for ${doc.id}: ${chatData.keys.toList()}');
                
                final chatId = doc.id;
                if (chatId.isEmpty) {
                  return const SizedBox(); // Skip rendering this chat
                }
                
                // Get chat name with better fallbacks
                String chatName;
                final rawEventName = chatData['eventName'];
                
                if (rawEventName != null && rawEventName.toString().isNotEmpty) {
                  chatName = rawEventName.toString();
                } else {
                  chatName = 'Unnamed Chat';
                }
                
                final lastMessage = chatData['lastMessage'] ?? '';
                final lastMessageTime =
                    (chatData['lastMessageTime'] as Timestamp?)?.toDate();
                final unreadCount =
                    chatData['unreadCount_$currentUserId'] ?? 0;
                final eventId = chatData['eventId'];
                final participants = chatData['participants'] as List<dynamic>? ?? [];
                final isEventChat = eventId != null && (eventId is String ? eventId.isNotEmpty : true);
                
                // Debug print for chat type
                print('Chat $chatId - isEventChat: $isEventChat, eventId: $eventId, name: $chatName');
                
                if (isEventChat) {
                  // Defensive check for eventId
                  if (eventId == null || (eventId is String && eventId.isEmpty)) {
                    return const SizedBox(); // Skip rendering if eventId is invalid
                  }
                  // Event group chat: show event image
                  return StreamBuilder<DocumentSnapshot>(
                    stream:
                        FirebaseFirestore.instance
                            .collection('events')
                            .doc(eventId)
                            .snapshots(),
                    builder: (context, eventSnapshot) {
                      final eventData =
                          eventSnapshot.data?.data() as Map<String, dynamic>?;
                      final eventImage = eventData?['imageUrl'];
                      final avatar =
                          eventImage != null && eventImage.isNotEmpty
                              ? NetworkImage(eventImage)
                              : null;
                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 2,
                        color: Colors.white.withOpacity(0.95),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          leading: CircleAvatar(
                            radius: 26,
                            backgroundColor: Colors.teal.withOpacity(0.12),
                            backgroundImage: avatar,
                            child:
                                avatar == null
                                    ? const Icon(
                                      Icons.group,
                                      color: Colors.teal,
                                      size: 28,
                                    )
                                    : null,
                          ),
                          title: Text(
                            chatName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                          subtitle: Text(
                            lastMessage.isNotEmpty
                                ? lastMessage
                                : "No messages yet.",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (lastMessageTime != null)
                                Text(
                                  timeago.format(lastMessageTime),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              if (unreadCount > 0)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    unreadCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          onTap: () async {
                            if (chatId.isNotEmpty) {
                              final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);
                              final chatDoc = await chatRef.get();
                              if (!chatDoc.exists) {
                                // Create the chat document for the event group chat
                                await chatRef.set({
                                  'eventId': chatId,
                                  'eventName': chatName,
                                  'participants': participants,
                                  'createdAt': FieldValue.serverTimestamp(),
                                  'lastMessage': '',
                                  'lastMessageTime': null,
                                  'lastSenderName': '',
                                  'profileImageUrl': null,
                                });
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CommunicationPage(chatId: chatId),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Invalid chat ID. Please try again.')),
                              );
                            }
                          },
                        ),
                      );
                    },
                  );
                } else {
                  // Direct user-to-user chat
                  // Find the other user's ID
                  final otherUserId = participants.firstWhere(
                    (id) => id.toString() != currentUserId,
                    orElse: () => '',
                  );
                  
                  if (otherUserId.isEmpty) {
                    return const SizedBox(); // Skip if no other user found
                  }
                  
                  print('Direct chat $chatId - otherUserId: $otherUserId, currentUserId: $currentUserId');
                  
                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(otherUserId.toString())
                        .get(),
                    builder: (context, userSnapshot) {
                      // Get participant details from the chat document
                      final participantDetails = chatData['participantDetails'] as Map<String, dynamic>?;
                      
                      if (participantDetails != null) {
                        print('ParticipantDetails keys: ${participantDetails.keys.toList()}');
                      }
                      
                      // Try to get username from different sources
                      String otherUsername = 'User';  // Initialize with a default value
                      String? profileImageUrl;
                      
                      // 1. Try to get from participantDetails
                      if (participantDetails != null) {
                        // Try both with and without toString() since we're not sure how the keys are stored
                        final details = participantDetails[otherUserId.toString()] ?? 
                                       participantDetails[otherUserId];
                        
                        if (details is Map) {
                          otherUsername = details['username'] ?? 'User';
                          profileImageUrl = details['profileImageUrl'];
                          print('Found username in participantDetails: $otherUsername');
                        } else {
                          print('No valid details found in participantDetails for $otherUserId');
                        }
                      } 
                      
                      // 2. Try to get from Firestore user document if not found in participantDetails
                      if (participantDetails == null && userSnapshot.hasData && userSnapshot.data != null) {
                        final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                        if (userData != null && userData['username'] != null) {
                          otherUsername = userData['username'];
                          profileImageUrl = userData['profileImageUrl'];
                          print('Found username in Firestore: $otherUsername');
                        }
                      }
                      
                      // 3. Try to extract name from chat name format if still using default
                      if (otherUsername == 'User' && chatName.contains('&')) {
                        final names = chatName.split('&');
                        // Find the name that's not the current user's name
                        for (final name in names) {
                          final trimmedName = name.trim();
                          // This is a simple check - in a real app you'd compare with the current user's name
                          if (!trimmedName.toLowerCase().contains('you')) {
                            otherUsername = trimmedName;
                            break;
                          }
                        }
                        
                        // If still not found, use the full chat name
                        if (otherUsername == 'User' && chatName != 'Unnamed Chat') {
                          otherUsername = chatName;
                        }
                        print('Using extracted username: $otherUsername');
                      }
                      
                      // Log what we found
                      print('Chat $chatId - Final username: $otherUsername for user $otherUserId');
                      
                      final avatar = profileImageUrl != null && profileImageUrl.toString().isNotEmpty
                          ? NetworkImage(profileImageUrl.toString())
                          : null;
                      
                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 2,
                        color: Colors.white.withOpacity(0.95),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          leading: CircleAvatar(
                            radius: 26,
                            backgroundColor: Colors.blue.withOpacity(0.12),
                            backgroundImage: avatar,
                            child: avatar == null
                                ? const Icon(
                                    Icons.person,
                                    color: Colors.blue,
                                    size: 28,
                                  )
                                : null,
                          ),
                          title: Text(
                            otherUsername,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                          subtitle: Text(
                            lastMessage.isNotEmpty
                                ? lastMessage
                                : "No messages yet.",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (lastMessageTime != null)
                                Text(
                                  timeago.format(lastMessageTime),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              if (unreadCount > 0)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    unreadCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          onTap: () {
                            if (chatId.isNotEmpty) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CommunicationPage(chatId: chatId),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Invalid chat ID. Please try again.')),
                              );
                            }
                          },
                        ),
                      );
                    },
                  );
                }
              },
            );
          },
        ),
      ),
    );
  }
}
