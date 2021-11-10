import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:m3u8_downloader/common/http.dart';
import 'package:m3u8_downloader/common/logger.dart';
import 'package:m3u8_downloader/m3u8/entity.dart';
import 'package:m3u8_downloader/m3u8/parser.dart';
import 'package:encrypt/encrypt.dart' as e;
import 'package:m3u8_downloader/page/home.dart';

final _logger = Logger('m3u8.downloader');

final httpRegExp = RegExp('https?://');

class M3U8Downloader with ChangeNotifier {
  DownloaderTaskConfig config;
  DateTime createTime;
  late M3U8 m3u8;


  List<M3U8Segment> successSegments = [];
  Map<M3U8Segment, int> retrySegments = {};
  List<M3U8Segment> failedSegments = [];

  int _progress = 0;
  int _total = -1;
  String _status = "Preparing";

  int get progress => _progress;

  set progress(int value) {
    _progress = value;
    notifyListeners();
  }

  int get total => _total;

  set total(int value) {
    _total = value;
    notifyListeners();
  }

  String get status => _status;

  set status(String value) {
    _status = value;
    notifyListeners();
  }

  var downloadSegmentIndex = 0;

  M3U8Downloader(this.config): createTime = DateTime.now();

  Future<void> init() async {
    status = 'Preparing';
    if (!config.sourceUrl.startsWith(httpRegExp) ||
        !config.sourceUrl.endsWith('.m3u8')) {
      status = 'Failure';
      _logger.severe('invalid m3u8 url: ${config.sourceUrl}');
      throw M3U8Exception('invalid url');
    }
    m3u8 = await _buildM3U8(config.sourceUrl);
    if (!_checkM3U8(m3u8)) {
      status = 'Failure';
      _logger.severe('invalid m3u8 url: ${config.sourceUrl}');
      throw M3U8Exception('invalid m3u8');
    }
    total = m3u8.segments.length;
  }

  Future<void> download() async {
    status = 'Downloading';
    var dir = Directory('${config.dictionary}/${config.taskName}');
    if (!(await dir.exists())) {
      await dir.create();
    }

    var completers = <Completer>[];
    var sendPortMap = <ReceivePort, SendPort>{};
    var isolateMap = <ReceivePort, Isolate>{};
    for (var i = 0; i < config.concurrency; i++) {
      var completer = Completer();
      completers.add(completer);
      var receivePort = ReceivePort();
      var isolate = await Isolate.spawn(
          _isolateDownload1, M3U8DownloadTask1(m3u8, config, receivePort.sendPort),
          debugName: 'downloader-isolate-$i');
      isolateMap[receivePort] = isolate;
      receivePort.listen((message) {
        if (message is SendPort) {
          sendPortMap[receivePort] = message;
        }
        if (downloadSegmentIndex >= m3u8.segments.length) {
          receivePort.close();
          isolateMap[receivePort]!.kill();
          completer.complete();
        }
        sendPortMap[receivePort]!.send(downloadSegmentIndex++);
        progress += 1;
      });
    }

    _logger.info('waiting download finish');
    await Future.wait(completers.map((c) => c.future).toList());
  }

  Future<void> merge() async {
    status = 'Merging';
    var file = File('${config.dictionary}/${config.taskName}/main.ts');
    for (var segment in m3u8.segments) {
      _logger.info('merging ${segment.uri}');
      var ts = File('${config.dictionary}/${config.taskName}/${segment.uri}');
      if (await ts.exists()) {
        await file.writeAsBytes(await ts.readAsBytes(), mode: FileMode.append);
      } else {
        throw M3U8Exception('no such ts segment');
      }
    }
  }

  Future<void> convert() async {
    status = 'Converting';
    FFmpegKit.executeAsync(
        '-i ${config.dictionary}/${config.taskName}/main.ts -c:v copy -c:a copy ${config.dictionary}/${config.taskName}/main.mp4',
        (session) async {
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        _logger.info('Success');
      } else if (ReturnCode.isCancel(returnCode)) {
        _logger.info('Cancel');
      } else {
        _logger.info('Error');
      }
    });
  }

  Future<void> clean() async {
    status = 'Cleaning';
    for (var segment in m3u8.segments) {
      var ts = File('${config.dictionary}/${config.taskName}/${segment.uri}');
      if (await ts.exists()) {
        await ts.delete();
      } else {
        _logger.severe('not exist ts, file: ${ts.path}');
      }
    }
  }

  Future<void> execute() async {
    await init();
    await download();
    await merge();
    await convert();
    if (config.cleanTsFiles) {
      await clean();
    }
  }

  static Future<void> _isolateDownload1(M3U8DownloadTask1 task) async {
    initLoggerConfig();
    var m3u8Encrypt = task.m3u8.key == null
        ? null
        : await _buildEncrypt(task.m3u8.key!, task.config);
    var receivePort = ReceivePort();
    task.sendPort.send(receivePort.sendPort);
    receivePort.listen((message) async {
      if (message is int) {
        await _download(task.m3u8.segments[message], m3u8Encrypt, task.config);
        task.sendPort.send(true);
      } else {
        throw M3U8Exception('unknown message');
      }
    });
  }

  static Future<void> _download(M3U8Segment segment, M3U8Encrypt? m3u8Encrypt, DownloaderTaskConfig config) async {
    var tsUri = segment.uri!.startsWith(httpRegExp)
        ? segment.uri!
        : _parseUrl(config.sourceUrl) + segment.uri!;
    var tsFile = File('${config.dictionary}/${config.taskName}/${Uri.parse(tsUri).pathSegments.last}');
    if (await tsFile.exists()) {
      _logger.info('skip ${segment.uri}');
      return;
    }
    _logger.info('downloading ${segment.uri}');
    var data = await decrypt(await getBytes(tsUri), m3u8Encrypt);
    await tsFile.writeAsBytes(data);
  }

  static Future<Uint8List> decrypt(
      Uint8List data, M3U8Encrypt? m3u8Encrypt) async {
    if (m3u8Encrypt == null) {
      return data;
    }
    var decryptBytes = m3u8Encrypt.encrypter.decryptBytes(e.Encrypted(data),
        iv: m3u8Encrypt.iv == null ? null : e.IV(m3u8Encrypt.iv!));
    return Uint8List.fromList(decryptBytes);
  }

  static Future<M3U8> _buildM3U8(String url) async {
    var body = await get(url);
    return parse(body);
  }

  static Future<M3U8Encrypt> _buildEncrypt(M3U8Key keySegment, DownloaderTaskConfig config) async {
    if (keySegment.method == 'AES-128') {
      var key = await getBytes(keySegment.url!.startsWith(httpRegExp)
          ? keySegment.url!
          : _parseUrl(config.sourceUrl) + keySegment.url!);
      var iv = keySegment.iv == null
          ? null
          : e.decodeHexString(keySegment.iv!.startsWith('0x')
              ? keySegment.iv!.substring(2)
              : keySegment.iv!);
      var encrypter = e.Encrypter(e.AES(e.Key(key), mode: e.AESMode.cbc));
      return M3U8Encrypt(keySegment.method!, key, iv, encrypter);
    } else {
      throw M3U8Error('nonsupport encrypt method');
    }
  }

  static String _parseUrl(String url) =>
      url.split(Uri.parse(url).pathSegments.last).first;

  static bool _checkM3U8(M3U8 m3u8) {
    if (!m3u8.m3u) {
      return false;
    }
    for (var segment in m3u8.segments) {
      if (segment.uri == null || segment.duration == null) {
        return false;
      }
    }
    return true;
  }
}

class M3U8DownloadTask1 {
  M3U8 m3u8;
  DownloaderTaskConfig config;
  SendPort sendPort;

  M3U8DownloadTask1(this.m3u8, this.config, this.sendPort);
}

class M3U8Encrypt {
  String method;
  Uint8List key;
  Uint8List? iv;
  e.Encrypter encrypter;

  M3U8Encrypt(this.method, this.key, this.iv, this.encrypter);
}

class M3U8Error extends Error {
  final String message;

  M3U8Error(this.message);
}

class M3U8Exception implements Exception {
  String message;

  M3U8Exception(this.message);
}
