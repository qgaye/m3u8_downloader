import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'exceptions.dart';

final _logger = Logger('common.http');

Future<String> get(String url) async {
  return (await _get(url)).body;
}

Future<Uint8List> getBytes(String url) async {
  return (await _get(url)).bodyBytes;
}

Future<http.Response> _get(String url) async {
  var resp = await http.get(Uri.parse(url));
  if (resp.statusCode != 200) {
    _logger.severe('get failed, url: $url, statusCode: ${resp.statusCode}, body: ${resp.body}');
    throw NetworkException('not OK');
  }
  return resp;
}