import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:m3u8_downloader/common/http.dart';
import 'package:m3u8_downloader/common/logger.dart';
import 'package:m3u8_downloader/m3u8/downloader.dart';
import 'package:m3u8_downloader/page/home.dart';
import 'package:m3u8_downloader/site/jable/jable.dart';
import 'package:m3u8_downloader/support.dart';

void main() async {
  var logger = Logger('main-test');
  initLoggerConfig();

  // https://jable.tv/videos/fsdss-298/
  // https://jable.tv/videos/ssis-218/
  var url = 'https://jable.tv/videos/ssis-213/';
  var m3u8_url =
      'https://ac-fors-caid.mushroomtrack.com/hls/ckr310xvtfSag1XUpSA9dw/1635620477/19000/19477/19477.m3u8';

  test('test', () async {
    var site = Jable(url);
    var extract = await site.extract(VideoType.m3u8);
    logger.info(extract);
    var config = DownloaderConfig(
        Uri.parse(url).pathSegments.lastWhere((element) => element.isNotEmpty),
        extract,
        '/Users/qgaye/Downloads',
        5,
        true);
    var downloader = M3U8Downloader(config);
    await downloader.parse();
    await downloader.download();
    await downloader.merge();
    // await downloader.convert();
    await downloader.clean();
  });

}
