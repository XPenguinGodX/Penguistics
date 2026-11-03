import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:penguin/pages/profile.dart';
import 'package:penguin/services/api_client.dart';
import 'package:penguin/services/profile_service.dart';

void main() {
  const profileJson = {
    'username': 'alice',
    'firstname': 'Alice',
    'lastname': 'Liddell',
    'state': 'Utah',
    'city': 'Provo',
  };

  test('fetch sends the token and parses the profile', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.example.com/dev/profile');
      expect(request.headers['Authorization'], 'Bearer test-token');
      return http.Response(jsonEncode(profileJson), 200);
    });
    final service = ProfileService(
      baseUrl: 'https://api.example.com/dev/',
      client: client,
    );

    final profile = await service.fetch(accessToken: 'test-token');

    expect(profile.username, 'alice');
    expect(profile.firstName, 'Alice');
    expect(profile.city, 'Provo');
  });

  test('updateLocation sends only state and city as JSON', () async {
    final client = MockClient((request) async {
      expect(request.method, 'PUT');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(request.body), {'state': 'Idaho', 'city': 'Boise'});
      return http.Response(
        jsonEncode({...profileJson, 'state': 'Idaho', 'city': 'Boise'}),
        200,
      );
    });
    final service = ProfileService(
      baseUrl: 'https://api.example.com',
      client: client,
    );

    final profile = await service.updateLocation(
      state: 'Idaho',
      city: 'Boise',
      accessToken: 'test-token',
    );

    expect(profile.state, 'Idaho');
    expect(profile.city, 'Boise');
  });

  test('server messages and expired sessions become readable errors', () async {
    final rejected = ProfileService(
      baseUrl: 'https://api.example.com',
      client: MockClient(
        (_) async => http.Response(jsonEncode({'message': 'Bad city.'}), 400),
      ),
    );
    final expired = ProfileService(
      baseUrl: 'https://api.example.com',
      client: MockClient((_) async => http.Response('', 401)),
    );

    await expectLater(
      rejected.updateLocation(state: 'Utah', city: 'x', accessToken: 't'),
      throwsA(
        isA<ApiException>().having((e) => '$e', 'message', 'Bad city.'),
      ),
    );
    await expectLater(
      expired.fetch(accessToken: 't'),
      throwsA(
        isA<ApiException>().having(
          (e) => '$e',
          'message',
          contains('log in again'),
        ),
      ),
    );
  });

  test('a missing PEN_API makes no request', () async {
    var requests = 0;
    final service = ProfileService(
      baseUrl: '',
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      service.fetch(accessToken: 't'),
      throwsA(isA<ApiException>()),
    );
    expect(requests, 0);
  });

  group('placeError', () {
    test('accepts real place names', () {
      for (final place in ['Provo', "Coeur d'Alene", 'São Paulo', 'St. Louis']) {
        expect(placeError(place, 'City'), isNull, reason: place);
      }
    });

    test('rejects blank, too long, and non-letter values', () {
      expect(placeError('   ', 'City'), 'City is required');
      expect(placeError('x' * 101, 'City'), contains('100 characters'));
      expect(placeError('Provo 84601', 'City'), isNotNull);
      expect(placeError('<script>', 'City'), isNotNull);
      expect(placeError('-Utah', 'State'), isNotNull);
    });
  });
}
