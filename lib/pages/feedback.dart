import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _feedbackController = TextEditingController();
  final TextEditingController _otherCategoryController =
      TextEditingController();

  int _rating = 0;
  String? _selectedCategory;
  File? _selectedImage;
  String? _uploadedImageUrl;
  Position? _currentPosition;

  final ImagePicker _picker = ImagePicker();
  bool _isSubmitting = false;
  bool _isUploadingImage = false;

  @override
  void dispose() {
    _feedbackController.dispose();
    _otherCategoryController.dispose();
    super.dispose();
  }

  // ----- Location Functionality -----
  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Verify if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location services are disabled.')),
      );
      return;
    }

    // Check location permission.
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location permissions are denied.')),
        );
        return;
      }
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = position;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to get location: $e')));
    }
  }

  // ----- Image Picker Enhancements -----
  // Show an action sheet to let the user choose between camera and gallery.
  Future<void> _showImageSourceActionSheet() async {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('Gallery'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('Camera'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Pick an image from the chosen source.
  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  // ----- Imgur Upload Functionality -----
  Future<void> _uploadToImgur() async {
    if (_selectedImage == null) return;

    setState(() {
      _isUploadingImage = true;
    });

    try {
      final bytes = await _selectedImage!.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse('https://api.imgur.com/3/image'),
        headers: {'Authorization': 'Client-ID 56fd005582df0ef'},
        body: {'image': base64Image, 'type': 'base64'},
      );

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        _uploadedImageUrl = jsonResponse['data']['link'];
      } else {
        throw Exception('Image upload failed');
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Image upload failed: $e')));
    } finally {
      setState(() {
        _isUploadingImage = false;
      });
    }
  }

  // ----- Submission & Preview -----
  Future<void> _submitFeedback() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      if (_selectedImage != null) {
        await _uploadToImgur();
      }

      // Prepare the feedback data.
      Map<String, dynamic> feedbackData = {
        'rating': _rating,
        'category': _selectedCategory,
        'feedback': _feedbackController.text.trim(),
        'imageUrl': _uploadedImageUrl,
        'timestamp': Timestamp.now(),
      };

      if (_selectedCategory == 'Other') {
        feedbackData['otherCategory'] = _otherCategoryController.text.trim();
      }

      if (_currentPosition != null) {
        feedbackData['location'] = {
          'latitude': _currentPosition!.latitude,
          'longitude': _currentPosition!.longitude,
        };
      }

      await FirebaseFirestore.instance.collection('feedback').add(feedbackData);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Thank you for your feedback!')));

      _resetForm();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submission failed. Please try again.')),
      );
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _resetForm() {
    _feedbackController.clear();
    _otherCategoryController.clear();
    setState(() {
      _rating = 0;
      _selectedCategory = null;
      _selectedImage = null;
      _uploadedImageUrl = null;
      _currentPosition = null;
    });
  }

  // A preview dialog to confirm submission.
  Future<void> _showPreviewDialog() async {
    return showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text('Review Your Feedback'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Rating: $_rating'),
                  SizedBox(height: 10),
                  Text(
                    'Category: $_selectedCategory${_selectedCategory == "Other" ? " (${_otherCategoryController.text.trim()})" : ""}',
                  ),
                  SizedBox(height: 10),
                  Text('Feedback: ${_feedbackController.text.trim()}'),
                  SizedBox(height: 10),
                  if (_currentPosition != null)
                    Text(
                      'Location: (${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)})',
                    ),
                  if (_selectedImage != null) ...[
                    SizedBox(height: 10),
                    Text('Screenshot:'),
                    SizedBox(height: 10),
                    SizedBox(
                      height: 100,
                      width: 100,
                      child: Image.file(_selectedImage!, fit: BoxFit.cover),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text('Edit'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _submitFeedback();
                },
                child: Text('Submit'),
              ),
            ],
          ),
    );
  }

  // ----- UI Widgets -----
  // Star rating widget.
  Widget _buildStarRating() {
    return FormField<int>(
      initialValue: _rating,
      validator: (value) {
        if (value == null || value == 0) {
          return 'Please rate your experience';
        }
        return null;
      },
      builder: (formFieldState) {
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return IconButton(
                  icon: Icon(
                    index < _rating ? Icons.star : Icons.star_border,
                    size: 36,
                    color: Colors.amber,
                  ),
                  onPressed: () {
                    setState(() {
                      _rating = index + 1;
                      formFieldState.didChange(_rating);
                    });
                  },
                );
              }),
            ),
            if (formFieldState.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  formFieldState.errorText!,
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }

  // Dropdown for selecting a feedback category.
  Widget _buildDropdown() {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        border: OutlineInputBorder(),
        labelText: 'Feedback Category',
      ),
      value: _selectedCategory,
      items:
          ['Bug Report', 'Feature Request', 'General Comment', 'Other']
              .map(
                (label) => DropdownMenuItem(value: label, child: Text(label)),
              )
              .toList(),
      onChanged: (value) {
        setState(() {
          _selectedCategory = value;
        });
      },
      validator:
          (value) => value == null ? 'Please select a feedback category' : null,
    );
  }

  // Show a text field when "Other" category is selected.
  Widget _buildOtherCategoryField() {
    if (_selectedCategory != 'Other') return SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 15.0),
      child: TextFormField(
        controller: _otherCategoryController,
        decoration: InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Specify Other Category',
        ),
        validator: (value) {
          if (_selectedCategory == 'Other') {
            if (value == null || value.trim().isEmpty) {
              return 'Please specify the category';
            }
          }
          return null;
        },
      ),
    );
  }

  // Image picker widget.
  Widget _buildImagePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Optional: Upload a screenshot'),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _showImageSourceActionSheet,
          child: Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                _selectedImage != null
                    ? Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            _selectedImage!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                        Positioned(
                          top: 5,
                          right: 5,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedImage = null;
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.close, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    )
                    : Center(
                      child: Icon(
                        Icons.add_a_photo,
                        size: 40,
                        color: Colors.grey,
                      ),
                    ),
          ),
        ),
        if (_isUploadingImage)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  // Location picker widget.
  Widget _buildLocationPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Optional: Attach your current location'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child:
                  _currentPosition != null
                      ? Text(
                        'Location: (${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)})',
                        style: TextStyle(fontSize: 14),
                      )
                      : Text('No location attached'),
            ),
            IconButton(
              icon: Icon(Icons.my_location),
              onPressed: _getCurrentLocation,
            ),
          ],
        ),
      ],
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
        title: Text('Submit Feedback'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),

        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text(
                'We value your feedback!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Text(
                'Rate your experience:',
                style: TextStyle(fontSize: 14, fontFamily: 'Comic Sans'),
              ),
              _buildStarRating(),
              const SizedBox(height: 20),
              _buildDropdown(),
              _buildOtherCategoryField(),
              const SizedBox(height: 20),
              TextFormField(
                controller: _feedbackController,
                maxLines: 5,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Write your feedback here...',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your feedback';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              _buildImagePicker(),
              const SizedBox(height: 20),
              _buildLocationPicker(),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF8BB2F7),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 60,
                    vertical: 18,
                  ),
                  elevation: 5,
                ),
                onPressed:
                    _isSubmitting
                        ? null
                        : _showPreviewDialog, // Preview before submit
                child:
                    _isSubmitting
                        ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                        : Text(
                          'Preview & Submit',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Times New Roman',
                            color: Colors.white,
                          ),
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
