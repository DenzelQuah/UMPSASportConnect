import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'communication.dart';
import 'edit_event.dart';
import 'mapviewer.dart';


class EventPage extends StatefulWidget {
  final String eventId;
  final VoidCallback onTap;
  final String? searchQuery;
  const EventPage({
    super.key,
    required this.onTap,
    required Map<String, dynamic> event,
    required this.eventId,
    this.searchQuery,
  });

  @override
  State<EventPage> createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> {
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
  String _searchTerm = '';
  String? _selectedSport;
  Set<String> _selectedStatuses = {'All'};
  bool _isRefreshing = false;

  final List<String> _allSports = [
    'Badminton',
    'Basketball',
    'Football',
    'Tennis',
    'Pétanque',
    'Lawn Bowls',
    'Sepak Takraw ',
    'Volleyball',
    ' Chess',
    'Ten-pin Bowling',
    'Netball',
    'Table Tennis',
    'Handball',
    'E-sport',
  ];

  // Map sport names to icons
  final Map<String, IconData> _sportIcons = {
    'Badminton': Icons.sports_tennis,
    'Basketball': Icons.sports_basketball,
    'Football': Icons.sports_soccer,
    'Tennis': Icons.sports_tennis,
    'Pétanque': Icons.sports,
    'Lawn Bowls': Icons.sports,
    'Sepak Takraw': Icons.sports_volleyball,
    'Volleyball': Icons.sports_volleyball,
    'Chess': Icons.extension,
    'Ten-pin Bowling': Icons.sports,
    'Netball': Icons.sports,
    'Table Tennis': Icons.sports_tennis,
    'Handball': Icons.sports_handball,
    'E-sport': Icons.sports_esports,
  };

  @override
  void initState() {
    super.initState();
    _searchTerm = widget.searchQuery?.toLowerCase() ?? '';
  }

  // Pull-to-refresh function
  Future<void> _onRefresh() async {
    setState(() {
      _isRefreshing = true;
    });

    try {
      // Add a small delay to show the refresh indicator
      await Future.delayed(const Duration(milliseconds: 500));
      
      // The StreamBuilder will automatically refresh when we rebuild
      // You can also clear any cached data here if needed
      setState(() {
        // This will trigger a rebuild and refresh the StreamBuilder
      });
      
      // Show a brief success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Events refreshed!'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      // Handle any errors during refresh
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _joinEvent(String eventId) async {
    final docRef = FirebaseFirestore.instance.collection('events').doc(eventId);
    final snapshot = await docRef.get();

    if (snapshot.exists) {
      final data = snapshot.data()!;
      List joinedUsers = data['joinedUsers'] ?? [];

      if (!joinedUsers.contains(currentUserId)) {
        joinedUsers.add(currentUserId);
        await docRef.update({
          'joinedUsers': FieldValue.arrayUnion([currentUserId]),
        });

        // Add user to the chat group participants
        final chatDoc =
            await FirebaseFirestore.instance
                .collection('chats')
                .doc(eventId)
                .get();

        if (chatDoc.exists) {
          await chatDoc.reference.update({
            'participants': FieldValue.arrayUnion([currentUserId]),
          });

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CommunicationPage(chatId: eventId),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Chat not found for this event.")),
          );
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You joined the event and the group chat!'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You have already joined this event.')),
        );
      }
    }
  }

// Fixed method to send join request for ongoing events
Future<void> _sendJoinRequest(String eventId) async {
  final docRef = FirebaseFirestore.instance.collection('events').doc(eventId);
  final snapshot = await docRef.get();

  if (snapshot.exists) {
    final data = snapshot.data()!;
    List joinRequests = data['joinRequests'] ?? [];
    List joinedUsers = data['joinedUsers'] ?? [];

    // Check if user is already joined
    if (joinedUsers.contains(currentUserId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You have already joined this event.')),
      );
      return;
    }

    // Check if request already exists
    bool requestExists = joinRequests.any((request) => 
      request['userId'] == currentUserId
    );

    if (!requestExists) {
      // Add join request - Use DateTime.now() instead of FieldValue.serverTimestamp()
      await docRef.update({
        'joinRequests': FieldValue.arrayUnion([{
          'userId': currentUserId,
          'timestamp': DateTime.now().toIso8601String(), // Fixed: Use DateTime.now()
          'status': 'pending'
        }]),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Join request sent to host!'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have already sent a join request.'),
        ),
      );
    }
  }
}

  // Method to handle join request (accept/reject)
  Future<void> _handleJoinRequest(String eventId, String requestUserId, bool accept) async {
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
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Join request accepted!')),
        );
      } else {
        // Just remove the request
        await docRef.update({
          'joinRequests': joinRequests,
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Join request rejected.')),
        );
      }
    }
  }

  // Method to show join requests dialog for hosts
  Future<void> _showJoinRequests(String eventId, List joinRequests) async {
    if (joinRequests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pending join requests.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join Requests'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: joinRequests.length,
            itemBuilder: (context, index) {
              final request = joinRequests[index];
              final userId = request['userId'];
              
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .get(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const ListTile(
                      title: Text('Loading...'),
                    );
                  }
                  
                  final userData = snapshot.data!.data() as Map<String, dynamic>?;
                  final username = userData?['username'] ?? 'Unknown User';
                  
                  return Card(
                    child: ListTile(
                      title: Text(username),
                      subtitle: Text('Requested to join'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.green),
                            onPressed: () {
                              _handleJoinRequest(eventId, userId, true);
                              Navigator.pop(context);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () {
                              _handleJoinRequest(eventId, userId, false);
                              Navigator.pop(context);
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEvent(String eventId) async {
    await FirebaseFirestore.instance.collection('events').doc(eventId).delete();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Event deleted.')));
  }

  Future<void> _editEvent(
    BuildContext context,
    String eventId,
    Map<String, dynamic> data,
  ) async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => EditEventPage(eventId: eventId)),
    );
  }

  Future<List<String>> _getUsernames(List<String>? userIds) async {
    List<String> usernames = [];

    if (userIds == null) return usernames;

    for (String? id in userIds) {
      if (id == null) {
        usernames.add('Unknown');
        continue;
      }

      final doc =
          await FirebaseFirestore.instance.collection('users').doc(id).get();
      final username =
          doc.exists ? (doc.data()?['username'] ?? 'Unknown') : 'Unknown';
      usernames.add(username);
    }

    return usernames;
  }

  String _getEventStatus(
    String dateStr,
    String startTimeStr,
    String endTimeStr,
  ) {
    try {
      final now = DateTime.now();

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

      if (now.isBefore(startDateTime)) {
        return 'Upcoming';
      } else if (now.isAfter(startDateTime) && now.isBefore(endDateTime)) {
        return 'Ongoing';
      } else {
        return 'Finished';
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<String> _getLocationName(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;

        // Build a detailed address
        final List<String> addressParts = [
          if (place.street != null && place.street!.isNotEmpty) place.street!,
          if (place.subLocality != null && place.subLocality!.isNotEmpty)
            place.subLocality!,
          if (place.locality != null && place.locality!.isNotEmpty)
            place.locality!,
          if (place.administrativeArea != null &&
              place.administrativeArea!.isNotEmpty)
            place.administrativeArea!,
          if (place.country != null && place.country!.isNotEmpty)
            place.country!,
        ];

        final String actualAddress = addressParts.join(', ');

        // Detect UMPSA main campus (adjust lat/lng range as needed)
        bool isInUMPSA =
            lat >= 3.531 && lat <= 3.535 && lng >= 103.425 && lng <= 103.431;
        final String placeName = isInUMPSA ? "UMPSA" : "";

        return placeName.isNotEmpty
            ? "$placeName, $actualAddress"
            : actualAddress;
      } else {
        return '$lat, $lng';
      }
    } catch (e) {
      return '$lat, $lng';
    }
  }

  // Method to launch maps
  void _launchMaps(double lat, double lng) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MapViewer(
          location: LatLng(lat, lng),
        ),
      ),
    );
  }

  Future<void> _leaveEvent(String eventId) async {
    final docRef = FirebaseFirestore.instance.collection('events').doc(eventId);
    final snapshot = await docRef.get();
    if (snapshot.exists) {
      final data = snapshot.data()!;
      List joinedUsers = data['joinedUsers'] ?? [];
      if (joinedUsers.contains(currentUserId)) {
        await docRef.update({
          'joinedUsers': FieldValue.arrayRemove([currentUserId]),
        });
        // Remove user from chat participants as well
        final chatDoc =
            await FirebaseFirestore.instance
                .collection('chats')
                .doc(eventId)
                .get();
        if (chatDoc.exists) {
          await chatDoc.reference.update({
            'participants': FieldValue.arrayRemove([currentUserId]),
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You have left the event.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You are not a participant of this event.'),
          ),
        );
      }
    }
  }

  // Method to open the event chat
  void _openEventChat(String eventId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommunicationPage(chatId: eventId),
      ),
    );
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
        title: const Text("Event Page"),
        actions: [
          // Add refresh button in app bar as well
          IconButton(
            icon: _isRefreshing 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _onRefresh,
            tooltip: 'Refresh events',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(130),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(text: _searchTerm),
                        decoration: const InputDecoration(
                          hintText: 'Search by name or sport...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchTerm = value.toLowerCase();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    DropdownButton<String>(
                      hint: const Text("Sport"),
                      value: _selectedSport,
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(
                            "All",
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        ..._allSports.map((sport) {
                          return DropdownMenuItem(
                            value: sport,
                            child: Text(sport),
                          );
                        }).toList(),
                      ],
                      onChanged: (value) {
                        setState(() => _selectedSport = value);
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Wrap(
                  spacing: 10,
                  children:
                      ['All', 'Upcoming', 'Ongoing', 'Finished'].map((status) {
                        return FilterChip(
                          label: Text(status),
                          selected: _selectedStatuses.contains(status),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                if (status == 'All') {
                                  _selectedStatuses = {'All'};
                                } else {
                                  _selectedStatuses.remove('All');
                                  _selectedStatuses.add(status);
                                }
                              } else {
                                _selectedStatuses.remove(status);
                                if (_selectedStatuses.isEmpty)
                                  _selectedStatuses.add('All');
                              }
                            });
                          },
                        );
                      }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: const Color.fromARGB(255, 0, 25, 116),
        backgroundColor: Colors.white,
        strokeWidth: 3,
        displacement: 40,
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('events').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());

            final events =
                snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final status = _getEventStatus(
                    data['date'],
                    data['startTime'],
                    data['endTime'],
                  );
                  final nameMatch = data['eventName']
                      .toString()
                      .toLowerCase()
                      .contains(_searchTerm);
                  final sportMatch = data['sport']
                      .toString()
                      .toLowerCase()
                      .contains(_searchTerm);
                  final statusMatch =
                      _selectedStatuses.contains('All') ||
                      _selectedStatuses.contains(status);
                  final sportFilterMatch =
                      _selectedSport == null || data['sport'] == _selectedSport;
                  return (nameMatch || sportMatch) &&
                      statusMatch &&
                      sportFilterMatch;
                }).toList();

            if (events.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.event_busy,
                      size: 64,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No events match your filters.',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Pull down to refresh',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(), // Ensures pull-to-refresh works even with few items
              itemCount: events.length,
              itemBuilder: (context, index) {
                final event = events[index];
                final data = event.data() as Map<String, dynamic>;
                final locationDetails =
                    data['locationDetails'] ?? 'No location details';
                final isHost = data['hostId'] == currentUserId;
                final joinedUsers =
                    data['joinedUsers'] != null
                        ? List<String>.from(data['joinedUsers'])
                        : [];
                final joinRequests = data['joinRequests'] ?? [];

                final status = _getEventStatus(
                  data['date'],
                  data['startTime'],
                  data['endTime'],
                );
                final double? lat =
                    (data['latitude'] is num)
                        ? (data['latitude'] as num).toDouble()
                        : null;
                final double? lng =
                    (data['longitude'] is num)
                        ? (data['longitude'] as num).toDouble()
                        : null;
                final hasLocation = lat != null && lng != null;
                final maxParticipants = data['maxParticipants'] ?? 0;
                final int slotsLeft = maxParticipants - joinedUsers.length;
                
                // Check if current user has pending request
                final hasPendingRequest = joinRequests.any((request) => 
                  request['userId'] == currentUserId && request['status'] == 'pending'
                );

                return FutureBuilder<String>(
                  future:
                      hasLocation
                          ? _getLocationName(lat, lng)
                          : Future.value('${lat ?? "N/A"}, ${lng ?? "N/A"}'),
                  builder: (context, locationSnap) {
                    if (locationSnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final String locationName =
                        locationSnap.hasData
                            ? locationSnap.data!
                            : '${lat ?? "N/A"}, ${lng ?? "N/A"}';

                    return Card(
                      margin: const EdgeInsets.all(16),
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Event image/banner
                          if (data['imageUrl'] != null &&
                              data['imageUrl'].toString().isNotEmpty)
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(18),
                              ),
                              child: Image.network(
                                data['imageUrl'],
                                width: double.infinity,
                                height: 180,
                                fit: BoxFit.cover,
                                errorBuilder:
                                    (context, error, stackTrace) =>
                                        const SizedBox(
                                          height: 180,
                                          child: Center(
                                            child: Text('Failed to load image'),
                                          ),
                                        ),
                              ),
                            )
                          else
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(18),
                              ),
                              child: Image.asset(
                                'assets/placeholder_image.png',
                                width: double.infinity,
                                height: 180,
                                fit: BoxFit.cover,
                              ),
                            ),

                          Padding(
                            padding: const EdgeInsets.all(18.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        data['eventName'],
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Color.fromARGB(
                                            255,
                                            0,
                                            25,
                                            116,
                                          ), // secondary
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Chip(
                                          label: Text(status),
                                          backgroundColor:
                                              status == 'Upcoming'
                                                  ? Colors.green.withOpacity(0.25)
                                                  : status == 'Ongoing'
                                                  ? Colors.orangeAccent.withOpacity(
                                                    0.18,
                                                  )
                                                  : Colors.red.withOpacity(0.18),
                                          labelStyle: TextStyle(
                                            color:
                                                status == 'Upcoming'
                                                    ? Colors.green
                                                    : status == 'Ongoing'
                                                    ? Colors.orange.shade900
                                                    : Colors.red,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        // Show join requests count for hosts
                                        if (isHost && status == 'Ongoing' && joinRequests.isNotEmpty)
                                          const SizedBox(width: 8),
                                        if (isHost && status == 'Ongoing' && joinRequests.isNotEmpty)
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
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      _sportIcons[data['sport'].trim()] ??
                                          Icons.sports,
                                      color: Colors.orangeAccent,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      data['sport'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 18),
                                    const Icon(
                                      Icons.calendar_today,
                                      color: Colors.amber,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      data['date'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.access_time,
                                      color: Color.fromARGB(255, 0, 25, 116),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      "${data['startTime']} - ${data['endTime']} (${data['duration']})",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on,
                                      color: Colors.redAccent,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        locationName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),

                              if (locationDetails.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 26,
                                    top: 2,
                                  ),
                                  child: Text(
                                    locationDetails,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.people,
                                    color: Colors.amber,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    "${joinedUsers.length}/$maxParticipants joined",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (slotsLeft > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 10),
                                      child: Chip(
                                        label: Text('$slotsLeft slots left'),
                                        backgroundColor: Colors.green
                                            .withOpacity(0.13),
                                        labelStyle: const TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              FutureBuilder<List<String>>(
                                future: _getUsernames(
                                  joinedUsers.cast<String>(),
                                ),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Text("Loading users...");
                                  } else if (snapshot.hasError) {
                                    return const Text("Failed to load users");
                                  } else {
                                    return Wrap(
                                      spacing: 6,
                                      children:
                                          snapshot.data!
                                              .map(
                                                (username) => Chip(
                                                  label: Text(username),
                                                  backgroundColor:
                                                      Colors.blueGrey.shade50,
                                                ),
                                              )
                                              .toList(),
                                    );
                                  }
                                },
                              ),
                              const SizedBox(height: 12),
                              Text(
                                data['description'] ?? '',
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: Colors.black87,
                                ),
                              ),
                             const SizedBox(height: 12),

// Action buttons section
                              // Host controls
                              if (isHost && status != 'Finished') 
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.edit,
                                          color: Colors.blue,
                                        ),
                                        onPressed: () => _editEvent(
                                          context,
                                          event.id,
                                          data,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete,
                                          color: Colors.red,
                                        ),
                                        onPressed: () async {
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Delete Event'),
                                              content: const Text(
                                                'Are you sure you want to delete this event?',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(
                                                    ctx,
                                                    false,
                                                  ),
                                                  child: const Text('Cancel'),
                                                ),
                                                TextButton(
                                                  onPressed: () => Navigator.pop(
                                                    ctx,
                                                    true,
                                                  ),
                                                  child: const Text('Delete'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            await _deleteEvent(event.id);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                
                              // Bottom action buttons
                              SizedBox(
                                width: double.infinity,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 12.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      // First row - View Location
                                      if (hasLocation)
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(minHeight: 48),
                                          child: Padding(
                                            padding: const EdgeInsets.only(bottom: 8.0),
                                            child: ElevatedButton.icon(
                                              onPressed: () => _launchMaps(lat, lng),
                                              icon: const Icon(Icons.location_on),
                                              label: const Text('View Location', style: TextStyle(fontSize: 16)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF0A192F),
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        
                                      // Second row - Chat and Leave buttons for participants
                                      if (joinedUsers.contains(currentUserId) && status != 'Finished')
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(minHeight: 48),
                                          child: Padding(
                                            padding: const EdgeInsets.only(bottom: 8.0),
                                            child: IntrinsicHeight(
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                                children: [
                                                  // Chat button
                                                  Expanded(
                                                    child: Padding(
                                                      padding: const EdgeInsets.only(right: 8.0),
                                                      child: ElevatedButton.icon(
                                                        onPressed: () => _openEventChat(event.id),
                                                        icon: const Icon(Icons.chat),
                                                        label: const Text('Chat', style: TextStyle(fontSize: 16)),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor: Colors.blue,
                                                          foregroundColor: Colors.white,
                                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                                          shape: RoundedRectangleBorder(
                                                            borderRadius: BorderRadius.circular(12),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  
                                                  // Leave button
                                                  Expanded(
                                                    child: ElevatedButton.icon(
                                                      onPressed: () async {
                                                        final confirm = await showDialog<bool>(
                                                          context: context,
                                                          builder: (context) => AlertDialog(
                                                            title: const Text('Leave Event'),
                                                            content: const Text('Are you sure you want to leave this event?'),
                                                            actions: [
                                                              TextButton(
                                                                onPressed: () => Navigator.pop(context, false),
                                                                child: const Text('Cancel'),
                                                              ),
                                                              TextButton(
                                                                onPressed: () => Navigator.pop(context, true),
                                                                child: const Text('Leave'),
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                        if (confirm == true) {
                                                          await _leaveEvent(event.id);
                                                        }
                                                      },
                                                      icon: const Icon(Icons.exit_to_app),
                                                      label: const Text('Leave', style: TextStyle(fontSize: 16)),
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: Colors.red,
                                                        foregroundColor: Colors.white,
                                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      
                                      // Join/Request buttons for non-participants
                                      if (!joinedUsers.contains(currentUserId) && 
                                          !hasPendingRequest && 
                                          status == 'Upcoming')
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(minHeight: 48),
                                          child: Padding(
                                            padding: const EdgeInsets.only(bottom: 8.0),
                                            child: ElevatedButton.icon(
                                              onPressed: slotsLeft > 0 
                                                  ? () => _joinEvent(event.id)
                                                  : null,
                                              icon: const Icon(Icons.person_add),
                                              label: Text(slotsLeft > 0 ? 'Join' : 'Full', style: TextStyle(fontSize: 16)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        
                                      // Request to join button for ongoing events
                                      if (!joinedUsers.contains(currentUserId) && 
                                          !hasPendingRequest && 
                                          status == 'Ongoing')
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(minHeight: 48),
                                          child: Padding(
                                            padding: const EdgeInsets.only(bottom: 8.0),
                                            child: ElevatedButton.icon(
                                              onPressed: slotsLeft > 0 
                                                  ? () => _sendJoinRequest(event.id)
                                                  : null,
                                              icon: const Icon(Icons.send),
                                              label: Text(slotsLeft > 0 ? 'Request to join' : 'Full', style: TextStyle(fontSize: 16)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.amber,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        
                                      // Pending request indicator
                                      if (hasPendingRequest)
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(minHeight: 48),
                                          child: Padding(
                                            padding: const EdgeInsets.only(bottom: 8.0),
                                            child: ElevatedButton.icon(
                                              onPressed: null,
                                              icon: const Icon(Icons.hourglass_empty),
                                              label: const Text('Request Pending', style: TextStyle(fontSize: 16)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.grey,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        
                                      // View join requests button for hosts
                                      if (isHost && status == 'Ongoing' && joinRequests.isNotEmpty)
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(minHeight: 48),
                                          child: Padding(
                                            padding: const EdgeInsets.only(bottom: 8.0),
                                            child: ElevatedButton.icon(
                                              onPressed: () => _showJoinRequests(event.id, joinRequests),
                                              icon: const Icon(Icons.notifications),
                                              label: Text('View Requests (${joinRequests.length})', style: TextStyle(fontSize: 16)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.orange,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        
                                      // Finished event indicator
                                      if (status == 'Finished')
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(minHeight: 48),
                                          child: Padding(
                                            padding: const EdgeInsets.only(bottom: 8.0),
                                            child: ElevatedButton.icon(
                                              onPressed: null,
                                              icon: const Icon(Icons.check_circle),
                                              label: const Text('Finished', style: TextStyle(fontSize: 16)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red,
                                                foregroundColor: Colors.white,
                                                disabledForegroundColor: Colors.white,
                                                disabledBackgroundColor: Colors.red.withOpacity(0.8),
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    ),
    );
  }
}
