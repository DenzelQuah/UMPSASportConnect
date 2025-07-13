import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SkillReviewPage extends StatefulWidget {
  const SkillReviewPage({super.key});

  @override
  _SkillReviewPageState createState() => _SkillReviewPageState();
}

class _SkillReviewPageState extends State<SkillReviewPage> {
  final currentUser = FirebaseAuth.instance.currentUser!;
  final _formKey = GlobalKey<FormState>();

  final List<String> _sports = [
    'Badminton',
    'Basketball',
    'Football',
    'Tennis',
    'Pétanque',
    'Lawn Bowls',
    'Sepak Takraw',
    'Volleyball',
    'Chess',
    'Ten-pin Bowling',
    'Netball',
    'Table Tennis',
    'Handball',
    'E-sport',
  ];
  String? _selectedSport;

  final List<String> _skillLevels = [
    "Beginner",
    "Intermediate",
    "Advanced",
    "Pro",
  ];
  String _skillLevel = "";

  bool _isSubmitting = false;

  int? _yearsOfPlaying;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Widget _buildSportDropdown() {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: "Select Sport",
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey.shade100,
      ),
      value: _selectedSport,
      items:
          _sports
              .map(
                (sport) => DropdownMenuItem(value: sport, child: Text(sport)),
              )
              .toList(),
      onChanged: (val) {
        setState(() {
          _selectedSport = val;
        });
      },
      validator:
          (value) =>
              value == null || value.isEmpty ? "Please select a sport" : null,
    );
  }

  Widget _buildSkillLevelSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Select your skill level:",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              _skillLevels.map((level) {
                return ChoiceChip(
                  label: Text(level),
                  selected: _skillLevel == level,
                  selectedColor: Colors.blue.shade600,
                  onSelected: (_) {
                    setState(() {
                      _skillLevel = level;
                    });
                  },
                  labelStyle: TextStyle(
                    color: _skillLevel == level ? Colors.white : Colors.black,
                  ),
                  backgroundColor: Colors.grey.shade200,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }

  Widget _buildYearsOfPlayingField() {
    return TextFormField(
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: "Years of Playing",
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey.shade100,
      ),
      initialValue: _yearsOfPlaying?.toString(),
      onChanged: (val) {
        setState(() {
          _yearsOfPlaying = int.tryParse(val);
        });
      },
      validator: (val) {
        if (val == null || val.isEmpty) return "Please enter years of playing";
        final n = int.tryParse(val);
        if (n == null || n < 0 || n > 100) {
          return "Enter a valid number of years";
        }
        return null;
      },
    );
  }

  Future<void> _showPreviewDialog() async {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text("Review Your Skill Assessment"),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Sport: ${_selectedSport ?? ""}"),
                  const SizedBox(height: 8),
                  Text("Skill Level: $_skillLevel"),
                  const SizedBox(height: 8),
                  if (_yearsOfPlaying != null)
                    Text("Years of Playing: $_yearsOfPlaying"),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Edit"),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _submitReview();
                },
                child: const Text("Submit"),
              ),
            ],
          ),
    );
  }

  Future<void> _submitReview() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSport == null || _selectedSport!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please select a sport.")));
      return;
    }
    if (_skillLevel.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select your skill level.")),
      );
      return;
    }
    if (_yearsOfPlaying == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter years of playing.")),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final query =
          await FirebaseFirestore.instance
              .collection('sportSkillReviews')
              .where('uid', isEqualTo: currentUser.uid)
              .where('sport', isEqualTo: _selectedSport)
              .get();

      final reviewData = {
        'uid': currentUser.uid,
        'sport': _selectedSport,
        'skillLevel': _skillLevel,
        'yearsOfPlaying': _yearsOfPlaying,
        'timestamp': FieldValue.serverTimestamp(),
      };

      if (query.docs.isNotEmpty) {
        // Use .doc(id).set(data, SetOptions(merge: true)) to ensure merge and trigger listeners
        await FirebaseFirestore.instance
            .collection('sportSkillReviews')
            .doc(query.docs.first.id)
            .set(reviewData, SetOptions(merge: true));
      } else {
        await FirebaseFirestore.instance
            .collection('sportSkillReviews')
            .add(reviewData);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Skill review submitted successfully!")),
      );

      setState(() {
        _selectedSport = null;
        _skillLevel = "";
        _yearsOfPlaying = null;
      });
    } catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Submission failed: $error")));
    } finally {
      setState(() => _isSubmitting = false);
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
        title: const Text("Skill Review"),
        centerTitle: true,
      ),
      body:
          _isSubmitting
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSportDropdown(),
                          const SizedBox(height: 16),
                          _buildSkillLevelSelector(),
                          const SizedBox(height: 16),
                          _buildYearsOfPlayingField(),
                          const SizedBox(height: 16),
                          const SizedBox(height: 25),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: _showPreviewDialog,
                              icon: const Icon(Icons.preview),
                              label: const Text(
                                "Preview & Submit",
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color.fromARGB(255, 0, 51, 153),
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
              ),
    );
  }
}
