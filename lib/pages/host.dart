import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart' show canLaunchUrl, launchUrl;

import "mappicker.dart";

class HostPage extends StatefulWidget {
  const HostPage({super.key});

  @override
  State<HostPage> createState() => _HostPageState();
}

class _HostPageState extends State<HostPage> {
  final _formKey = GlobalKey<FormState>();
  final _eventNameController = TextEditingController();
  final _locationController = TextEditingController();

  final _descriptionController = TextEditingController();
  final _maxParticipantsController = TextEditingController();
  final _locationDetailsController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isLoading = false;
  double? _latitude;
  double? _longitude;

  //Array list
  final List<String> _sports = [
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
  String? _selectedSport;
  File? _pickedImage;

  // Map sport names to icons (use only available Material icons)
  final Map<String, IconData> _sportIcons = {
    'Badminton': Icons.sports_tennis, // closest available
    'Basketball': Icons.sports_basketball,
    'Football': Icons.sports_soccer,
    'Tennis': Icons.sports_tennis,
    'Pétanque': Icons.sports_golf, // closest available
    'Lawn Bowls': Icons.sports_golf, // closest available
    'Sepak Takraw': Icons.sports_volleyball,
    'Sepak Takraw ': Icons.sports_volleyball,
    'Volleyball': Icons.sports_volleyball,
    'Chess': Icons.extension, // closest available
    ' Chess': Icons.extension, // closest available
    'Ten-pin Bowling': Icons.sports, // fallback
    'Netball': Icons.sports_handball, // closest available
    'Table Tennis': Icons.sports_tennis, // closest available
    'Handball': Icons.sports_handball,
    'E-sport': Icons.sports_esports,
  };

  @override
  void initState() {
    super.initState();
    _selectedSport = _sports.first;
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _pickedImage = File(picked.path));
    }
  }

  Future<void> _pickDate() async {
    DateTime? pickedDate = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
      initialDate: DateTime.now(),
    );
    if (pickedDate != null) {
      setState(() => _selectedDate = pickedDate);
    }
  }

  Future<void> _pickStartTime() async {
    TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEndTime() async {
    TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null &&
        _startTime != null &&
        picked.hour * 60 + picked.minute >
            _startTime!.hour * 60 + _startTime!.minute) {
      setState(() => _endTime = picked);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time.')),
      );
    }
  }

  Duration _calculateDuration(TimeOfDay start, TimeOfDay end) {
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    int durationInMinutes = endMinutes - startMinutes;
    if (durationInMinutes < 0) durationInMinutes += 1440;
    return Duration(minutes: durationInMinutes);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '$hours hour${hours != 1 ? 's' : ''} $minutes min';
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MapPicker()),
    );

    if (result != null && result is Map) {
      _latitude = result['lat'];
      _longitude = result['lng'];

      if (result['name'] != null && result['name'].toString().isNotEmpty) {
        setState(() {
          _locationController.text = result['name'];
        });
      } else {
        try {
          List<Placemark> placemarks = await placemarkFromCoordinates(
            _latitude!,
            _longitude!,
          );
          Placemark place = placemarks.first;
          String address = "${place.name}, ${place.locality}, ${place.country}";

          setState(() {
            _locationController.text = address;
          });
        } catch (e) {
          debugPrint("Reverse geocoding failed: $e");
          setState(() {
            _locationController.text = "$_latitude, $_longitude";
          });
        }
      }
    }
  }

  Future<String?> _uploadImageToImgur(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse("https://api.imgur.com/3/image"),
        headers: {'Authorization': 'Client-ID 56fd005582df0ef'},
        body: {'image': base64Image, 'type': 'base64'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['data']['link'];
      } else {
        debugPrint('Imgur upload failed: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint("🔥 Imgur upload error: $e");
      return null;
    }
  }

  Future<void> _submitHostEvent() async {
    if (!_formKey.currentState!.validate() ||
        _selectedDate == null ||
        _startTime == null ||
        _endTime == null ||
        _pickedImage == null ||
        _latitude == null ||
        _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all fields.')),
      );
      return;
    }

    // 🔐 Time validation block
    final now = DateTime.now();
    final selectedStartDateTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _startTime!.hour,
      _startTime!.minute,
    );
    final endDateTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _endTime!.hour,
      _endTime!.minute,
    );

    if (selectedStartDateTime.isBefore(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏰ Event start time cannot be in the past.'),
        ),
      );
      return;
    } else if (endDateTime.isBefore(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏰ Event End time cannot be in the past.'),
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ You must be signed in to host an event.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final duration = _calculateDuration(_startTime!, _endTime!);
      final imageUrl = await _uploadImageToImgur(_pickedImage!);

      if (imageUrl == null) throw '❌ Image upload to Imgur failed.';

      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
      final username =
          userDoc.data()?['username'] ?? user.displayName ?? "Anonymous";

      final eventData = {
        "hostId": user.uid,
        "hostName": username,
        "eventName": _eventNameController.text.trim(),
        "sport": _selectedSport,
        "description": _descriptionController.text.trim(),
        "maxParticipants": int.parse(_maxParticipantsController.text),
        "date": DateFormat('dd-MM-yyyy').format(_selectedDate!),
        "startTime": _startTime!.format(context),
        "endTime": _endTime!.format(context),
        "duration": _formatDuration(duration),
        "location": _locationController.text,
        "locationDetails": _locationDetailsController.text.trim(),
        "latitude": _latitude,
        "longitude": _longitude,
        "imageUrl": imageUrl,
        "joinedUsers": [user.uid],
        "createdAt": Timestamp.now(),
      };

      final eventRef = await FirebaseFirestore.instance
          .collection('events')
          .add(eventData);

      // 🗨️ Create chat group using event ID
      await FirebaseFirestore.instance.collection('chats').doc(eventRef.id).set(
        {
          "eventId": eventRef.id, // this must match
          "eventName": _eventNameController.text.trim(),
          "createdBy": user.uid,
          "createdAt": Timestamp.now(),
          "participants": [user.uid],
        },
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🎉 Event successfully hosted!')),
      );

      Navigator.pop(context);
    } catch (e) {
      debugPrint("🔥 Firestore Error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('⚠️ Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  //open map Function
  void _openMapLocation() async {
    final url =
        'https://www.google.com/maps/search/?api=1&query=$_latitude,$_longitude';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps.')),
      );
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
        title: const Text('Host a Game'),
        elevation: 0,
      ),
      body: Stack(
        children: [
          Container(
            color: const Color(0xFFF6F8FA), // subtle background
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Card(
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 28,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child:
                                      _pickedImage != null
                                          ? Image.file(
                                            _pickedImage!,
                                            height: 160,
                                            width: 160,
                                            fit: BoxFit.cover,
                                          )
                                          : Container(
                                            height: 160,
                                            width: 160,
                                            color: Colors.grey[300],
                                            child: const Icon(
                                              Icons.image,
                                              size: 60,
                                              color: Colors.white70,
                                            ),
                                          ),
                                ),
                                Positioned(
                                  bottom: 8,
                                  right: 8,
                                  child: Material(
                                    color: Colors.white,
                                    shape: const CircleBorder(),
                                    elevation: 2,
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.edit,
                                        color: Color.fromARGB(
                                          255,
                                          108,
                                          124,
                                          120,
                                        ),
                                      ),
                                      onPressed: _pickImage,
                                      tooltip: 'Change Event Image',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: const [
                              Icon(Icons.event, color: Colors.teal),
                              SizedBox(width: 8),
                              Text(
                                "Event Details",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _eventNameController,
                            decoration: InputDecoration(
                              labelText: 'Event Name',
                              prefixIcon: const Icon(Icons.title),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            validator:
                                (value) =>
                                    value!.isEmpty
                                        ? 'Please enter an event name'
                                        : null,
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: _descriptionController,
                            decoration: InputDecoration(
                              labelText: 'Event Description',
                              prefixIcon: const Icon(Icons.description),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            validator:
                                (value) =>
                                    value!.isEmpty
                                        ? 'Please provide an event description'
                                        : null,
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: _maxParticipantsController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Maximum Participants',
                              prefixIcon: const Icon(Icons.people),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            validator:
                                (value) =>
                                    value!.isEmpty
                                        ? 'Please enter the maximum participants'
                                        : null,
                          ),
                          const SizedBox(height: 18),
                          DropdownButtonFormField<String>(
                            value: _selectedSport,
                            items:
                                _sports
                                    .map(
                                      (sport) => DropdownMenuItem(
                                        value: sport,
                                        child: Row(
                                          children: [
                                            Icon(
                                              _sportIcons[sport.trim()] ??
                                                  Icons.sports,
                                              color: Colors.black,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(sport),
                                          ],
                                        ),
                                      ),
                                    )
                                    .toList(),
                            onChanged:
                                (value) =>
                                    setState(() => _selectedSport = value),
                            decoration: InputDecoration(
                              labelText: 'Select Sport Type',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: const [
                              Icon(Icons.location_on, color: Colors.teal),
                              SizedBox(width: 8),
                              Text(
                                "Location",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _locationController,
                            readOnly: true,
                            onTap: _pickLocation,
                            decoration: InputDecoration(
                              labelText: 'Location (Tap to pick)',
                              prefixIcon: const Icon(Icons.location_on),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.map),
                                onPressed:
                                    (_latitude != null && _longitude != null)
                                        ? _openMapLocation
                                        : null,
                                tooltip: 'Open in Google Maps',
                              ),
                            ),
                            validator:
                                (value) =>
                                    value!.isEmpty
                                        ? 'Please select a location'
                                        : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _locationDetailsController,
                            decoration: InputDecoration(
                              labelText: 'Location Details',
                              hintText: 'e.g., Court 2 near the gym',
                              prefixIcon: const Icon(Icons.info_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: const [
                              Icon(Icons.access_time, color: Colors.teal),
                              SizedBox(width: 8),
                              Text(
                                "Date & Time",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  readOnly: true,
                                  decoration: InputDecoration(
                                    labelText: "Date",
                                    prefixIcon: const Icon(
                                      Icons.calendar_today,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  controller: TextEditingController(
                                    text:
                                        _selectedDate != null
                                            ? DateFormat(
                                              'dd-MM-yyyy',
                                            ).format(_selectedDate!)
                                            : "",
                                  ),
                                  onTap: _pickDate,
                                  validator:
                                      (_) =>
                                          _selectedDate == null
                                              ? 'Pick a date'
                                              : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  readOnly: true,
                                  decoration: InputDecoration(
                                    labelText: "Start Time",
                                    prefixIcon: const Icon(Icons.access_time),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  controller: TextEditingController(
                                    text:
                                        _startTime != null
                                            ? _startTime!.format(context)
                                            : "",
                                  ),
                                  onTap: _pickStartTime,
                                  validator:
                                      (_) =>
                                          _startTime == null
                                              ? 'Pick start time'
                                              : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  readOnly: true,
                                  decoration: InputDecoration(
                                    labelText: "End Time",
                                    prefixIcon: const Icon(
                                      Icons.access_time_outlined,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  controller: TextEditingController(
                                    text:
                                        _endTime != null
                                            ? _endTime!.format(context)
                                            : "",
                                  ),
                                  onTap: _pickEndTime,
                                  validator:
                                      (_) =>
                                          _endTime == null
                                              ? 'Pick end time'
                                              : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                          Center(
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _isLoading ? null : _submitHostEvent,
                                icon: const Icon(Icons.sports),
                                label: const Text(
                                  'Host Game',
                                  style: TextStyle(fontSize: 16),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  elevation: 2,
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
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
