import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:m3u8_downloader/common/http.dart';
import 'package:m3u8_downloader/common/logger.dart';
import 'package:m3u8_downloader/m3u8/downloader.dart';
import 'package:m3u8_downloader/site/jable/jable.dart';
import 'package:m3u8_downloader/support.dart';

void main() async {
  var logger = Logger('main-test');
  initLoggerConfig();

  var url = 'https://jable.tv/videos/ssis-219/';
  var m3u8_url =
      'https://ac-fors-caid.mushroomtrack.com/hls/ckr310xvtfSag1XUpSA9dw/1635620477/19000/19477/19477.m3u8';

  test('test', () async {
    var site = Jable(url);
    var extract = await site.extract(VideoType.m3u8);
    logger.info(extract);
    var downloader = await M3U8Downloader.create(extract,
        path: '/Users/qgaye/Downloads',
        name: Uri.parse(url)
            .pathSegments
            .lastWhere((element) => element.isNotEmpty));
    await downloader.download();
    await downloader.merge();
    // await downloader.convert();
    await downloader.clean();
  });

  test('test222', () {
    var indexes = List<List<int>>.generate(5, (i) {
      return [for (var j = i; j < 100; j += 5) j];
    });
    print(indexes.toString());
    print(
        Uri.parse(url).pathSegments.lastWhere((element) => element.isNotEmpty));
  });

  // test('test2', () async {
  //   FFmpegKit.executeAsync(
  //       '-i /Users/qgaye/Downloads/194770.ts -c:v copy -c:a copy /Users/qgaye/Downloads/output.mp4',
  //           (session) async {
  //         final returnCode = await session.getReturnCode();
  //         if (ReturnCode.isSuccess(returnCode)) {
  //           logger.info('Success');
  //         } else if (ReturnCode.isCancel(returnCode)) {
  //           logger.info('Cancel');
  //         } else {
  //           logger.info('Error');
  //         }
  //       });
  // });
}
