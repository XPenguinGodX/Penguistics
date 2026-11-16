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
    this.longitude,
  );
  final String id, title, status;
  final double latitude, longitude;

  static CityReport? tryParse(Object? value) {
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
        !cityMapStatuses.contains(status)) {
      return null;
    }
    return CityReport(
      id,
      value['title'] is String ? value['title'] as String : '',
      status as String,
      lat.toDouble(),
      lon.toDouble(),
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
      (body['reports'] as List).map(CityReport.tryParse).nonNulls.toList(),
    );
  }

  void close() => _client.close();
}
