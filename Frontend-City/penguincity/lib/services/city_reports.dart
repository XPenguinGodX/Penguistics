import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:penguincity/config.dart';

const cityMapStatuses = ['CONFIRMED', 'ACTIVE', 'COMPLETED'];

class CityReport {
  const CityReport(
    this.id,
    this.title,
    this.status,
    this.latitude,
    this.longitude, {
    this.description = '',
    this.confidence,
    this.createdAt,
    this.locationSource = 'ONSITE',
  });
  final String id, title, status;
  final double latitude, longitude;
  final String description, locationSource;
  final double? confidence;
  final DateTime? createdAt;

  static CityReport? tryParse(Object? value, {bool allowDismissed = false}) {
    if (value is! Map<String, dynamic>) return null;
    final id = value['id'];
    final lat = value['lat'];
    final lon = value['long'];
    final status = value['status'];
    if (id is! String ||
        id.isEmpty ||
        lat is! num ||
        lon is! num ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lon < -180 ||
        lon > 180 ||
        !(cityMapStatuses.contains(status) ||
            (allowDismissed && status == 'DISMISSED'))) {
      return null;
    }
    return CityReport(
      id,
      value['title'] is String ? value['title'] as String : '',
      status as String,
      lat.toDouble(),
      lon.toDouble(),
      description: value['description'] is String
          ? value['description'] as String
          : '',
      confidence: value['confidence'] is num
          ? (value['confidence'] as num).toDouble()
          : null,
      createdAt: value['created_at'] is String
          ? DateTime.tryParse(value['created_at'] as String)
          : null,
      locationSource: value['location_source'] == 'REMOTE'
          ? 'REMOTE'
          : 'ONSITE',
    );
  }
}

class CityReports {
  const CityReports(this.city, this.state, this.reports);
  final String city, state;
  final List<CityReport> reports;
}

class CityReportsException implements Exception {
  const CityReportsException(this.message);
  final String message;
}

class CityReportService {
  CityReportService({this.baseUrl = penApi, http.Client? client})
    : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;

  Future<CityReports> load(String token) async {
    if (baseUrl.trim().isEmpty) {
      throw const CityReportsException(
        'PEN_API is not set. Start with --dart-define=PEN_API=<ApiBaseUrl>.',
      );
    }
    final response = await _client
        .get(
          Uri.parse('${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/city/reports'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw CityReportsException(switch (response.statusCode) {
        401 => 'Your session has expired. Sign out and log in again.',
        403 => 'Ask your admin to check your staff access and city assignment.',
        _ => 'City reports are temporarily unavailable. Refresh to try again.',
      });
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> ||
        body['city'] is! String ||
        body['state'] is! String ||
        body['reports'] is! List) {
      throw const FormatException('Invalid city reports response.');
    }
    return CityReports(
      body['city'] as String,
      body['state'] as String,
      (body['reports'] as List)
          .map((value) => CityReport.tryParse(value))
          .nonNulls
          .toList(),
    );
  }

  Future<CityReport> changeStatus(
    String id,
    String status,
    String token,
  ) async {
    final response = await _client
        .put(
          Uri.parse(
            '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/city/reports/${Uri.encodeComponent(id)}/status',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'status': status}),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw CityReportsException(switch (response.statusCode) {
        401 => 'Your session has expired. Sign out and log in again.',
        403 => 'This account cannot change city reports.',
        404 => 'This report is no longer available. Refresh the map.',
        409 => 'This report has changed. Refresh the map before trying again.',
        _ =>
          'Could not update the report. Refresh to check its current status before retrying.',
      });
    }
    final body = jsonDecode(response.body);
    final report = body is Map<String, dynamic>
        ? CityReport.tryParse(body['report'], allowDismissed: true)
        : null;
    if (report == null || report.id != id || report.status != status) {
      throw const FormatException('Invalid status response. Refresh the map.');
    }
    return report;
  }

  void close() => _client.close();
}
