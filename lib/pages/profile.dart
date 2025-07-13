import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'edit_event.dart';
import 'edit_profile_page.dart';


class ProfilePage extends StatefulWidget {
  final VoidCallback onTap;
  const ProfilePage({super.key, required this.onTap});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final currentUser = FirebaseAuth.instance.currentUser;
  late Future<DocumentSnapshot> _userDataFuture;
  late Stream<QuerySnapshot> _hostedEventsStream;
  late Stream<QuerySnapshot> _joinedEventsStream;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _initializeStreams();
  }

  void _initializeStreams() {
    _userDataFuture =
        FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser!.uid)
            .get();
    _hostedEventsStream =
        FirebaseFirestore.instance
            .collection('events')
            .where('hostId', isEqualTo: currentUser!.uid)
            .snapshots();

    _joinedEventsStream =
        FirebaseFirestore.instance
            .collection('events')
            .where('joinedUsers', arrayContains: currentUser!.uid)
            .snapshots();
  }

  Future<void> _refreshProfile() async {
    try {
      // Refresh user data
      setState(() {
        _userDataFuture =
            FirebaseFirestore.instance
                .collection('users')
                .doc(currentUser!.uid)
                .get();
      });

      // Reinitialize streams to refresh events
      _initializeStreams();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile refreshed successfully!'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to refresh profile: $e'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() => _isUploading = true);

      try {
        final imageBytes = await pickedFile.readAsBytes();
        final base64Image = base64Encode(imageBytes);

        // Upload to Imgur
        final response = await http.post(
          Uri.parse('https://api.imgur.com/3/image'),
          headers: {'Authorization': 'Client-ID 56fd005582df0ef'},
          body: {'image': base64Image, 'type': 'base64'},
        );

        final data = jsonDecode(response.body);
        if (response.statusCode == 200 && data['success']) {
          final imageUrl = data['data']['link'];

          // Update Firestore
          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser!.uid)
              .update({'profileImageUrl': imageUrl});

          setState(() {
            _userDataFuture =
                FirebaseFirestore.instance
                    .collection('users')
                    .doc(currentUser!.uid)
                    .get();
          });
        } else {
          throw Exception('Imgur upload failed: ${data['data']['error']}');
        }
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to upload image: $e')));
      } finally {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<String> _getLocationName(double? lat, double? lng) async {
    if (lat == null || lng == null) return 'Unknown location';
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final String locality =
            place.locality ?? place.subAdministrativeArea ?? '';
        final String country = place.country ?? '';
        return '$locality, $country';
      }
      return '$lat, $lng';
    } catch (e) {
      return '$lat, $lng';
    }
  }

  Future<void> _confirmDeleteEvent(String eventId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text("Delete Event"),
            content: const Text("Are you sure you want to delete this event?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Delete"),
              ),
            ],
          ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .delete();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Event deleted.")));
    }
  }

  Future<List<Map<String, dynamic>>> fetchSkillReviews() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final querySnapshot =
        await FirebaseFirestore.instance
            .collection('sportSkillReviews')
            .where('uid', isEqualTo: uid)
            .get();

    return querySnapshot.docs.map((doc) => doc.data()).toList();
  }

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
        title: const Text("Profile"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshProfile,
            tooltip: 'Refresh Profile',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshProfile,
        color: const Color.fromARGB(255, 0, 25, 116),
        backgroundColor: Colors.white,
        child: FutureBuilder<DocumentSnapshot>(
          future: _userDataFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final username = data['username'] ?? 'No name';
            final email = data['email'] ?? 'No email';
            final bio = data['bio'] ?? 'No bio';
            final phone = data['phone'] ?? 'No phone';
            final imageUrl = data['profileImageUrl'];
            final faculty = data['faculty'] ?? 'No faculty';
            final semester = data['semester'] ?? 'No semester';

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(), // Important for RefreshIndicator
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Profile Avatar
                    GestureDetector(
                      onTap: _pickAndUploadImage,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircleAvatar(
                            radius: 55,
                            backgroundColor: Colors.grey.shade300,
                            backgroundImage:
                                imageUrl != null ? NetworkImage(imageUrl) : null,
                            child:
                                imageUrl == null
                                    ? const Icon(
                                      Icons.person,
                                      size: 55,
                                      color: Colors.white70,
                                    )
                                    : null,
                          ),
                          if (_isUploading)
                            const CircleAvatar(
                              radius: 55,
                              backgroundColor: Colors.black45,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Stylish Info Card
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Text(
                                username,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Center(
                              child: Text(
                                email,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey[700],
                                ),
                              ),
                            ),
                            const Divider(height: 24),
                            Row(
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  size: 20,
                                  color: Colors.teal,
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: Text(
                                    bio.isNotEmpty ? bio : 'No bio added.',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(
                                  Icons.phone,
                                  size: 20,
                                  color: Colors.teal,
                                ),
                                const SizedBox(width: 20),
                                Text(
                                  phone.isNotEmpty ? phone : 'No phone added.',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(
                                  Icons.school,
                                  size: 20,
                                  color: Colors.teal,
                                ),
                                const SizedBox(width: 20),
                                Text(
                                  faculty.isNotEmpty
                                      ? faculty
                                      : 'No faculty added.',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today,
                                  size: 20,
                                  color: Colors.teal,
                                ),
                                const SizedBox(width: 20),
                                Text(
                                  semester.isNotEmpty
                                      ? semester
                                      : 'No semester added.',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ExpansionTile(
                                        tilePadding: EdgeInsets.zero,
                                        title: Row(
                                          children: [
                                            Align(
                                              alignment: Alignment.center,
                                              child: Icon(
                                                Icons.military_tech,
                                                color: Colors.teal,
                                              ),
                                            ),
                                            const SizedBox(width: 20),
                                            Text(
                                              "Skill Reviews",
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                          ],
                                        ),

                                        childrenPadding: const EdgeInsets.only(
                                          left: 8,
                                          right: 8,
                                          bottom: 8,
                                        ),
                                        children: [
                                          FutureBuilder<
                                            List<Map<String, dynamic>>
                                          >(
                                            future: fetchSkillReviews(),
                                            builder: (context, snapshot) {
                                              if (snapshot.connectionState ==
                                                  ConnectionState.waiting) {
                                                return const Padding(
                                                  padding: EdgeInsets.all(8),
                                                  child:
                                                      LinearProgressIndicator(),
                                                );
                                              } else if (snapshot.hasError) {
                                                return Padding(
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  child: Text(
                                                    "Error: ${snapshot.error}",
                                                  ),
                                                );
                                              } else if (!snapshot.hasData ||
                                                  snapshot.data!.isEmpty) {
                                                return const Padding(
                                                  padding: EdgeInsets.all(8),
                                                  child: Text(
                                                    "No skill reviews submitted yet.",
                                                  ),
                                                );
                                              }

                                              final reviews = snapshot.data!;
                                              return Column(
                                                children:
                                                    reviews.map((review) {
                                                      return Padding(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              vertical: 6.0,
                                                            ),
                                                        child: Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  Text(
                                                                    review['sport'] ??
                                                                        'Unknown Sport',
                                                                    style: const TextStyle(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                    ),
                                                                  ),
                                                                  Text(
                                                                    "Level: ${review['skillLevel'] ?? 'N/A'}",
                                                                  ),
                                                                  if (review['yearsOfPlaying'] !=
                                                                      null)
                                                                    Text(
                                                                      "Years of Playing: ${review['yearsOfPlaying']}",
                                                                    ),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    }).toList(),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Edit Button
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const EditProfilePage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text("Edit Profile"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(255, 92, 229, 250),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),

                    // Event Lists
                    _buildEventList(
                      title: "Joined Events",
                      stream: _joinedEventsStream,
                    ),
                    const SizedBox(height: 30),
                    _buildEventList(
                      title: "Hosted Events",
                      stream: _hostedEventsStream,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEventList({
    required String title,
    required Stream<QuerySnapshot> stream,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: stream,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final events = snapshot.data!.docs;

            if (events.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_busy, color: Colors.grey, size: 40),
                      const SizedBox(height: 8),
                      Text(
                        "No $title found.",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: events.length,
              itemBuilder: (context, index) {
                final eventData = events[index].data() as Map<String, dynamic>;
                final eventName = eventData['eventName'] ?? 'Unnamed Event';
                final sport = eventData['sport'] ?? 'No sport';
                final dateString = eventData['date'] as String?;
                final date =
                    dateString != null
                        ? DateFormat('dd-MM-yyyy').parse(dateString)
                        : null;
                final startTime = eventData['startTime'] ?? 'Start time';
                final endTime = eventData['endTime'] ?? 'End time';
                final double? lat = (eventData['latitude'] as num?)?.toDouble();
                final double? lng =
                    (eventData['longitude'] as num?)?.toDouble();

                final joinedUsers = List<String>.from(
                  eventData['joinedUsers'] ?? [],
                );
                final maxParticipants = eventData['maxParticipants'] ?? 0;
                final int slotsLeft = maxParticipants - joinedUsers.length;

                final now = DateTime.now();
                String status = 'Upcoming';

                if (date != null && startTime != null && endTime != null) {
                  try {
                    // Use AM/PM format parser
                    final dateFormat = DateFormat('dd-MM-yyyy');
                    final timeFormat = DateFormat('h:mm a');

                    final parsedDate = dateFormat.parse(
                      DateFormat('dd-MM-yyyy').format(date),
                    );

                    final start = timeFormat.parse(startTime);
                    final end = timeFormat.parse(endTime);

                    DateTime startDateTime = DateTime(
                      parsedDate.year,
                      parsedDate.month,
                      parsedDate.day,
                      start.hour,
                      start.minute,
                    );
                    DateTime endDateTime = DateTime(
                      parsedDate.year,
                      parsedDate.month,
                      parsedDate.day,
                      end.hour,
                      end.minute,
                    );

                    // Handle overnight events (e.g., 10 PM - 1 AM)
                    if (endDateTime.isBefore(startDateTime)) {
                      endDateTime = endDateTime.add(Duration(days: 1));
                    }

                    //print('Now: $now | Start: $startDateTime | End: $endDateTime');

                    if (now.isBefore(startDateTime)) {
                      status = 'Upcoming';
                    } else if (now.isBefore(endDateTime)) {
                      status = 'Ongoing';
                    } else {
                      status = 'Finished';
                    }
                  } catch (e) {
                    //print('Failed to determine status: $e');
                    status = 'Unknown';
                  }
                }

                return FutureBuilder<String>(
                  future: _getLocationName(lat, lng),
                  builder: (context, locationSnapshot) {
                    final location =
                        locationSnapshot.data ?? 'Loading location...';

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: ListTile(
                        title: Text(
                          eventName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Sport: $sport"),
                            if (date != null)
                              Text("Date: ${DateFormat.yMMMd().format(date)}"),
                            Text("Time: $startTime - $endTime"),
                            Text("Location: $location"),
                            Text(
                              "Participants: ${joinedUsers.length}/$maxParticipants (Slots left: $slotsLeft)",
                            ),
                            Text(
                              "Status: $status",
                              style: TextStyle(
                                color:
                                    status == 'Ongoing'
                                        ? Colors.orange
                                        : (status == 'Finished'
                                            ? Colors.red
                                            : Colors.green),
                              ),
                            ),
                          ],
                        ),
                        trailing:
                            title == "Hosted Events"
                                ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (status != 'Finished')
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Delete Button
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete,
                                              color: Colors.red,
                                            ),
                                            onPressed: () async {
                                              _confirmDeleteEvent(
                                                events[index].id,
                                              );
                                              final confirm = await showDialog<
                                                bool
                                              >(
                                                context: context,
                                                builder:
                                                    (_) => AlertDialog(
                                                      title: const Text(
                                                        "Delete Event",
                                                      ),
                                                      content: const Text(
                                                        "Are you sure you want to delete this event?",
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed:
                                                              () =>
                                                                  Navigator.pop(
                                                                    context,
                                                                    false,
                                                                  ),
                                                          child: const Text(
                                                            "Cancel",
                                                          ),
                                                        ),
                                                        SizedBox(width: 10),
                                                        TextButton(
                                                          onPressed:
                                                              () =>
                                                                  Navigator.pop(
                                                                    context,
                                                                    true,
                                                                  ),
                                                          child: const Text(
                                                            "Delete",
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                              );

                                              if (confirm == true) {
                                                await FirebaseFirestore.instance
                                                    .collection('events')
                                                    .doc(events[index].id)
                                                    .delete();
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      "Event deleted.",
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                          ),
                                          SizedBox(
                                            width: 10,
                                          ), // Optional space between buttons
                                          // Edit Button
                                          IconButton(
                                            icon: const Icon(
                                              Icons.edit,
                                              color: Colors.blue,
                                            ),
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder:
                                                      (_) => EditEventPage(
                                                        eventId:
                                                            events[index].id,
                                                      ),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    if (status == 'Finished')
                                      Icon(
                                        _getSportIcon(sport),
                                        color: Colors.teal,
                                        size: 28,
                                      ), // Sport icon for finished events
                                  ],
                                )
                                : null,
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }
}

// Place this helper function outside the ProfilePage class, at the top or bottom of the file
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