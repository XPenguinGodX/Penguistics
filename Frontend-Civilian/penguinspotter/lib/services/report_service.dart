import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:penguin/services/api_client.dart';

/// One of the signed-in user's reports, as listed by GET /reports.
class ReportSummary {
  const ReportSummary({
    required this.id,
    required this.status,
    required this.description,
    required this.latitude,
    required this.longitude,
    this.confidence,
    this.createdAt,
  });

  /// Returns null for an entry missing its id or coordinates, so one bad row can't hide the rest.
  static ReportSummary? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final lat = json['lat'];
    final long = json['long'];
    if (id is! String || lat is! num || long is! num) return null;
    final confidence = json['confidence'];
    final createdAt = json['created_at'];
    return ReportSummary(
      id: id,
      status: json['status'] is String ? json['status'] as String : 'PENDING',
      description: json['description'] is String
          ? json['description'] as String
          : '',
      latitude: lat.toDouble(),
      longitude: long.toDouble(),
      confidence: confidence is num ? confidence.toDouble() : null,
      createdAt: createdAt is String ? DateTime.tryParse(createdAt) : null,
    );
  }

  final String id;
  final String status;
  final String description;
  final double latitude;
  final double longitude;
  final double? confidence; // 0 to 1; null until validation finishes
  final DateTime? createdAt;
}

class ReportService {
  ReportService({
    this.baseUrl = const String.fromEnvironment('PEN_API'),
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  /// Saves a PENDING report and starts validation. Returns the report id.
  Future<String> create({
    required String imageKey,
    required double latitude,
    required double longitude,
    required String description,
    required String accessToken,
  }) async {
    final response = await _client
        .post(
          _endpoint('/reports'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'imagepath': imageKey,
            'lat': latitude,
            'long': longitude,
            'description': description,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 202) {
      throw ApiException(
        apiErrorMessage(response, 'Could not submit the report'),
      );
    }
    final id = decodeJsonObject(response)['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Invalid report response.');
    }
    return id;
  }

  /// Current status of one of the signed-in user's reports.
  Future<String> status(String id, {required String accessToken}) async {
    final response = await _client
        .get(
          _endpoint('/reports/${Uri.encodeComponent(id)}'),
          headers: {'Authorization': 'Bearer $accessToken'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw ApiException(apiErrorMessage(response, 'Could not check the report'));
    }
    final status = decodeJsonObject(response)['status'];
    if (status is! String) {
      throw const FormatException('Invalid report response.');
    }
    return status;
  }

  /// Polls until the report leaves PENDING or [timeout] passes; returns the last status seen.
  Future<String> waitForResult(
    String id, {
    required String accessToken,
    Duration timeout = const Duration(seconds: 90),
    Duration interval = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final current = await status(id, accessToken: accessToken);
      if (current != 'PENDING' || DateTime.now().isAfter(deadline)) {
        return current;
      }
      await Future.delayed(interval);
    }
  }

  /// All of the signed-in user's reports, newest first.
  Future<List<ReportSummary>> listMine({required String accessToken}) async {
    final response = await _client
        .get(
          _endpoint('/reports'),
          headers: {'Authorization': 'Bearer $accessToken'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw ApiException(
        apiErrorMessage(response, 'Could not load your reports'),
      );
    }
    final reports = decodeJsonObject(response)['reports'];
    if (reports is! List) {
      throw const FormatException('Unexpected response from the server.');
    }
    return reports.map(ReportSummary.tryParse).nonNulls.toList();
  }

  Uri _endpoint(String path) => apiEndpoint(baseUrl, path);

  void close() => _client.close();
}
