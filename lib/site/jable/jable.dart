import 'package:logging/logging.dart';
import 'package:m3u8_downloader/common/errors.dart';
import 'package:m3u8_downloader/common/extensions.dart';
import 'package:m3u8_downloader/support.dart';

import '../site.dart';

final _logger = Logger('site.jable');

class Jable extends Site {

  Jable(String url) : super(url);

  @override
  Future<String> extract(VideoType videoType) async {
    var _content = await content;
    switch (videoType) {
      case VideoType.m3u8:
        return extractM3U8(_content);
      default:
        _logger.severe('not support ${videoType.name}');
        throw NotSupportTypeError('VideoType');
    }
  }

  String extractM3U8(String content) {
    var regExp = RegExp('(https|http)://.+\.m3u8');
    var match = regExp.firstMatch(content);
    if (match == null) {
      throw RegExpNotMatchError();
    }
    return match.group(0)!;
  }

}