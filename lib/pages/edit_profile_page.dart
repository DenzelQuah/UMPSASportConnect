import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  // Current Firebase user.
  final currentUser = FirebaseAuth.instance.currentUser!;
  final _formKey = GlobalKey<FormState>();

  // Controllers for form fields.
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _phoneController = TextEditingController();
  final _facultyController = TextEditingController();
  final _semesterController = TextEditingController();

  bool _isSaving = false;
  String? _profileImageUrl;
  File? _newImageFile;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // Loads the current user data from Firestore.
  Future<void> _loadUserData() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get();
      final data = snapshot.data()!;
      _usernameController.text = data['username'] ?? '';
      _bioController.text = data['bio'] ?? '';
      _phoneController.text = data['phone'] ?? '';
      _facultyController.text = data['faculty'] ?? '';
      _semesterController.text = data['semester'] ?? '';
      _profileImageUrl = data['profileImageUrl'];
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
    }
  }

  // Presents the user with options to pick an image from the camera or gallery.
  Future<void> _showImageSourceOptions() async {
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text("Camera"),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final picker = ImagePicker();
                    final picked = await picker.pickImage(
                      source: ImageSource.camera,
                    );
                    if (picked != null) {
                      setState(() {
                        _newImageFile = File(picked.path);
                      });
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text("Gallery"),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final picker = ImagePicker();
                    final picked = await picker.pickImage(
                      source: ImageSource.gallery,
                    );
                    if (picked != null) {
                      setState(() {
                        _newImageFile = File(picked.path);
                      });
                    }
                  },
                ),
              ],
            ),
          ),
    );
  }

  // Uploads the new image file to Imgur and returns the image URL.
  Future<String?> _uploadImageToImgur(File imageFile) async {
    // Replace with your Imgur Client-ID.
    const clientId = '56fd005582df0ef';
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    final response = await http.post(
      Uri.parse('https://api.imgur.com/3/image'),
      headers: {'Authorization': 'Client-ID $clientId'},
      body: {'image': base64Image, 'type': 'base64'},
    );

    if (response.statusCode == 200) {
      final jsonRes = jsonDecode(response.body);
      return jsonRes['data']['link'];
    } else {
      print('Imgur upload failed: ${response.body}');
      return null;
    }
  }

  // Saves the changes to Firestore. If a new image was selected, it is first uploaded to Imgur.
  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      String? finalImageUrl = _profileImageUrl;
      if (_newImageFile != null) {
        final uploadedUrl = await _uploadImageToImgur(_newImageFile!);
        if (uploadedUrl != null) {
          finalImageUrl = uploadedUrl;
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Image upload failed.')));
        }
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .update({
            'username': _usernameController.text.trim(),
            'bio': _bioController.text.trim(),
            'phone': _phoneController.text.trim(),
            'faculty': _facultyController.text.trim(),
            'semester': _semesterController.text.trim(),
            'profileImageUrl': finalImageUrl,
          });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
      // Refresh the form with latest data.
      await _loadUserData();
      
      // Return to previous screen after successful update
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  // Builds a consistent input decoration for text fields.
  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.grey.shade100,
    );
  }

  // Builds the profile image widget with an overlay icon to indicate editability.
  Widget _buildProfileImage() {
    final ImageProvider displayImage;
    if (_newImageFile != null) {
      displayImage = FileImage(_newImageFile!);
    } else if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
      displayImage = NetworkImage(_profileImageUrl!);
    } else {
      displayImage = const AssetImage('assets/default_avatar.png');
    }

    return GestureDetector(
      onTap: _showImageSourceOptions,
      child: CircleAvatar(
        radius: 50,
        backgroundImage: displayImage,
        // Display a camera icon overlay if using the default image.
        child:
            displayImage is AssetImage
                ? const Icon(Icons.camera_alt, size: 30, color: Colors.white)
                : null,
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    _facultyController.dispose();
    _semesterController.dispose();
    super.dispose();
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
        title: const Text("Edit Profile"),
        centerTitle: true,
      ),
      body:
          _isSaving
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
                      child: Column(
                        children: [
                          _buildProfileImage(),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _usernameController,
                            decoration: _buildInputDecoration(
                              "Username",
                              Icons.person,
                            ),
                            validator:
                                (value) =>
                                    value == null || value.isEmpty
                                        ? "Enter username"
                                        : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _bioController,
                            decoration: _buildInputDecoration(
                              "Bio",
                              Icons.info_outline,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: _buildInputDecoration(
                              "Phone",
                              Icons.phone,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _facultyController,
                            keyboardType: TextInputType.text,
                            decoration: _buildInputDecoration(
                              "Faculty",
                              Icons.school,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _semesterController,
                            keyboardType: TextInputType.text,
                            decoration: _buildInputDecoration(
                              "Semester",
                              Icons.calendar_today_rounded,
                            ),
                          ),
                          const SizedBox(height: 35),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: _saveChanges,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color.fromARGB(
                                  255,
                                  100,
                                  195,
                                  236,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.save),
                              label: const Text(
                                "Save Changes",
                                style: TextStyle(fontSize: 16),
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
