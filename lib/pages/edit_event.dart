import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'mappicker.dart';

class EditEventPage extends StatefulWidget {
  final String eventId;
  const EditEventPage({super.key, required this.eventId});

  @override
  State<EditEventPage> createState() => _EditEventPageState();
}

class _EditEventPageState extends State<EditEventPage> {
  final List<String> _sportOptions = [
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

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _sportController = TextEditingController();
  final _maxParticipantsController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  double? _latitude;
  double? _longitude;
  String? _locationName;
  String? _imageUrl;
  bool _isLoading = false;
  String? _manualLocationName; // For manual override

  // Helper method to check if a road name should be excluded
  bool _isGenericRoadName(String roadName) {
    if (roadName.isEmpty) return true;
    final lowerRoad = roadName.toLowerCase();
    final genericNames = [
      'unnamed road',
      'unnamed',
      'unknown road',
      'unknown',
      'no name',
      'jalan tanpa nama',
      'jalan',
      'road',
    ];
    return genericNames.any(
      (generic) => lowerRoad == generic || lowerRoad.startsWith(generic),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadEventData();
  }

  Future<void> _loadEventData() async {
    final doc =
        await FirebaseFirestore.instance
            .collection('events')
            .doc(widget.eventId)
            .get();
    final data = doc.data();
    if (data == null) return;

    setState(() {
      _nameController.text = data['eventName'];
      _sportController.text = data['sport'];
      _maxParticipantsController.text = data['maxParticipants'].toString();
      _selectedDate = DateFormat('dd-MM-yyyy').parse(data['date']);
      _startTime = _parseTime(data['startTime']);
      _endTime = _parseTime(data['endTime']);
      _latitude = (data['latitude'] as num?)?.toDouble();
      _longitude = (data['longitude'] as num?)?.toDouble();
      _imageUrl = data['imageUrl'];
    });

    if (_latitude != null && _longitude != null) {
      _fetchLocationName(_latitude!, _longitude!);
    }
  }

  TimeOfDay _parseTime(String timeStr) {
    try {
      final dt = DateFormat('hh:mm a').parse(timeStr);
      return TimeOfDay(hour: dt.hour, minute: dt.minute);
    } catch (_) {
      final parts = timeStr.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
  }

  String _formatTime(TimeOfDay time) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return DateFormat("hh:mm a").format(dt);
  }

  Future<void> _fetchLocationName(double lat, double lng) async {
    final uri = Uri.parse(
      'https://api.opencagedata.com/geocode/v1/json?q=$lat+$lng&key=b581c8b6fe7140948618cb02e439a7ce&countrycode=my',
    );
    final res = await http.get(uri);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final results = data['results'];
      if (results != null && results.isNotEmpty) {
        final formatted = results[0]['formatted'] ?? '';
        final components = results[0]['components'];
        final road = components['road'] ?? '';
        final filteredRoad = _isGenericRoadName(road) ? '' : road;
        final suburb = components['suburb'] ?? '';
        final city =
            components['city'] ??
            components['town'] ??
            components['village'] ??
            '';
        final state = components['state'] ?? '';
        final country = components['country'] ?? '';
        final parts =
            [
              filteredRoad,
              suburb,
              city,
              state,
              country,
            ].where((part) => part.isNotEmpty).toList();
        final fallbackFormatted = parts.join(', ');
        final hasGenericRoadInFormatted =
            formatted.toLowerCase().contains('unnamed road') ||
            formatted.toLowerCase().contains('unnamed,') ||
            formatted.toLowerCase().startsWith('unnamed');
        setState(() {
          if (formatted.isNotEmpty && !hasGenericRoadInFormatted) {
            _locationName = formatted;
          } else if (fallbackFormatted.isNotEmpty) {
            _locationName = fallbackFormatted;
          } else {
            _locationName =
                "${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}";
          }
        });
      } else {
        setState(() {
          _locationName =
              "${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}";
        });
      }
    } else {
      setState(() {
        _locationName = "${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}";
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _isLoading = true);
      try {
        final Uint8List bytes = await picked.readAsBytes();
        final base64Image = base64Encode(bytes);
        final response = await http.post(
          Uri.parse('https://api.imgur.com/3/image'),
          headers: {'Authorization': 'Client-ID 56fd005582df0ef'},
          body: {'image': base64Image, 'type': 'base64'},
        );
        final data = jsonDecode(response.body);
        if (data['success']) {
          setState(() => _imageUrl = data['data']['link']);
        } else {
          throw Exception(data['data']['error']);
        }
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Image upload failed: $e")));
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now,
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime({required bool isStartTime}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          isStartTime
              ? (_startTime ?? TimeOfDay.now())
              : (_endTime ?? TimeOfDay.now()),
    );
    if (picked != null) {
      setState(() {
        if (isStartTime) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  // Replace your existing _pickLocation method with this:
  Future<void> _pickLocation() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) =>  MapPicker()),
    );

    if (result != null) {
      if (result is LatLng) {
        setState(() {
          _latitude = result.latitude;
          _longitude = result.longitude;
          _locationName = "Loading location...";
          _manualLocationName = null;
        });
        await _fetchLocationName(result.latitude, result.longitude);
      } else if (result is Map) {
        final lat = result['lat'];
        final lng = result['lng'];
        final name = result['name'];
        setState(() {
          _latitude = lat is double ? lat : (lat as num).toDouble();
          _longitude = lng is double ? lng : (lng as num).toDouble();
          _locationName = name is String ? name : null;
          _manualLocationName = null;
        });
      }
    }
  }

  // Update your _saveChanges method to handle the location properly:
  Future<void> _saveChanges() async {
    // Validate that all required fields are filled
    if (!_formKey.currentState!.validate() ||
        _selectedDate == null ||
        _startTime == null ||
        _endTime == null ||
        (_latitude == null || _longitude == null)) {
      // Add location validation
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all fields including location.'),
        ),
      );
      return;
    }

    // If location is still loading, wait a bit
    if (_locationName == "Loading location...") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait for location to load.')),
      );
      return;
    }

    // Get the current DateTime (now) for comparison
    final now = DateTime.now();

    // Convert selected start time and end time into DateTime
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

    // Validate that the start time is not in the past
    if (selectedStartDateTime.isBefore(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏰ Event start time cannot be in the past.'),
        ),
      );
      return;
    }
    // Validate that the end time is not in the past
    else if (endDateTime.isBefore(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏰ Event end time cannot be in the past.'),
        ),
      );
      return;
    }

    // Validate that start time is before end time
    if (selectedStartDateTime.isAfter(endDateTime) ||
        selectedStartDateTime.isAtSameMomentAs(endDateTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⏰ Start time must be before end time.')),
      );
      return;
    }

    // Format the chosen date and parse max participants
    final dateFormatted = DateFormat('dd-MM-yyyy').format(_selectedDate!);
    final maxParticipants =
        int.tryParse(_maxParticipantsController.text.trim()) ?? 0;

    // Determine which location name to use
    String locationToSave;
    if (_manualLocationName?.isNotEmpty == true) {
      locationToSave = _manualLocationName!;
    } else if (_locationName != null && _locationName!.isNotEmpty) {
      locationToSave = _locationName!;
    } else {
      locationToSave =
          "${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}";
    }

    // Save updates to Firestore
    await FirebaseFirestore.instance
        .collection('events')
        .doc(widget.eventId)
        .update({
          'eventName': _nameController.text.trim(),
          'sport': _sportController.text.trim(),
          'date': dateFormatted,
          'startTime': _formatTime(_startTime!),
          'endTime': _formatTime(_endTime!),
          'maxParticipants': maxParticipants,
          'latitude': _latitude,
          'longitude': _longitude,
          'locationName': locationToSave,
          'imageUrl': _imageUrl,
        });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Event updated successfully')),
    );
    Navigator.pop(context);
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
        title: const Text("Edit Event"),
        elevation: 0,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Container(
                color: const Color(0xFFF6F8FA), // subtle background
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
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
                                          _imageUrl != null
                                              ? Image.network(
                                                _imageUrl!,
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
                                controller: _nameController,
                                decoration: InputDecoration(
                                  labelText: "Event Name",
                                  prefixIcon: const Icon(Icons.title),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                validator:
                                    (v) =>
                                        v == null || v.trim().isEmpty
                                            ? "Enter event name"
                                            : null,
                              ),
                              const SizedBox(height: 18),
                              DropdownButtonFormField<String>(
                                value:
                                    _sportOptions.contains(
                                          _sportController.text,
                                        )
                                        ? _sportController.text
                                        : null,
                                decoration: InputDecoration(
                                  labelText: "Sport",
                                  prefixIcon: const Icon(Icons.sports_soccer),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                items:
                                    _sportOptions.map((sport) {
                                      return DropdownMenuItem(
                                        value: sport,
                                        child: Text(sport),
                                      );
                                    }).toList(),
                                onChanged:
                                    (value) => setState(() {
                                      _sportController.text = value ?? '';
                                    }),
                                validator:
                                    (value) =>
                                        value == null || value.isEmpty
                                            ? 'Select a sport'
                                            : null,
                              ),
                              const SizedBox(height: 18),
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
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
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
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      readOnly: true,
                                      decoration: InputDecoration(
                                        labelText: "Start Time",
                                        prefixIcon: const Icon(
                                          Icons.access_time,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                      controller: TextEditingController(
                                        text:
                                            _startTime != null
                                                ? _formatTime(_startTime!)
                                                : "",
                                      ),
                                      onTap: () => _pickTime(isStartTime: true),
                                      validator:
                                          (_) =>
                                              _startTime == null
                                                  ? 'Pick start time'
                                                  : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      readOnly: true,
                                      decoration: InputDecoration(
                                        labelText: "End Time",
                                        prefixIcon: const Icon(
                                          Icons.access_time_outlined,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                      controller: TextEditingController(
                                        text:
                                            _endTime != null
                                                ? _formatTime(_endTime!)
                                                : "",
                                      ),
                                      onTap:
                                          () => _pickTime(isStartTime: false),
                                      validator:
                                          (_) =>
                                              _endTime == null
                                                  ? 'Pick end time'
                                                  : null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              TextFormField(
                                controller: _maxParticipantsController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: "Max Participants",
                                  prefixIcon: const Icon(Icons.people),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  hintText: "e.g. 10",
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty)
                                    return "Enter max participants";
                                  final num = int.tryParse(v.trim());
                                  if (num == null || num <= 0)
                                    return "Must be > 0";
                                  return null;
                                },
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
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _manualLocationName?.isNotEmpty == true
                                          ? _manualLocationName!
                                          : _locationName ??
                                              (_latitude != null &&
                                                      _longitude != null
                                                  ? "Lat: ${_latitude!.toStringAsFixed(4)}, Lng: ${_longitude!.toStringAsFixed(4)}"
                                                  : "No location selected"),
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: _pickLocation,
                                    icon: const Icon(Icons.map),
                                    label: const Text("Pick Location"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color.fromARGB(
                                        255,
                                        108,
                                        124,
                                        120,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_locationName != null &&
                                  (_isGenericRoadName(_locationName!) ||
                                      _locationName!.contains('unnamed') ||
                                      _locationName ==
                                          "${_latitude?.toStringAsFixed(5)}, ${_longitude?.toStringAsFixed(5)}"))
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: TextFormField(
                                    initialValue: _manualLocationName,
                                    decoration: InputDecoration(
                                      labelText: 'Enter location name',
                                      hintText: 'e.g. Stadium Kuantan',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onChanged:
                                        (val) => setState(
                                          () => _manualLocationName = val,
                                        ),
                                  ),
                                ),
                              const SizedBox(height: 30),
                              Center(
                                child: SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _saveChanges,
                                    icon: const Icon(Icons.save),
                                    label: const Text(
                                      "Save Changes",
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
    );
  }
}
