import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class MapPicker extends StatefulWidget {
  const MapPicker({super.key});

  @override
  State<MapPicker> createState() => _MapPickerState();
}

class _MapPickerState extends State<MapPicker> {
  LatLng _selectedLocation = LatLng(3.8126, 103.3256); // Default: Pahang
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  String _locationName = "Fetching location...";
  bool _isLoading = false;
  List<dynamic> _placeSuggestions = [];

  final String _apiKey =
      'b581c8b6fe7140948618cb02e439a7ce'; // Replace with your API key

  @override
  void initState() {
    super.initState();
    _updateLocationName(_selectedLocation);
    _determinePositionAndSetLocation();
  }

  bool _isInMalaysia(LatLng location) {
    return location.latitude >= 0.8 &&
        location.latitude <= 7.5 &&
        location.longitude >= 99.6 &&
        location.longitude <= 119.3;
  }

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

  Future<void> _updateLocationName(LatLng location) async {
    setState(() {
      _locationName = "Fetching location...";
      _isLoading = true;
    });

    try {
      final url =
          'https://api.opencagedata.com/geocode/v1/json?q=${location.latitude}+${location.longitude}&key=$_apiKey&countrycode=my';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'];

        if (results != null && results.isNotEmpty) {
          final formatted = results[0]['formatted'] ?? '';
          final components = results[0]['components'];

          // Get components and filter out generic road names
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

          // Build parts list with filtered road
          final parts =
              [
                filteredRoad,
                suburb,
                city,
                state,
                country,
              ].where((part) => part.isNotEmpty).toList();
          final fallbackFormatted = parts.join(', ');

          // Also check if the formatted address contains generic road names
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
                  "${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}";
            }
          });
        } else {
          setState(() {
            _locationName =
                "${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}";
          });
        }
      }
    } catch (_) {
      setState(() {
        _locationName =
            "${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}";
      });
    }

    setState(() => _isLoading = false);
  }

  Future<void> _fetchPlaceSuggestions(String query) async {
    if (query.isEmpty) {
      setState(() {
        _placeSuggestions = [];
      });
      return;
    }

    final url =
        'https://api.opencagedata.com/geocode/v1/json?q=${Uri.encodeComponent(query)}&key=$_apiKey&countrycode=my&limit=5';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _placeSuggestions = data['results'];
        });
      } else {
        setState(() {
          _placeSuggestions = [];
        });
      }
    } catch (_) {
      setState(() {
        _placeSuggestions = [];
      });
    }
  }

  Future<void> _determinePositionAndSetLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location services are disabled.')),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are denied.')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permissions are permanently denied.'),
        ),
      );
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    LatLng currentLocation = LatLng(position.latitude, position.longitude);

    if (!_isInMalaysia(currentLocation)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your location is outside Malaysia.')),
      );
      return;
    }

    setState(() {
      _selectedLocation = currentLocation;
    });

    _mapController.move(currentLocation, 13.0);
    await _updateLocationName(currentLocation);
  }

  Future<void> _selectPlaceSuggestion(dynamic suggestion) async {
    FocusScope.of(context).unfocus();

    final geometry = suggestion['geometry'];
    if (geometry == null || geometry['lat'] == null || geometry['lng'] == null)
      return;

    final lat = geometry['lat'];
    final lon = geometry['lng'];
    LatLng newLocation = LatLng(lat, lon);

    if (!_isInMalaysia(newLocation)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Only locations in Malaysia are allowed")),
      );
      return;
    }

    setState(() {
      _selectedLocation = newLocation;
      _searchController.text = suggestion['formatted'] ?? '';
      _placeSuggestions = [];
    });

    _mapController.move(newLocation, 13.0);
    await _updateLocationName(newLocation);
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
        title: const Text('Pick a Location'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60.0),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by place name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed:
                      () => _fetchPlaceSuggestions(_searchController.text),
                ),
              ),
              onChanged: _fetchPlaceSuggestions,
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedLocation,
              initialZoom: 13.0,
              onTap: (tapPosition, latlng) {
                if (!_isInMalaysia(latlng)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Only locations in Malaysia are allowed"),
                    ),
                  );
                  return;
                }

                setState(() {
                  _selectedLocation = latlng;
                  _placeSuggestions = [];
                  _searchController.clear();
                });
                _updateLocationName(latlng);
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                subdomains: const ['a', 'b', 'c'],
              ),
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: [
                      LatLng(0.8, 99.6),
                      LatLng(0.8, 119.3),
                      LatLng(7.5, 119.3),
                      LatLng(7.5, 99.6),
                    ],
                    color: Colors.blue.withOpacity(0.2),
                    borderStrokeWidth: 2,
                    borderColor: Colors.blue,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    width: 80.0,
                    height: 80.0,
                    point: _selectedLocation,
                    child: const Icon(
                      Icons.location_pin,
                      color: Colors.red,
                      size: 40,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Location name display
          Positioned(
            top: 150,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(8.0),
              color: Colors.white70,
              child:
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Text(
                        _locationName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
            ),
          ),

          // Suggestion dropdown
          if (_placeSuggestions.isNotEmpty)
            Positioned(
              top: 10,
              left: 16,
              right: 16,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.3,
                ),
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _placeSuggestions.length,
                    itemBuilder: (context, index) {
                      final suggestion = _placeSuggestions[index];
                      final formatted =
                          suggestion['formatted'] ?? 'Unnamed Place';

                      return ListTile(
                        title: Text(
                          formatted,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _selectPlaceSuggestion(suggestion),
                      );
                    },
                  ),
                ),
              ),
            ),

          // Confirm button
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: ElevatedButton(
              onPressed: () {
                if (!_isInMalaysia(_selectedLocation)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Please select a location in Malaysia"),
                    ),
                  );
                  return;
                }

                Navigator.pop(context, {
                  'lat': _selectedLocation.latitude,
                  'lng': _selectedLocation.longitude,
                  'name': _locationName,
                });
              },
              child: const Text('Confirm Location'),
            ),
          ),
        ],
      ),
    );
  }
}
