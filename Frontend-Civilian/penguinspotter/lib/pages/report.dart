import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:penguin/pages/location_picker.dart';
import 'package:penguin/services/auth_session.dart';
import 'package:penguin/services/image_upload_service.dart';
import 'package:penguin/services/report_service.dart';
import 'package:penguin/theme/penguin_theme.dart';
import 'package:penguin/widgets/penguin_widgets.dart';

class Report extends StatefulWidget {
  const Report({super.key});

  @override
  State<Report> createState() => _ReportState();
}

class _ReportState extends State<Report> {
  final TextEditingController title = TextEditingController();
  final TextEditingController description = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final ImageUploadService _imageUploader = ImageUploadService();
  final ReportService _reports = ReportService();
  String? _uploadedImageKey;
  String? _reportStatus;
  // Set after a rejection, so the next submit retries that report instead of adding another
  String? _rejectedReportId;

  XFile? _selectedPhoto;
  bool _isPickingPhoto = false;
  // Where the phone is (always needed, even for a remote report)
  double? _latitude;
  double? _longitude;
  // Set when the user placed the pin on the map; null means "use my GPS"
  LatLng? _remoteLocation;
  bool _isSubmitting = false;

  bool get _isRemote => _remoteLocation != null;

  // On a phone, an on-site report takes a fresh photo. Someone reporting
  // from elsewhere isn't at the damage, so they pick a photo they took earlier.
  bool get _usesCamera =>
      !kIsWeb &&
      !_isRemote &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _fetchLocation();
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    _imageUploader.close();
    _reports.close();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
        });
      }
    } catch (_) {}
  }

  /// Opens the map picker. Keeps the current choice if the user backs out.
  Future<void> _pickRemoteLocation() async {
    if (_latitude == null || _longitude == null) {
      showPenguinSnack(
        context,
        'Waiting for your GPS location. Remote reports must be near you.',
      );
      _fetchLocation();
      return;
    }
    final picked = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPicker(
          device: LatLng(_latitude!, _longitude!),
          initial: _remoteLocation,
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _remoteLocation = picked);
    }
  }

  Future<void> _attachPhoto() async {
    final ImageSource source = _usesCamera
        ? ImageSource.camera
        : ImageSource.gallery;

    setState(() => _isPickingPhoto = true);
    try {
      final XFile? photo = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (photo != null && mounted) {
        setState(() {
          _selectedPhoto = photo;
          _uploadedImageKey = null;
          _reportStatus = null;
        });
      }
    } catch (e) {
      if (mounted) {
        showPenguinSnack(
          context,
          'Could not attach photo: $e',
          tone: PenguinTone.warning,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingPhoto = false);
      }
    }
  }

  Future<String> submitImage(String token) async {
    final photo = _selectedPhoto;
    if (photo == null) {
      throw Exception('Please attach a photo first.');
    }
    final bytes = await photo.readAsBytes();
    return _imageUploader.upload(bytes, accessToken: token);
  }

  Future<({String id, String status})> processReport(
    String imageKey,
    String token,
  ) async {
    final remote = _remoteLocation;
    final reportId = await _reports.create(
      imageKey: imageKey,
      // The report's pin: the spot picked on the map, or else the phone's GPS
      latitude: remote?.latitude ?? _latitude!,
      longitude: remote?.longitude ?? _longitude!,
      title: title.text.trim(),
      description: description.text.trim(),
      accessToken: token,
      replaces: _rejectedReportId,
      locationSource: remote == null ? 'ONSITE' : 'REMOTE',
      // The server checks the pin is within 12 km of where the phone really is
      deviceLatitude: remote == null ? null : _latitude,
      deviceLongitude: remote == null ? null : _longitude,
    );
    final status = await _reports.waitForResult(reportId, accessToken: token);
    return (id: reportId, status: status);
  }

  String _statusMessage(String status) {
    switch (status) {
      case 'CONFIRMED':
        return 'Report confirmed. Thank you!';
      case 'REJECTED':
        return 'We could not spot road damage in this photo. Take a new, clearer photo to try again.';
      default:
        return 'Still checking your photo. Your report is saved and will be reviewed shortly.';
    }
  }

  PenguinTone _statusTone(String status) => switch (status) {
    'CONFIRMED' => PenguinTone.success,
    'REJECTED' => PenguinTone.warning,
    _ => PenguinTone.info,
  };

  Future<void> submitReport() async {
    if (_isSubmitting || _isPickingPhoto || _reportStatus == 'CONFIRMED') {
      return;
    }
    if (title.text.trim().isEmpty || description.text.trim().isEmpty) {
      showPenguinSnack(
        context,
        'Please fill in all fields',
        tone: PenguinTone.warning,
      );
      return;
    }

    if (_selectedPhoto == null) {
      showPenguinSnack(
        context,
        'Please attach a photo of the road damage',
        tone: PenguinTone.warning,
      );
      return;
    }

    if (_latitude == null || _longitude == null) {
      showPenguinSnack(
        context,
        'Waiting for your GPS location. Try again shortly.',
      );
      _fetchLocation();
      return;
    }

    setState(() {
      _isSubmitting = true;
      _reportStatus = null;
    });

    try {
      final token = await accessToken();
      // Reuse an already-uploaded image if only the report step failed last time
      final key = _uploadedImageKey ?? await submitImage(token);
      if (!mounted) return;
      setState(() => _uploadedImageKey = key);

      final result = await processReport(key, token);
      if (!mounted) return;
      setState(() {
        _reportStatus = result.status;
        // Remember a rejected report so the next attempt replaces it, else forget it
        _rejectedReportId = result.status == 'REJECTED' ? result.id : null;
        // A rejected report keeps its image; a new attempt uploads a fresh one
        if (result.status == 'REJECTED') _uploadedImageKey = null;
      });
    } catch (error) {
      if (mounted) {
        showPenguinSnack(
          context,
          'Could not submit report: $error',
          tone: PenguinTone.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Camera wording and icons only when the photo will come from the camera
    final bool isMobile = _usesCamera;

    final text = Theme.of(context).textTheme;
    final bool hasLocation = _latitude != null && _longitude != null;
    final bool canEditPhoto = !_isPickingPhoto && !_isSubmitting;
    final remote = _remoteLocation;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Report'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: Container(height: 4, color: PenguinColors.yellow),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: PenguinColors.charcoal,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: PenguinColors.outline),
                    ),
                    child: Row(
                      children: [
                        const PenguinLogo(size: 52),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Spotted road damage?',
                                style: text.titleLarge?.copyWith(
                                  color: PenguinColors.yellow,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Snap a photo and our penguin will check it for potholes.',
                                style: text.bodyMedium?.copyWith(
                                  color: PenguinColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: title,
                    textInputAction: TextInputAction.next,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Issue title',
                      hintText: 'e.g. Pothole on Main St',
                      prefixIcon: Icon(Icons.title_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: description,
                    maxLines: 3,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'Describe the road damage...',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Where is the damage?', style: text.titleMedium),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.my_location_rounded),
                        label: Text("I'm here"),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.edit_location_alt_rounded),
                        label: Text('Somewhere else'),
                      ),
                    ],
                    selected: {_isRemote},
                    // Locked while submitting so the location can't change mid-upload
                    onSelectionChanged: _isSubmitting
                        ? null
                        : (selection) {
                            if (selection.first) {
                              _pickRemoteLocation();
                            } else {
                              setState(() => _remoteLocation = null);
                            }
                          },
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: (remote == null
                              ? PenguinColors.blue
                              : PenguinColors.orange)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          remote != null
                              ? Icons.edit_location_alt_rounded
                              : hasLocation
                              ? Icons.location_on_rounded
                              : Icons.location_searching_rounded,
                          color: remote == null
                              ? PenguinColors.blue
                              : PenguinColors.orange,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            remote != null
                                ? 'Pinned: ${remote.latitude.toStringAsFixed(5)}, ${remote.longitude.toStringAsFixed(5)}'
                                : hasLocation
                                ? '${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}'
                                : 'Fetching GPS coordinates...',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (remote != null)
                          TextButton(
                            onPressed: _isSubmitting
                                ? null
                                : _pickRemoteLocation,
                            child: const Text('Move pin'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_selectedPhoto == null)
                    Material(
                      color: PenguinColors.charcoal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(
                          color: PenguinColors.blue,
                          width: 2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: canEditPhoto ? _attachPhoto : null,
                        child: SizedBox(
                          height: 180,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 30,
                                backgroundColor: PenguinColors.yellow,
                                child: _isPickingPhoto
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: PenguinColors.black,
                                        ),
                                      )
                                    : Icon(
                                        isMobile
                                            ? Icons.camera_alt_rounded
                                            : Icons.add_photo_alternate_rounded,
                                        color: PenguinColors.black,
                                        size: 30,
                                      ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                isMobile
                                    ? 'Take a photo of the damage'
                                    : 'Attach a photo from your files',
                                style: text.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'JPEG, PNG, or WebP',
                                style: text.bodyMedium?.copyWith(
                                  color: PenguinColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else ...[
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: FutureBuilder<Uint8List>(
                            future: _selectedPhoto!.readAsBytes(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                      ConnectionState.done &&
                                  snapshot.hasData) {
                                return Image.memory(
                                  snapshot.data!,
                                  height: 240,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                );
                              }
                              return Container(
                                height: 240,
                                color: PenguinColors.charcoalHigh,
                                alignment: Alignment.center,
                                child: const CircularProgressIndicator(),
                              );
                            },
                          ),
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: IconButton.filled(
                            tooltip: 'Remove photo',
                            style: IconButton.styleFrom(
                              backgroundColor: PenguinColors.black.withValues(
                                alpha: 0.7,
                              ),
                              foregroundColor: PenguinColors.white,
                            ),
                            icon: const Icon(Icons.close_rounded),
                            onPressed: _isSubmitting
                                ? null
                                : () {
                                    setState(() {
                                      _selectedPhoto = null;
                                      _uploadedImageKey = null;
                                      _reportStatus = null;
                                    });
                                  },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: canEditPhoto ? _attachPhoto : null,
                      icon: Icon(
                        isMobile
                            ? Icons.camera_alt_rounded
                            : Icons.photo_library_rounded,
                      ),
                      label: Text(
                        _isPickingPhoto ? 'Opening...' : 'Change Photo',
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_isSubmitting)
                    const StatusBanner(
                      message: 'Uploading and checking your photo...',
                      busy: true,
                    ),
                  if (!_isSubmitting && _reportStatus != null)
                    StatusBanner(
                      message: _statusMessage(_reportStatus!),
                      tone: _statusTone(_reportStatus!),
                    ),
                  if (_isSubmitting || _reportStatus != null)
                    const SizedBox(height: 16),
                  ElevatedButton.icon(
                    // The same photo would be rejected again, so after a rejection
                    // this button asks for a new photo instead of resubmitting
                    onPressed:
                        _isSubmitting ||
                            _isPickingPhoto ||
                            _reportStatus == 'CONFIRMED' ||
                            _reportStatus == 'PENDING'
                        ? null
                        : _reportStatus == 'REJECTED'
                        ? _attachPhoto
                        : submitReport,
                    icon: Icon(switch (_reportStatus) {
                      'REJECTED' when isMobile => Icons.camera_alt_rounded,
                      'REJECTED' => Icons.photo_library_rounded,
                      _ => Icons.send_rounded,
                    }),
                    label: Text(switch (_reportStatus) {
                      'CONFIRMED' => 'Report Submitted',
                      'PENDING' => 'Report Saved',
                      'REJECTED' when isMobile => 'Take a New Photo',
                      'REJECTED' => 'Choose a New Photo',
                      _ => 'Submit Report',
                    }),
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
