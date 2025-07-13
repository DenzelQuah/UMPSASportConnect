import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HostRequestsPage extends StatefulWidget {
  const HostRequestsPage({super.key});

  @override
  State<HostRequestsPage> createState() => _HostRequestsPageState();
}

class _HostRequestsPageState extends State<HostRequestsPage> {
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;

  // Method to handle join request (accept/reject)
  Future<void> _handleJoinRequest(String eventId, String requestUserId, bool accept, String eventName) async {
    try {
      final docRef = FirebaseFirestore.instance.collection('events').doc(eventId);
      final snapshot = await docRef.get();

      if (snapshot.exists) {
        final data = snapshot.data()!;
        List joinRequests = data['joinRequests'] ?? [];
        
        // Find and remove the request
        joinRequests.removeWhere((request) => request['userId'] == requestUserId);
        
        if (accept) {
          // Add user to joined users
          await docRef.update({
            'joinedUsers': FieldValue.arrayUnion([requestUserId]),
            'joinRequests': joinRequests,
            'lastUpdated': FieldValue.serverTimestamp(), // Add timestamp for notification tracking
          });

          // Add user to chat participants
          final chatDoc = await FirebaseFirestore.instance
              .collection('chats')
              .doc(eventId)
              .get();

          if (chatDoc.exists) {
            await chatDoc.reference.update({
              'participants': FieldValue.arrayUnion([requestUserId]),
            });
            
            // Add a system message to the chat
            await FirebaseFirestore.instance
                .collection('chats')
                .doc(eventId)
                .collection('messages')
                .add({
                  'text': 'A new participant has joined the event!',
                  'senderId': 'system',
                  'senderName': 'System',
                  'timestamp': FieldValue.serverTimestamp(),
                  'isSystemMessage': true,
                });
                
            // Create a notification document for the user to navigate them to the chat
            await FirebaseFirestore.instance
                .collection('users')
                .doc(requestUserId)
                .collection('notifications')
                .add({
                  'type': 'event_join',
                  'eventId': eventId,
                  'eventName': eventName,
                  'timestamp': FieldValue.serverTimestamp(),
                  'read': false,
                  'message': 'Your request to join "$eventName" has been accepted!',
                  'actionType': 'navigate_to_chat',
                  'actionData': eventId,
                });
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Join request accepted for $eventName')),
          );
        } else {
          // Just remove the request for rejection
          await docRef.update({
            'joinRequests': joinRequests,
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Join request rejected for $eventName')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error handling request: $e')),
      );
    }
  }

  // Add this to your event creation method
Future<void> createEventWithChat(Map<String, dynamic> eventData, String eventId) async {
  try {
    // Create the event document
    await FirebaseFirestore.instance.collection('events').doc(eventId).set(eventData);
    
    // Create the corresponding chat document
    await FirebaseFirestore.instance.collection('chats').doc(eventId).set({
      'eventId': eventId,
      'eventName': eventData['eventName'],
      'participants': [eventData['hostId']], // Initially just the host
      'lastMessage': '',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': '',
      'createdAt': FieldValue.serverTimestamp(),
      // Initialize unread count for host
      'unreadCount_${eventData['hostId']}': 0,
    });
    
  } catch (e) {
    print('Error creating event with chat: $e');
    rethrow;
  }
}

  // Get username from user ID
  Future<String> _getUsername(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      return doc.exists ? (doc.data()?['username'] ?? 'Unknown User') : 'Unknown User';
    } catch (e) {
      return 'Unknown User';
    }
  }

  // Format timestamp
  String _formatTimestamp(String timestampStr) {
    try {
      final dateTime = DateTime.parse(timestampStr);
      return DateFormat('MMM dd, yyyy - hh:mm a').format(dateTime);
    } catch (e) {
      return 'Unknown time';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 0, 25, 116),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("Manage Join Requests"),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('events')
            .where('hostId', isEqualTo: currentUserId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text('Error loading events'),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.event_busy,
                    size: 80,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'You have no hosted events',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }

          // Filter events that have join requests
          final eventsWithRequests = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final joinRequests = data['joinRequests'] ?? [];
            return joinRequests.isNotEmpty;
          }).toList();

          if (eventsWithRequests.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 80,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No pending join requests',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Join requests will appear here when users want to join your events',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: eventsWithRequests.length,
            itemBuilder: (context, eventIndex) {
              final eventDoc = eventsWithRequests[eventIndex];
              final eventData = eventDoc.data() as Map<String, dynamic>;
              final eventName = eventData['eventName'] ?? 'Unknown Event';
              final eventSport = eventData['sport'] ?? 'Unknown Sport';
              final eventDate = eventData['date'] ?? 'Unknown Date';
              final joinRequests = eventData['joinRequests'] ?? [];

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Event header
                      Row(
                        children: [
                          Icon(
                            Icons.event,
                            color: const Color.fromARGB(255, 0, 25, 116),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  eventName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color.fromARGB(255, 0, 25, 116),
                                  ),
                                ),
                                Text(
                                  '$eventSport • $eventDate',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Chip(
                            label: Text('${joinRequests.length} requests'),
                            backgroundColor: Colors.orange.withOpacity(0.2),
                            labelStyle: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      
                      // Join requests list
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: joinRequests.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, requestIndex) {
                          final request = joinRequests[requestIndex];
                          final userId = request['userId'];
                          final timestamp = request['timestamp'] ?? '';
                          
                          return FutureBuilder<String>(
                            future: _getUsername(userId),
                            builder: (context, userSnapshot) {
                              final username = userSnapshot.data ?? 'Loading...';
                              
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Row(
                                  children: [
                                    // User avatar
                                    CircleAvatar(
                                      backgroundColor: const Color.fromARGB(255, 0, 25, 116),
                                      child: Text(
                                        username.isNotEmpty ? username[0].toUpperCase() : 'U',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    
                                    // User info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            username,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Requested to join',
                                            style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 14,
                                            ),
                                          ),
                                          if (timestamp.isNotEmpty)
                                            Text(
                                              _formatTimestamp(timestamp),
                                              style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 12,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    
                                    // Action buttons
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Accept button
                                        ElevatedButton.icon(
                                          onPressed: () {
                                            _handleJoinRequest(eventDoc.id, userId, true, eventName);
                                          },
                                          icon: const Icon(Icons.check, size: 18),
                                          label: const Text('Accept'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            minimumSize: const Size(0, 36),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        
                                        // Reject button
                                        ElevatedButton.icon(
                                          onPressed: () {
                                            _handleJoinRequest(eventDoc.id, userId, false, eventName);
                                          },
                                          icon: const Icon(Icons.close, size: 18),
                                          label: const Text('Reject'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            minimumSize: const Size(0, 36),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                      ],
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
              );
            },
          );
        },
      ),
    );
  }
}