import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:penguin/services/api_client.dart';

/// The signed-in user's profile, as returned by GET /profile.
class Profile {
  const Profile({
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.state,
    required this.city,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    String text(String key) => json[key] is String ? json[key] as String : '';
    return Profile(
      username: text('username'),
      firstName: text('firstname'),
      lastName: text('lastname'),
      state: text('state'),
      city: text('city'),
    );
  }

  final String username;
  final String firstName;
  final String lastName;
  final String state;
  final String city;
}

class ProfileService {
  ProfileService({
    this.baseUrl = const String.fromEnvironment('PEN_API'),
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<Profile> fetch({required String accessToken}) async {
    final response = await _client
        .get(
          apiEndpoint(baseUrl, '/profile'),
          headers: {'Authorization': 'Bearer $accessToken'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw ApiException(
        apiErrorMessage(response, 'Could not load your profile'),
      );
    }
    return Profile.fromJson(decodeJsonObject(response));
  }

  /// Saves a new state and city; the server ignores every other field.
  Future<Profile> updateLocation({
    required String state,
    required String city,
    required String accessToken,
  }) async {
    final response = await _client
        .put(
          apiEndpoint(baseUrl, '/profile'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'state': state, 'city': city}),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw ApiException(
        apiErrorMessage(response, 'Could not save your profile'),
      );
    }
    return Profile.fromJson(decodeJsonObject(response));
  }

  void close() => _client.close();
}
