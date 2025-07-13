import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import '../pages/communication.dart';

// Create a global key for navigator
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  StreamSubscription<QuerySnapshot>? _chatSubscription;
  StreamSubscription<QuerySnapshot>? _eventsSubscription;
  String? _currentUserId;
  
  // Initialize notification service
  Future<void> initialize() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    
    _currentUserId = currentUser.uid;
    
    // Initialize notifications with action handling
    const initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    final initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    
    // Configure notification actions
    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _handleNotificationTap,
    );
    
    // Request notification permissions
    await _requestNotificationPermissions();
    
    // Listen for new messages in chats
    await _setupChatNotifications();
    
    // Listen for event join acceptances
    await _setupEventJoinNotifications();
  }
  
  // Handle notification tap - FIXED VERSION
  void _handleNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) {
      final parts = payload.split(':');
      if (parts.length == 2) {
        final type = parts[0];
        final id = parts[1];
        
        if (type == 'chat') {
          // Navigate directly to chat
          _navigateToChat(id);
        } else if (type == 'event_join') {
          // For event join notifications, navigate to the event chat
          _navigateToChat(id);
        }
      }
    }
  }
  
  // Navigate to chat screen - IMPROVED VERSION
  void _navigateToChat(String chatId) {
    final navigatorState = navigatorKey.currentState;
    if (navigatorState != null && navigatorState.mounted) {
      // Get the current context
      final context = navigatorState.context;
      
      // Navigate to the chat
      navigatorState.push(
        MaterialPageRoute(
          builder: (context) => CommunicationPage(chatId: chatId),
        ),
      );
      
      // Show a brief confirmation message
      Future.delayed(const Duration(milliseconds: 300), () {
        if (navigatorState.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Opening chat...'),
              duration: Duration(seconds: 1),
              backgroundColor: Color.fromARGB(255, 0, 25, 116),
            ),
          );
        }
      });
    } else {
      // If navigator is not available, store the request for later
      debugPrint('Navigator not available, storing navigation request for later');
      _storeNavigationRequest(chatId);
    }
  }
  
  // Store navigation request to be handled when app is in foreground - IMPROVED VERSION
  Future<void> _storeNavigationRequest(String chatId) async {
    if (_currentUserId == null) return;
    
    try {
      // Get event name for better notification message
      String eventName = 'an event';
      try {
        final chatDoc = await FirebaseFirestore.instance
            .collection('chats')
            .doc(chatId)
            .get();
        if (chatDoc.exists) {
          final chatData = chatDoc.data() as Map<String, dynamic>;
          eventName = chatData['eventName'] ?? 'an event';
        }
      } catch (e) {
        debugPrint('Error getting event name: $e');
      }
      
      // Store the navigation request in Firestore for the current user
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .collection('notifications')
          .add({
            'type': 'event_join',
            'actionType': 'navigate_to_chat',
            'actionData': chatId,
            'eventName': eventName,
            'timestamp': FieldValue.serverTimestamp(),
            'read': false,
            'message': 'You have been added to $eventName chat',
          });
      
      debugPrint('Navigation request stored successfully');
    } catch (e) {
      debugPrint('Error storing navigation request: $e');
    }
  }
  
  // Request notification permissions
  Future<void> _requestNotificationPermissions() async {
    final status = await Permission.notification.request();
    if (status.isGranted) {
      debugPrint('Notification permission granted.');
    } else {
      debugPrint('Notification permission denied.');
    }
  }
  
  // Setup chat notifications
  Future<void> _setupChatNotifications() async {
    if (_currentUserId == null) return;
    
    _chatSubscription?.cancel();
    _chatSubscription = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: _currentUserId)
        .snapshots()
        .listen((snapshot) {
          for (var change in snapshot.docChanges) {
            // Only process modified documents
            if (change.type == DocumentChangeType.modified) {
              final data = change.doc.data() as Map<String, dynamic>;
              // Only notify if the last message is not from the current user
              if (data['lastSenderId'] != _currentUserId && 
                  data['lastMessage'] != null &&
                  data['lastMessage'].toString().isNotEmpty) {
                _showNotification(
                  data['eventName'] ?? 'New Message',
                  data['lastMessage'] ?? 'You have a new message.',
                  'chat_${change.doc.id}',
                  'chat:${change.doc.id}',
                );
              }
            }
          }
        });
  }
  
  // Setup event join acceptance notifications
  Future<void> _setupEventJoinNotifications() async {
    if (_currentUserId == null) return;
    
    _eventsSubscription?.cancel();
    _eventsSubscription = FirebaseFirestore.instance
        .collection('events')
        .where('joinedUsers', arrayContains: _currentUserId)
        .snapshots()
        .listen((snapshot) {
          for (var change in snapshot.docChanges) {
            // Process only newly added documents or modified ones
            if (change.type == DocumentChangeType.added || 
                change.type == DocumentChangeType.modified) {
              final data = change.doc.data() as Map<String, dynamic>;
              final eventName = data['eventName'] ?? 'Event';
              final joinedUsers = data['joinedUsers'] as List<dynamic>? ?? [];
              
              // Check if the current user was just added to joinedUsers
              if (joinedUsers.contains(_currentUserId)) {
                // Check if this is a recent addition by looking at a timestamp field
                // We can use the lastUpdated field if it exists, or just notify anyway
                _showNotification(
                  'Join Request Accepted',
                  'You have been accepted to join "$eventName"! Tap to open the chat.',
                  'event_join_${change.doc.id}',
                  'event_join:${change.doc.id}',
                );
                
                // Automatically add user to the event chat if not already there
                _addUserToEventChat(change.doc.id);
              }
            }
          }
        });
  }
  
  // Add user to event chat if not already there
  Future<void> _addUserToEventChat(String eventId) async {
    if (_currentUserId == null) return;
    
    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(eventId)
          .get();
      
      if (chatDoc.exists) {
        final chatData = chatDoc.data() as Map<String, dynamic>;
        final participants = chatData['participants'] as List<dynamic>? ?? [];
        
        // Only add if not already a participant
        if (!participants.contains(_currentUserId)) {
          await chatDoc.reference.update({
            'participants': FieldValue.arrayUnion([_currentUserId]),
          });
          debugPrint('User added to event chat successfully');
        }
      }
    } catch (e) {
      debugPrint('Error adding user to event chat: $e');
    }
  }
  
  // Show a notification - IMPROVED VERSION
  Future<void> _showNotification(String title, String body, String channelId, String payload) async {
    final androidPlatformChannelSpecifics = AndroidNotificationDetails(
      channelId,
      'UMPSA Sport',
      channelDescription: 'Notifications for UMPSA Sport app',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      // Add action buttons for better user experience
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'open_chat',
          'Open Chat',
          showsUserInterface: true,
        ),
      ],
    );
    
    final platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );
    
    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000), // Better unique ID
      title,
      body,
      platformChannelSpecifics,
      payload: payload, // Add payload for navigation
    );
  }
  
  // Add method to manually trigger navigation (useful for testing)
  void triggerNavigationToChat(String chatId) {
    _navigateToChat(chatId);
  }
  
  // Add method to check if navigator is ready
  bool get isNavigatorReady => navigatorKey.currentState != null && navigatorKey.currentState!.mounted;
  
  // Dispose subscriptions
  void dispose() {
    _chatSubscription?.cancel();
    _eventsSubscription?.cancel();
  }
}