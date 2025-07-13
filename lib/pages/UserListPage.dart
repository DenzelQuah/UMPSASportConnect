import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';


import 'UserPublicProfilePage.dart';

class UserListPage extends StatefulWidget {
  const UserListPage({super.key});

  @override
  State<UserListPage> createState() => _UserListPageState();
}

class _UserListPageState extends State<UserListPage> {
  String? _selectedFilter;
  Set<String> selectedSports = {};
  Set<String> selectedSkillLevels = {};
  String _searchQuery = '';

  final List<String> _filters = [
    'All',
    'Badminton',
    'Basketball',
    'Football',
    'Tennis',
    'Volleyball',
    'Chess',
    'E-sport',
  ];

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
        title: const Text('All Users'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                // Search field
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search by username',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 0,
                        horizontal: 16,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.trim().toLowerCase();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Filter button on the right
                ElevatedButton.icon(
                  onPressed: _showFilterDialog,
                  icon: const Icon(Icons.filter_list, color: Colors.white),
                  label: const Text(
                    'Filter',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance.collection('users').get(),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!userSnapshot.hasData || userSnapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No users found.'));
                }

                final users = userSnapshot.data!.docs;

                return FutureBuilder<QuerySnapshot>(
                  future:
                      FirebaseFirestore.instance
                          .collection('sportSkillReviews')
                          .get(),
                  builder: (context, skillSnapshot) {
                    if (!skillSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final skillReviews = skillSnapshot.data!.docs;

                    // Map uid to list of sport-skill entries
                    Map<String, List<Map<String, dynamic>>> skillMap = {};

                    for (var doc in skillReviews) {
                      final data = doc.data() as Map<String, dynamic>;
                      final uid = data['uid'];
                      if (uid == null) continue;

                      skillMap.putIfAbsent(uid, () => []).add({
                        'sport': data['sport'],
                        'skillLevel': data['skillLevel'],
                      });
                    }
                    // Filtered + enriched user list
                    final filteredUsers =
                        users.where((userDoc) {
                          final uid = userDoc.id;
                          final userData =
                              userDoc.data() as Map<String, dynamic>;
                          final userSkills = skillMap[uid] ?? [];

                          // Search filter
                          if (_searchQuery.isNotEmpty &&
                              !(userData['username']
                                          ?.toString()
                                          .toLowerCase() ??
                                      '')
                                  .contains(_searchQuery)) {
                            return false;
                          }

                          // Sports filter
                          if (selectedSports.isNotEmpty &&
                              !userSkills.any(
                                (entry) =>
                                    selectedSports.contains(entry['sport']),
                              )) {
                            return false;
                          }

                          // Skill level filter
                          if (selectedSkillLevels.isNotEmpty &&
                              !userSkills.any(
                                (entry) => selectedSkillLevels.contains(
                                  entry['skillLevel'],
                                ),
                              )) {
                            return false;
                          }

                          // Dropdown filter (legacy, keep for compatibility)
                          if (_selectedFilter == null ||
                              _selectedFilter == 'All') {
                            return true;
                          }

                          // Match sport or skillLevel from dropdown
                          return userSkills.any(
                            (entry) =>
                                entry['sport'] == _selectedFilter ||
                                entry['skillLevel'] == _selectedFilter,
                          );
                        }).toList();

                    if (filteredUsers.isEmpty) {
                      return const Center(
                        child: Text('No users match your filters.'),
                      );
                    }

                    return ListView.builder(
                      itemCount: filteredUsers.length,
                      itemBuilder: (context, index) {
                        final userDoc = filteredUsers[index];
                        final userData = userDoc.data() as Map<String, dynamic>;
                        final uid = userDoc.id;

                        final userSkills = skillMap[uid] ?? [];
                        final sportsList = userSkills
                            .map((e) => e['sport'])
                            .join(', ');
                        final levelsList = userSkills
                            .map((e) => e['skillLevel'])
                            .toSet()
                            .join(', ');

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage:
                                userData['profileImageUrl'] != null &&
                                        userData['profileImageUrl']
                                            .toString()
                                            .isNotEmpty
                                    ? NetworkImage(userData['profileImageUrl'])
                                    : const AssetImage(
                                          "assets/default_profile.png",
                                        )
                                        as ImageProvider,
                          ),
                          title: Text(userData['username'] ?? ''),
                          subtitle: Text(
                            'Skill Level(s): $levelsList\nSports: $sportsList',
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) =>
                                        UserPublicProfilePage(user: userData),
                              ),
                            );
                          },
                        );
                      },
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

  void _showFilterDialog() {
    final tempSelectedSports = Set<String>.from(selectedSports);
    final tempSelectedSkillLevels = Set<String>.from(selectedSkillLevels);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Filter Users'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select Sports'),
                ..._filters.where((e) => e != 'All').map((sport) {
                  return CheckboxListTile(
                    title: Text(sport),
                    value: tempSelectedSports.contains(sport),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          tempSelectedSports.add(sport);
                        } else {
                          tempSelectedSports.remove(sport);
                        }
                      });
                    },
                  );
                }).toList(),
                const Divider(),
                const Text('Select Skill Levels'),
                ...['Beginner', 'Intermediate', 'Advanced'].map((level) {
                  return CheckboxListTile(
                    title: Text(level),
                    value: tempSelectedSkillLevels.contains(level),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          tempSelectedSkillLevels.add(level);
                        } else {
                          tempSelectedSkillLevels.remove(level);
                        }
                      });
                    },
                  );
                }).toList(),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  selectedSports = tempSelectedSports;
                  selectedSkillLevels = tempSelectedSkillLevels;
                });
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }
}
