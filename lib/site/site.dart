import 'package:logging/logging.dart';
import 'package:m3u8_downloader/common/http.dart';
import 'package:m3u8_downloader/support.dart';

final _logger = Logger('site');

abstract class Site {

  String url;
  final Future<String> _futureContent;

  Site(this.url) : _futureContent = fetch(url);

  Future<String> get content => _futureContent;

  static Future<String> fetch(String url) async {
    return get(url);
  }

  Future<String?> extract(VideoType videoType);
}