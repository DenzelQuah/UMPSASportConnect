import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'UserPublicProfilePage.dart';

class CommunicationPage extends StatefulWidget {
  final String chatId;
  const CommunicationPage({super.key, required this.chatId});

  @override
  _CommunicationPageState createState() => _CommunicationPageState();
}

class _CommunicationPageState extends State<CommunicationPage>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
  late final AudioPlayer _audioPlayer;
  bool _isVoicePlaying = false;
  String? _playingVoicePath;
  
  // Add new variables to track chat type and related data
  bool _isEventChat = false;
  Map<String, dynamic>? _eventData;
  Map<String, dynamic>? _otherUserData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    
    // Initialize audio player
    _audioPlayer = AudioPlayer();
    _audioPlayer.onPlayerComplete.listen((event) {
      setState(() {
        _isVoicePlaying = false;
        _playingVoicePath = null;
      });
    });
    
    // Add validation for chatId
    if (widget.chatId.isEmpty) {
      // Handle empty chatId - either navigate back or show error
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid chat ID. Please try again.')),
        );
        Navigator.of(context).pop();
      });
      return;
    }
    
    // Load everything in initState
    _loadInitialData();
  }
  
  // Combined method to load all initial data at once
  Future<void> _loadInitialData() async {
    await _ensureParticipantInChat();
    await _identifyChatTypeAndLoadData();
    
    // Only set loading to false when everything is done
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // Ensure that the current user is a participant in the chat.
  Future<void> _ensureParticipantInChat() async {
    try {
      final chatRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId);
      final chatSnapshot = await chatRef.get();
  
      if (chatSnapshot.exists) {
        final chatData = chatSnapshot.data();
        final participants = List<String>.from(chatData?['participants'] ?? []);
        if (!participants.contains(currentUserId)) {
          await chatRef.update({
            'participants': FieldValue.arrayUnion([currentUserId]),
          });
        }
      } else {
        // Optionally create the chat if it doesn't exist.
        await chatRef.set({
          'createdBy': currentUserId,
          'eventId': widget.chatId,
          'eventName': 'Unnamed Event',
          'participants': [currentUserId],
          'createdAt': FieldValue.serverTimestamp(),
          'lastMessage': '',
          'lastMessageTime': null,
          'lastSenderName': '',
          'profileImageUrl': null,
        });
      }
    } catch (e) {
      print('Error ensuring participant in chat: $e');
    }
  }

  // Identify chat type and load related data
  Future<void> _identifyChatTypeAndLoadData() async {
    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .get();
      
      if (!chatDoc.exists) {
        print('Chat document does not exist');
        return;
      }
      
      final chatData = chatDoc.data() as Map<String, dynamic>;
      final eventId = chatData['eventId'];
      
      bool isEventChat = eventId != null && eventId.toString().isNotEmpty;
      
      // Check if this is an event chat or direct chat
      if (isEventChat) {
        // This is an event chat
        Map<String, dynamic>? eventData;
        
        // Load event data without causing a rebuild yet
        try {
          final eventDoc = await FirebaseFirestore.instance
              .collection('events')
              .doc(eventId.toString())
              .get();
          
          if (eventDoc.exists) {
            eventData = eventDoc.data();
          }
        } catch (e) {
          print('Error loading event data: $e');
        }
        
        // Update state once with all collected data
        if (mounted) {
          setState(() {
            _isEventChat = isEventChat;
            _eventData = eventData;
          });
        }
      } else {
        // This is a direct user-to-user chat
        Map<String, dynamic>? otherUserData;
        
        // Find the other user in the participants
        final participants = List<String>.from(chatData['participants'] ?? []);
        final otherUserId = participants.firstWhere(
          (id) => id != currentUserId,
          orElse: () => '',
        );
        
        if (otherUserId.isNotEmpty) {
          // Load other user data without causing a rebuild yet
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(otherUserId)
                .get();
            
            if (userDoc.exists) {
              otherUserData = userDoc.data();
            }
          } catch (e) {
            print('Error loading user data: $e');
          }
        }
        
        // Update state once with all collected data
        if (mounted) {
          setState(() {
            _isEventChat = isEventChat;
            _otherUserData = otherUserData;
          });
        }
      }
    } catch (e) {
      print('Error identifying chat type: $e');
    }
  }
  
  // Play a voice message
  Future<void> _playVoiceMessage(String voiceData) async {
    try {
      if (_isVoicePlaying && _playingVoicePath == voiceData) {
        // If the same voice message is playing, pause it
        await _audioPlayer.pause();
        setState(() {
          _isVoicePlaying = false;
          _playingVoicePath = null;
        });
      } else {
        // If a different voice message is playing, stop it first
        if (_isVoicePlaying) {
          await _audioPlayer.stop();
        }
        
        // Check if this is a base64 encoded audio
        if (voiceData.startsWith('http')) {
          // It's a URL, play directly
          await _audioPlayer.play(UrlSource(voiceData));
        } else {
          // It's likely base64 encoded, decode and play from memory
          try {
            // Decode base64 to bytes
            final bytes = base64Decode(voiceData);
            
            // Create a temporary file to play
            final tempDir = await getTemporaryDirectory();
            final tempFile = File('${tempDir.path}/temp_voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
            await tempFile.writeAsBytes(bytes);
            
            // Play from the temporary file
            await _audioPlayer.play(DeviceFileSource(tempFile.path));
            
            // Schedule deletion of temp file after playback
            _audioPlayer.onPlayerComplete.listen((_) {
              // ignore: invalid_return_type_for_catch_error
              tempFile.delete().catchError((e) => print('Error deleting temp file: $e'));
            });
          } catch (e) {
            print('Error decoding base64 audio: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error playing voice message: Invalid format')),
            );
            return;
          }
        }
        
        setState(() {
          _isVoicePlaying = true;
          _playingVoicePath = voiceData;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error playing voice message: $e')),
      );
    }
  }

  // Show event details when info button is clicked
  void _showEventDetails(dynamic eventId) {
    if (eventId == null || (eventId is String && eventId.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No event information available')),
      );
      return;
    }

    // Use cached event data if available
    if (_isEventChat && _eventData != null) {
      _displayEventDetailsDialog(_eventData!);
      return;
    }

    FirebaseFirestore.instance
        .collection('events')
        .doc(eventId.toString())
        .get()
        .then((eventDoc) {
      if (!eventDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event not found')),
        );
        return;
      }

      final eventData = eventDoc.data()!;
      _displayEventDetailsDialog(eventData);
    }).catchError((error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading event details: $error')),
      );
    });
  }

  // Show full-screen image when tapped
  void _showImageZoom(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: InteractiveViewer(
            child: Image.network(
              imageUrl,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: Colors.black54,
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                print('Error loading zoomed image: $error');
                return Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Icon(Icons.error, color: Colors.white, size: 50),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // Helper method to display event details dialog
  void _displayEventDetailsDialog(Map<String, dynamic> eventData) {
    final hostId = eventData['hostId'];
    final sport = eventData['sport'] ?? 'Unknown sport';
    final maxParticipants = eventData['maxParticipants'] ?? 0;
    final joinedUsers = eventData['joinedUsers'] != null ? List.from(eventData['joinedUsers']) : [];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(eventData['eventName'] ?? 'Event Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (eventData['imageUrl'] != null && eventData['imageUrl'].toString().isNotEmpty)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      eventData['imageUrl'],
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => 
                        Container(
                          height: 150,
                          color: Colors.grey.shade200,
                          child: const Center(child: Icon(Icons.error)),
                        ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              _eventDetailRow(Icons.description, 'Description', eventData['description'] ?? 'No description'),
              _eventDetailRow(Icons.location_on, 'Location', eventData['location'] ?? 'No location'),
              _eventDetailRow(Icons.calendar_today, 'Date', eventData['date'] ?? 'No date'),
              _eventDetailRow(Icons.access_time, 'Time', '${eventData['startTime'] ?? 'N/A'} - ${eventData['endTime'] ?? 'N/A'}'),
              _eventDetailRow(Icons.sports, 'Sport', sport),
              _eventDetailRow(Icons.people, 'Participants', '${joinedUsers.length} / $maxParticipants'),
              
              // Show host information
              if (hostId != null)
                FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection('users').doc(hostId.toString()).get(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                    }
                    
                    final hostData = snapshot.data?.data() as Map<String, dynamic>?;
                    final hostName = hostData?['username'] ?? eventData['hostName'] ?? 'Unknown Host';
                    
                    return _eventDetailRow(Icons.person, 'Host', hostName);
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Helper method for event details dialog
  Widget _eventDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.teal),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Show event participants
  void _showEventParticipants(List<dynamic>? participants) {
    if (participants == null || participants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No participants found')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => ParticipantsList(participants: participants),
    );
  }

  Widget _buildMessageBubble(String messageId, Map<String, dynamic> messageData, bool isCurrentUser, DateTime? messageTime, String? currentUserProfileImage) {
    final text = messageData['text'] as String? ?? '';
    final senderName = messageData['senderName'] as String?;
    final profileImageUrl = isCurrentUser ? currentUserProfileImage : messageData['profileImageUrl'] as String?;
    
    // Check for file URL which is used for both images and voice messages
    final fileUrl = messageData['fileUrl'] as String?;
    final fileType = messageData['fileType'] as String?;
    
    // Determine if this is an image or voice message
    final hasImage = fileUrl != null && (fileType == 'jpg' || fileType == 'png' || fileType == 'gif');
    final hasVoice = fileUrl != null && fileType == 'm4a' && messageData['isVoice'] == true;
    
    // Check if this is a system message
    final isSystemMessage = messageData['isSystemMessage'] == true || messageData['senderId'] == 'system';
    
    // Check if message is within 10-minute edit window
    bool canModify = false;
    if (isCurrentUser && messageTime != null && !isSystemMessage) {
      final now = DateTime.now();
      final difference = now.difference(messageTime);
      canModify = difference.inMinutes < 10;
    }
    
    // For system messages, display centered with different styling
    if (isSystemMessage) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              text,
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }
    
    // Use GestureDetector to handle long press only on the user's own messages
    return Align(
      alignment: isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isCurrentUser)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: profileImageUrl != null && profileImageUrl.isNotEmpty
                    ? NetworkImage(profileImageUrl)
                    : null,
                  child: profileImageUrl == null || profileImageUrl.isEmpty
                    ? const Icon(Icons.person, size: 16, color: Colors.grey)
                    : null,
                ),
              ),
              
            GestureDetector(
              // Only show options if it's the current user's message and can be modified
              onLongPress: isCurrentUser ? () => _showMessageOptions(
                context, 
                messageId, 
                messageData, 
                canModify, 
                text,
                hasImage || hasVoice,
              ) : null,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.7,
                ),
                decoration: BoxDecoration(
                  color: isCurrentUser ? Colors.blue.shade200 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sender name for non-current user
                    if (!isCurrentUser && senderName != null && senderName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          senderName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      
                    // Regular text message
                    if (text.isNotEmpty)
                      Text(
                        text,
                        style: const TextStyle(fontSize: 16),
                      ),
                      
                    // Image message
                    if (hasImage)
                      GestureDetector(
                        onTap: () => _showImageZoom(fileUrl),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            fileUrl,
                            fit: BoxFit.cover,
                            width: 200,
                            height: 150,
                            errorBuilder: (context, error, stackTrace) {
                              print('Error loading image: $error');
                              return Container(
                                width: 200,
                                height: 150,
                                color: Colors.grey.shade300,
                                child: const Center(child: Icon(Icons.error)),
                              );
                            },
                          ),
                        ),
                      ),
                      
                    // Voice message
                    if (hasVoice)
                      GestureDetector(
                        onTap: () => _playVoiceMessage(fileUrl),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.teal.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isVoicePlaying && _playingVoicePath == fileUrl
                                  ? Icons.pause
                                  : Icons.play_arrow,
                                color: Colors.teal,
                              ),
                              const SizedBox(width: 8),
                              const Text('Voice message'),
                            ],
                          ),
                        ),
                      ),
                    
                    // Message timestamp
                    if (messageTime != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DateFormat('hh:mm a').format(messageTime),
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                            ),
                            // Show edit indicator if message was modified
                            if (messageData['edited'] == true)
                              Text(
                                ' · edited',
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            
            // Current user's profile picture on the right
            if (isCurrentUser)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.blue.shade100,
                  backgroundImage: profileImageUrl != null && profileImageUrl.isNotEmpty
                    ? NetworkImage(profileImageUrl)
                    : null,
                  child: profileImageUrl == null || profileImageUrl.isEmpty
                    ? const Icon(Icons.person, size: 16, color: Colors.blue)
                    : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Show options menu for editing or deleting a message
  void _showMessageOptions(
    BuildContext context, 
    String messageId, 
    Map<String, dynamic> messageData, 
    bool canModify,
    String text,
    bool isMediaMessage,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canModify && !isMediaMessage)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Edit Message'),
                  onTap: () {
                    Navigator.pop(context);
                    _editMessage(messageId, text);
                  },
                ),
              if (canModify)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Delete Message', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteMessage(messageId);
                  },
                ),
              if (!canModify)
                const ListTile(
                  leading: Icon(Icons.timer_off),
                  title: Text('Cannot modify messages older than 10 minutes'),
                  enabled: false,
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }

  // Edit a message
  void _editMessage(String messageId, String originalText) {
    final TextEditingController editController = TextEditingController(text: originalText);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Message'),
        content: TextField(
          controller: editController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Edit your message',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final newText = editController.text.trim();
              if (newText.isEmpty || newText == originalText) return;
              
              try {
                await FirebaseFirestore.instance
                    .collection('chats')
                    .doc(widget.chatId)
                    .collection('messages')
                    .doc(messageId)
                    .update({
                      'text': newText,
                      'edited': true,
                    });
                    
                // Check if this was the last message and update chat document if needed
                final chatDoc = await FirebaseFirestore.instance
                    .collection('chats')
                    .doc(widget.chatId)
                    .get();
                    
                if (chatDoc.exists) {
                  final chatData = chatDoc.data();
                  final lastSenderId = chatData?['lastSenderId'];
                  if (lastSenderId == currentUserId) {
                    await FirebaseFirestore.instance
                        .collection('chats')
                        .doc(widget.chatId)
                        .update({
                          'lastMessage': '${newText.length > 30 ? '${newText.substring(0, 30)}...' : newText} (edited)',
                        });
                  }
                }
              } catch (e) {
                print('Error updating message: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error updating message: $e')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Delete a message
  void _deleteMessage(String messageId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              
              try {
                // Get message data before deleting to check if it's the last message
                final messageDoc = await FirebaseFirestore.instance
                    .collection('chats')
                    .doc(widget.chatId)
                    .collection('messages')
                    .doc(messageId)
                    .get();
                
                if (!messageDoc.exists) return;
                
                // Delete the message
                await FirebaseFirestore.instance
                    .collection('chats')
                    .doc(widget.chatId)
                    .collection('messages')
                    .doc(messageId)
                    .delete();
                    
                // Check if this was the last message and update chat document if needed
                final chatDoc = await FirebaseFirestore.instance
                    .collection('chats')
                    .doc(widget.chatId)
                    .get();
                    
                if (chatDoc.exists) {
                  final chatData = chatDoc.data();
                  final lastSenderId = chatData?['lastSenderId'];
                  
                  if (lastSenderId == currentUserId) {
                    // Get the new last message
                    final messagesSnapshot = await FirebaseFirestore.instance
                        .collection('chats')
                        .doc(widget.chatId)
                        .collection('messages')
                        .orderBy('timestamp', descending: true)
                        .limit(1)
                        .get();
                        
                    if (messagesSnapshot.docs.isNotEmpty) {
                      // There's a previous message, update to that
                      final lastMessage = messagesSnapshot.docs.first;
                      final lastMessageData = lastMessage.data();
                      final text = lastMessageData['text'] as String? ?? '';
                      final senderName = lastMessageData['senderName'] as String? ?? '';
                      
                      await FirebaseFirestore.instance
                          .collection('chats')
                          .doc(widget.chatId)
                          .update({
                            'lastMessage': text.isNotEmpty ? text : 'Media message',
                            'lastSenderName': senderName,
                            'lastSenderId': lastMessageData['senderId'],
                            'lastMessageTime': lastMessageData['timestamp'],
                          });
                    } else {
                      // No messages left, update to empty state
                      await FirebaseFirestore.instance
                          .collection('chats')
                          .doc(widget.chatId)
                          .update({
                            'lastMessage': 'No messages',
                            'lastSenderName': '',
                            'lastMessageTime': FieldValue.serverTimestamp(),
                          });
                    }
                  }
                }
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Message deleted')),
                  );
                }
              } catch (e) {
                print('Error deleting message: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error deleting message: $e')),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildScaffold(Widget titleWidget, bool isDirectChat, Map<String, dynamic> chatData, String? currentUserProfileImage, String currentUsername) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 0, 25, 116),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        title: titleWidget,
        actions: [
          if (!isDirectChat && _eventData != null)
            IconButton(
              icon: const Icon(Icons.people),
              onPressed: () => _showEventParticipants(chatData['participants']),
            ),
          if (!isDirectChat && _eventData != null)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () => _showEventDetails(chatData['eventId']),
            ),
        ],
      ),
      // This is critical for proper keyboard handling
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          // Messages area
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('timestamp')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No messages yet'));
                }
                
                final messages = snapshot.data!.docs;
                
                // Auto-scroll to bottom on new messages
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                  }
                });
                
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final messageDoc = messages[index];
                    final messageData = messageDoc.data() as Map<String, dynamic>;
                    final senderId = messageData['senderId'] as String?;
                    final isCurrentUser = senderId == currentUserId;
                    final timestamp = messageData['timestamp'] as Timestamp?;
                    final messageTime = timestamp?.toDate();
                    
                    return _buildMessageBubble(
                      messageDoc.id, 
                      messageData, 
                      isCurrentUser, 
                      messageTime, 
                      currentUserProfileImage
                    );
                  },
                );
              },
            ),
          ),
          
          // Message input - no wrappers
          MessageInput(chatId: widget.chatId, currentUserId: currentUserId),
        ],
      ),
    );
  }

  // Main build method that's more stable
  @override
  Widget build(BuildContext context) {
    if (widget.chatId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: const Center(child: Text('Invalid chat ID.')),
      );
    }
    
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    // Stream only the chat document for minimal UI updates
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Chat')),
            body: const Center(child: Text('Chat not found')),
          );
        }

        final chatData = snapshot.data!.data() as Map<String, dynamic>;
        final isDirectChat = !_isEventChat;
        
        // Create the title widget
        Widget titleWidget;
        if (isDirectChat && _otherUserData != null) {
          final username = _otherUserData!['username'] ?? 'User';
          final profileImageUrl = _otherUserData!['profileImageUrl'];
          
          titleWidget = Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.blue.shade100,
                backgroundImage: profileImageUrl != null && profileImageUrl.toString().isNotEmpty
                    ? NetworkImage(profileImageUrl.toString())
                    : null,
                child: profileImageUrl == null || profileImageUrl.toString().isEmpty
                    ? const Icon(Icons.person, size: 18, color: Colors.blue)
                    : null,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  username,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        } else if (_isEventChat && _eventData != null) {
          final eventName = _eventData!['eventName'] ?? 'Event Chat';
          final eventImage = _eventData!['imageUrl'];
          
          titleWidget = Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.teal.shade100,
                backgroundImage: eventImage != null && eventImage.toString().isNotEmpty
                    ? NetworkImage(eventImage.toString())
                    : null,
                child: eventImage == null || eventImage.toString().isEmpty
                    ? const Icon(Icons.group, size: 18, color: Colors.teal)
                    : null,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  eventName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        } else {
          // Default title
          titleWidget = Text(chatData['eventName'] ?? 'Chat');
        }
        
        // Get current user profile image just once
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(currentUserId)
              .get(),
          builder: (context, userSnapshot) {
            final currentUserData = userSnapshot.data?.data() as Map<String, dynamic>?;
            final currentUserProfileImage = currentUserData?['profileImageUrl'];
            final currentUsername = currentUserData?['username'] ?? 'You';
            
            return _buildScaffold(
              titleWidget, 
              isDirectChat, 
              chatData, 
              currentUserProfileImage, 
              currentUsername
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}

// Separate widget just for message input to prevent rebuilds
class MessageInput extends StatefulWidget {
  final String chatId;
  final String currentUserId;
  
  const MessageInput({
    Key? key, 
    required this.chatId, 
    required this.currentUserId
  }) : super(key: key);

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _controller = TextEditingController();
  String _currentText = '';
  bool _isRecording = false;
  bool _isUploading = false;
  AudioRecorder? _audioRecorder;
  bool _isRecorderInitialized = false;
  
  @override
  void initState() {
    super.initState();
    // Initialize recorder with error handling
    _initializeRecorder();
  }
  
  // Add method to safely initialize recorder
  Future<void> _initializeRecorder() async {
    try {
      _audioRecorder = AudioRecorder();
      _isRecorderInitialized = true;
    } catch (e) {
      print('Error initializing audio recorder: $e');
      _isRecorderInitialized = false;
    }
  }
  
  void _handleSend() async {
    // Don't try to send empty messages
    if (_currentText.trim().isEmpty) return;
    
    // Store text and clear field immediately
    final textToSend = _currentText;
    setState(() {
      _currentText = '';
      _controller.clear();
    });
    
    try {
      // Get user data
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.currentUserId)
          .get();
      
      final username = userDoc.data()?['username'] ?? 'Anonymous';
      final profileImage = userDoc.data()?['profileImageUrl'] ?? '';
      
      // Create message data
      final messageData = {
        'senderId': widget.currentUserId,
        'senderName': username,
        'text': textToSend,
        'timestamp': FieldValue.serverTimestamp(),
        'profileImageUrl': profileImage,
      };

      // Add the message to Firestore
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .add(messageData);

      // Update last message info
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
            'lastMessage': textToSend,
            'lastMessageTime': FieldValue.serverTimestamp(),
            'lastSenderId': widget.currentUserId,
            'lastSenderName': username,
          });
    } catch (e) {
      print('Error sending message: $e');
      // No UI feedback about error to keep things simple
    }
  }

  // Image handling methods
  Future<void> _pickImage() async {
    if (_isUploading) return;

    try {
      final ImagePicker picker = ImagePicker();
      
      // Show options in bottom sheet
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      );
      
      if (source == null) return;
      
      final XFile? image = await picker.pickImage(source: source);
      if (image == null) return;
      
      setState(() {
        _isUploading = true;
      });
      
      // Upload image
      final imageUrl = await _uploadImageToImgur(File(image.path));
      
      if (imageUrl != null) {
        await _sendFileMessage(
          fileUrl: imageUrl,
          fileName: image.name,
          fileType: 'jpg',
          displayText: '[Photo]',
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image sent')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload image')),
        );
      }
    } catch (e) {
      print('Error picking/uploading image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }
  
  // Upload to Imgur
  Future<String?> _uploadImageToImgur(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      
      final response = await http.post(
        Uri.parse('https://api.imgur.com/3/image'),
        headers: {
          'Authorization': 'Client-ID 56fd005582df0ef',
        },
        body: {
          'image': base64Image,
          'type': 'base64'
        },
      );
      
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        return jsonResponse['data']['link'];
      } else {
        print('Imgur upload failed: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error in Imgur upload: $e');
      return null;
    }
  }
  
  // Voice message methods - updated for safety
  Future<void> _startRecording() async {
    // Check if recorder is initialized
    if (!_isRecorderInitialized || _audioRecorder == null) {
      await _initializeRecorder();
      if (!_isRecorderInitialized) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not initialize audio recorder')),
        );
        return;
      }
    }
    
    if (_isRecording) return;
    
    try {
      // Check permission
      final hasPermission = await _audioRecorder!.hasPermission();
      if (!hasPermission) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
        return;
      }
      
      // Create path for recording
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      // Start recording
      await _audioRecorder!.start(
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000, 
          sampleRate: 44100,
        ), 
        path: path
      );
      
      setState(() {
        _isRecording = true;
      });
      
      // Show recording indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recording... Press mic again to stop'),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      print('Error starting recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting recording: $e')),
      );
    }
  }
  
  Future<void> _stopRecording() async {
    if (!_isRecording || !_isRecorderInitialized || _audioRecorder == null) return;
    
    try {
      setState(() {
        _isRecording = false;
      });
      
      // Stop recording and get the path
      final path = await _audioRecorder!.stop();
      if (path == null) {
        print('Recording failed: No path returned');
        return;
      }
      
      // Read file as bytes and encode to Base64
      final file = File(path);
      if (!file.existsSync()) {
        print('Recording file not found at $path');
        return;
      }
      
      final bytes = await file.readAsBytes();
      final base64Audio = base64Encode(bytes);
      
      // Send voice message
      await _sendFileMessage(
        fileUrl: base64Audio,
        fileName: 'voice_message.m4a',
        fileType: 'm4a',
        displayText: '[Voice]',
        isVoice: true,
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice message sent')),
      );
    } catch (e) {
      print('Error stopping recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
  
  // Generic file message sender
  Future<void> _sendFileMessage({
    required String fileUrl,
    required String fileName,
    required String fileType,
    required String displayText,
    bool isVoice = false,
  }) async {
    try {
      // Get user data
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.currentUserId)
          .get();
      
      final username = userDoc.data()?['username'] ?? 'Anonymous';
      final profileImage = userDoc.data()?['profileImageUrl'] ?? '';
      
      // Create message data
      final messageData = {
        'senderId': widget.currentUserId,
        'senderName': username,
        'text': '',
        'fileUrl': fileUrl,
        'fileName': fileName,
        'fileType': fileType,
        'isVoice': isVoice,
        'timestamp': FieldValue.serverTimestamp(),
        'profileImageUrl': profileImage,
      };
      
      // Add message to Firestore
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .add(messageData);
      
      // Update chat info
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
            'lastMessage': '$displayText $fileName',
            'lastMessageTime': FieldValue.serverTimestamp(),
            'lastSenderId': widget.currentUserId,
            'lastSenderName': username,
          });
    } catch (e) {
      print('Error sending file message: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Row(
          children: [
            // Image button
            IconButton(
              icon: const Icon(Icons.photo_camera),
              color: Colors.blue,
              onPressed: _isUploading ? null : _pickImage,
            ),
            
            // Voice recording button
            IconButton(
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              color: _isRecording ? Colors.red : Colors.blue,
              onPressed: _isRecording ? _stopRecording : _startRecording,
            ),
            
            // Text field
            Expanded(
              child: TextField(
                controller: _controller,
                onChanged: (value) => _currentText = value,
                decoration: const InputDecoration(
                  hintText: 'Message',
                  contentPadding: EdgeInsets.symmetric(horizontal: 16.0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(24.0)),
                  ),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSend(),
              ),
            ),
            
            // Send button
            IconButton(
              icon: const Icon(Icons.send),
              color: Colors.blue,
              onPressed: _handleSend,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    // Safely dispose of audio recorder
    if (_isRecorderInitialized && _audioRecorder != null) {
      _audioRecorder!.dispose();
    }
    super.dispose();
  }
}

// Widget to display participants list
class ParticipantsList extends StatelessWidget {
  final List<dynamic> participants;
  
  const ParticipantsList({Key? key, required this.participants}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Participants',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${participants.length} people',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: participants.length,
              itemBuilder: (context, index) {
                final userId = participants[index];
                
                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection('users').doc(userId.toString()).get(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const ListTile(
                        leading: CircleAvatar(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        title: Text('Loading...'),
                      );
                    }
                    
                    final userData = snapshot.data?.data() as Map<String, dynamic>?;
                    final username = userData?['username'] ?? 'Unknown User';
                    final profileImageUrl = userData?['profileImageUrl'];
                    final isCurrentUser = userId == FirebaseAuth.instance.currentUser?.uid;
                    final faculty = userData?['faculty'] ?? '';
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.blue.withOpacity(0.2),
                          backgroundImage: profileImageUrl != null && profileImageUrl.isNotEmpty
                              ? NetworkImage(profileImageUrl)
                              : null,
                          child: profileImageUrl == null || profileImageUrl.isEmpty
                              ? const Icon(Icons.person, color: Colors.blue)
                              : null,
                        ),
                        title: Text(
                          username,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(isCurrentUser ? 'You' : 'Participant'),
                            if (faculty.isNotEmpty) Text('Faculty: $faculty', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                        trailing: isCurrentUser ? null : IconButton(
                          icon: const Icon(Icons.message, color: Colors.blue),
                          onPressed: () => _startDirectChat(context, userId.toString(), userData),
                          tooltip: 'Message directly',
                        ),
                        onTap: isCurrentUser ? null : () {
                          // Navigate to user profile if available
                          if (userData != null) {
                            // Add user ID to the data for profile page
                            final userDataWithId = Map<String, dynamic>.from(userData);
                            userDataWithId['id'] = userId.toString();
                            
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => UserPublicProfilePage(user: userDataWithId),
                              ),
                            );
                          }
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  // Helper method to start a direct chat with a participant
  void _startDirectChat(BuildContext context, String targetUserId, Map<String, dynamic>? userData) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be signed in to chat')),
        );
        return;
      }
      
      // Generate a chat ID for the direct conversation
      final chatId = _getChatId(currentUser.uid, targetUserId);
      
      // Check if the chat already exists
      final chatDoc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .get();
      
      if (!chatDoc.exists) {
        // Create a new chat document
        final currentUserDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();
        
        final currentUserData = currentUserDoc.data() ?? {};
        final currentUsername = currentUserData['username'] ?? 'User';
        final targetUsername = userData?['username'] ?? 'User';
        
        // Create participant details map
        Map<String, dynamic> participantDetails = {};
        participantDetails[currentUser.uid] = {
          'username': currentUsername,
          'profileImageUrl': currentUserData['profileImageUrl'] ?? '',
        };
        participantDetails[targetUserId] = {
          'username': targetUsername,
          'profileImageUrl': userData?['profileImageUrl'] ?? '',
        };
        
        // Create the chat document
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(chatId)
            .set({
              'participants': [currentUser.uid, targetUserId],
              'participantDetails': participantDetails,
              'lastMessage': 'Chat started',
              'lastMessageTime': FieldValue.serverTimestamp(),
              'lastSenderId': currentUser.uid,
              'lastSenderName': currentUsername,
              'createdAt': FieldValue.serverTimestamp(),
              'eventId': '', // Empty for direct chat
              'eventName': '$currentUsername & $targetUsername',
              'type': 'direct',
            });
      }
      
      // Navigate to the chat
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CommunicationPage(chatId: chatId),
        ),
      );
    } catch (e) {
      print('Error starting direct chat: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting chat: $e')),
      );
    }
  }
}

// Helper to generate a unique chatId for two users
String _getChatId(String uid1, String uid2) {
  final ids = [uid1, uid2]..sort();
  return ids.join('_');
}

