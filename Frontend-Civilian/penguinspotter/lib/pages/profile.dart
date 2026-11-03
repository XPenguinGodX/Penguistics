import 'package:flutter/material.dart';
import 'package:penguin/services/auth_session.dart';
import 'package:penguin/services/profile_service.dart';
import 'package:penguin/theme/penguin_theme.dart';
import 'package:penguin/widgets/penguin_widgets.dart';

// Mirrors the backend's rule: a letter (any alphabet) first, then letters and space . ' -
final _placePattern = RegExp(r"^\p{L}[\p{L} .'\-]*$", unicode: true);
const _maxPlaceLength = 100;

/// Validator for the state and city fields; null means the value is fine.
String? placeError(String? value, String label) {
  final place = (value ?? '').trim().split(RegExp(r'\s+')).join(' ');
  if (place.isEmpty) return '$label is required';
  if (place.length > _maxPlaceLength) {
    return '$label must be $_maxPlaceLength characters or fewer';
  }
  if (!_placePattern.hasMatch(place)) {
    return "Use letters, spaces, and . ' - only";
  }
  return null;
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ProfileService _profiles = ProfileService();
  final _formKey = GlobalKey<FormState>();
  final TextEditingController city = TextEditingController();
  final TextEditingController state = TextEditingController();

  Profile? _profile;
  String? _loadError;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    city.dispose();
    state.dispose();
    _profiles.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final profile = await _profiles.fetch(accessToken: await accessToken());
      if (!mounted) return;
      setState(() {
        _profile = profile;
        city.text = profile.city;
        state.text = profile.state;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = '$error');
    }
  }

  Future<void> _save() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await _profiles.updateLocation(
        state: state.text.trim(),
        city: city.text.trim(),
        accessToken: await accessToken(),
      );
      if (!mounted) return;
      showPenguinSnack(context, 'Profile saved.', tone: PenguinTone.success);
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        showPenguinSnack(context, '$error', tone: PenguinTone.warning);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
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
              child: _buildBody(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatusBanner(message: _loadError!, tone: PenguinTone.warning),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
          ),
        ],
      );
    }

    final profile = _profile;
    if (profile == null) {
      return const StatusBanner(message: 'Loading your profile...', busy: true);
    }

    final text = Theme.of(context).textTheme;
    final fullName = '${profile.firstName} ${profile.lastName}'.trim();
    final displayName = fullName.isNotEmpty ? fullName : profile.username;
    // `characters` keeps emoji and accented letters whole, unlike displayName[0]
    final initial = displayName.isEmpty
        ? '?'
        : displayName.characters.first.toUpperCase();
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: PenguinColors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: PenguinColors.blue,
                    foregroundColor: PenguinColors.white,
                    child: Text(initial, style: text.titleLarge),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: text.titleLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '@${profile.username}',
                          style: text.bodyMedium?.copyWith(
                            color: PenguinColors.muted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'WHERE YOU REPORT',
                style: text.labelSmall?.copyWith(color: PenguinColors.muted),
              ),
              const SizedBox(height: 4),
              Text(
                'New reports are filed under this city.',
                style: text.bodyMedium?.copyWith(color: PenguinColors.muted),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: city,
                textInputAction: TextInputAction.next,
                maxLength: _maxPlaceLength,
                validator: (value) => placeError(value, 'City'),
                decoration: const InputDecoration(
                  labelText: 'City / Town',
                  prefixIcon: Icon(Icons.location_city_rounded),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: state,
                textInputAction: TextInputAction.done,
                maxLength: _maxPlaceLength,
                validator: (value) => placeError(value, 'State'),
                onFieldSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                  labelText: 'State',
                  prefixIcon: Icon(Icons.map_rounded),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
