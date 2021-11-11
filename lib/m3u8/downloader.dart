import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
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
import 'package:m3u8_downloader/m3u8/status.dart';
import 'package:m3u8_downloader/page/home.dart';

final _logger = Logger('m3u8.downloader');

final httpRegExp = RegExp('https?://');

class M3U8Downloader with ChangeNotifier {
  DownloaderConfig config;
  DateTime createTime;
  late M3U8 m3u8;

  int maxRetryCount = 3;

  int downloadSegmentIndex = 0;

  List<int> successSegmentIndexes = [];
  Map<int, int> retrySegmentIndexes = {};
  List<int> failedSegmentIndexes = [];

  int _progress = 0;
  int _total = -1;
  DownloaderStatus _status = DownloaderStatus.Init;
  bool isInterrupt = false;

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

  DownloaderStatus get status => _status;

  set status(DownloaderStatus value) {
    _status = value;
    notifyListeners();
  }

  M3U8Downloader(this.config) : createTime = DateTime.now();

  Future<void> parse() async {
    if (!config.sourceUrl.startsWith(httpRegExp) ||
        !config.sourceUrl.endsWith('.m3u8')) {
      throw M3U8ParesException('invalid url');
    }
    m3u8 = await _buildM3U8(config.sourceUrl);
    if (!_checkM3U8(m3u8)) {
      throw M3U8ParesException('invalid m3u8');
    }
    total = m3u8.segments.length;
  }

  Future<void> download() async {
    var dir = Directory('${config.directory}/${config.taskName}');
    if (!(await dir.exists())) {
      _logger.info('target directory not exists, create ${dir.path}');
      await dir.create();
    }

    var completers = <Completer>[];
    var sendPortMap = <ReceivePort, SendPort>{};
    var isolateMap = <ReceivePort, Isolate>{};

    for (var i = 0; i < config.concurrency; i++) {
      var random = Random();
      var completer = Completer();
      completers.add(completer);
      var receivePort = ReceivePort();
      var isolate = await Isolate.spawn(
          _isolateDownload, _DownloadParam(m3u8, config, receivePort.sendPort),
          debugName: 'downloader-isolate-$i');
      isolateMap[receivePort] = isolate;

      void _sendDownloadRep() {
        if (downloadSegmentIndex >= m3u8.segments.length &&
            retrySegmentIndexes.isEmpty) {
          receivePort.close();
          isolateMap[receivePort]!.kill();
          completer.complete();
        }
        if (retrySegmentIndexes.isNotEmpty && random.nextBool()) {
          var segmentIndex = retrySegmentIndexes.keys.first;
          var retryCount = retrySegmentIndexes.remove(segmentIndex)!;
          sendPortMap[receivePort]!
              .send(_DownloadReq(segmentIndex, retryCount++));
        } else {
          sendPortMap[receivePort]!
              .send(_DownloadReq(downloadSegmentIndex++, 0));
        }
      }

      receivePort.listen((resp) {
        if (isInterrupt) {
          isolateMap.forEach((receivePort, isolate) {
            receivePort.close();
            isolate.kill();
          });
          completers.forEach((completer) => completer.complete());
          // TODO
          throw M3U8InterruptException("interrupted");
        }
        if (resp is SendPort) {
          sendPortMap[receivePort] = resp;
          _sendDownloadRep();
        } else if (resp is _DownloadResp) {
          if (resp.isSuccess) {
            successSegmentIndexes.add(resp.segmentIndex);
            progress += 1;
          } else if (resp.retryCount <= maxRetryCount) {
            retrySegmentIndexes[resp.segmentIndex] = resp.retryCount;
          } else {
            failedSegmentIndexes.add(resp.segmentIndex);
          }
          _sendDownloadRep();
        } else {
          _logger.severe('download: unknown message');
        }
      });
    }
    _logger.info('waiting download finish');
    await Future.wait(completers.map((c) => c.future).toList());
  }

  Future<void> merge() async {
    var file = File('${config.directory}/${config.taskName}/main.ts');
    for (var segment in m3u8.segments) {
      _logger.info('merging ${segment.uri}');
      var ts = File('${config.directory}/${config.taskName}/${segment.uri}');
      if (await ts.exists()) {
        await file.writeAsBytes(await ts.readAsBytes(), mode: FileMode.append);
      } else {
        _logger.severe('merge: cannot find ts segment: ${segment.uri}');
        throw M3U8MergeException('no such ts segment');
      }
    }
  }

  Future<void> convert() async {
    FFmpegKit.executeAsync(
        '-i ${config.directory}/${config.taskName}/main.ts -c:v copy -c:a copy ${config.directory}/${config.taskName}/main.mp4',
        (session) async {
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        _logger.info('Success');
      } else if (ReturnCode.isCancel(returnCode)) {
        _logger.info('Cancel');
      } else {
        throw M3U8ConvertException('convert error');
      }
    });
  }

  Future<void> clean() async {
    for (var segment in m3u8.segments) {
      var ts = File('${config.directory}/${config.taskName}/${segment.uri}');
      if (await ts.exists()) {
        await ts.delete();
      } else {
        _logger.severe('clean: not exist ts, file: ${ts.path}');
      }
    }
  }

  Future<void> interrupt() async {
    isInterrupt = true;
  }

  Future<void> execute() async {
    _logger.info('execute: m3u8 task: $config');
    try {
      status = DownloaderStatus.Parsing;
      await parse();
      status = DownloaderStatus.Downloading;
      await download();
      status = DownloaderStatus.Merging;
      await merge();
      status = DownloaderStatus.Converting;
      await convert();
      if (config.cleanTsFiles) {
        status = DownloaderStatus.Cleaning;
        await clean();
      }
      status = DownloaderStatus.Success;
    } on M3U8ParesException catch (e) {
      status = DownloaderStatus.ParseFail;
    } on M3U8DownloadException catch (e) {
      status = DownloaderStatus.DownloadFail;
    } on M3U8MergeException catch (e) {
      status = DownloaderStatus.MergeFail;
    } on M3U8ConvertException catch (e) {
      status = DownloaderStatus.ConvertFail;
    } on M3U8CleanException catch (e) {
      status = DownloaderStatus.CleanFail;
    } on M3U8InterruptException catch (e) {
      status = DownloaderStatus.Interrupted;
    } catch (e) {
      _logger.severe('unknown exception when execute', e);
      status = DownloaderStatus.Fail;
    }
  }

  static Future<void> _isolateDownload(_DownloadParam param) async {
    initLoggerConfig();

    var m3u8Encrypt = param.m3u8.key == null
        ? null
        : await _buildEncrypt(param.m3u8.key!, param.config);

    var receivePort = ReceivePort();
    param.sendPort.send(receivePort.sendPort);
    receivePort.listen((req) async {
      if (req is _DownloadReq) {
        _logger.info(
            '_isolateDownload: download segmentIndex: ${req.segmentIndex}, retryCount: ${req.retryCount}');
        var isSuccess = await _download(
            param.m3u8.segments[req.segmentIndex], m3u8Encrypt, param.config);
        param.sendPort.send(
            _DownloadResp(req.segmentIndex, isSuccess, req.retryCount + 1));
      } else {
        _logger.severe('_isolateDownload: unknown message');
      }
    });
  }

  static Future<bool> _download(M3U8Segment segment, M3U8Encrypt? m3u8Encrypt,
      DownloaderConfig config) async {
    try {
      var tsUri = segment.uri!.startsWith(httpRegExp)
          ? segment.uri!
          : _getUrlPrefix(config.sourceUrl) + segment.uri!;
      var tsFile = File(
          '${config.directory}/${config.taskName}/${Uri.parse(tsUri).pathSegments.last}');
      if (await tsFile.exists()) {
        return true;
      }
      var data = await getBytes(tsUri);
      if (m3u8Encrypt != null) {
        data = await _decrypt(data, m3u8Encrypt);
      }
      await tsFile.writeAsBytes(data);
      return true;
    } catch (e) {
      _logger.severe("_download occurs exception", e);
      return false;
    }
  }

  static Future<Uint8List> _decrypt(
      Uint8List data, M3U8Encrypt m3u8Encrypt) async {
    var decryptBytes = m3u8Encrypt.encrypter.decryptBytes(e.Encrypted(data),
        iv: m3u8Encrypt.iv == null ? null : e.IV(m3u8Encrypt.iv!));
    return Uint8List.fromList(decryptBytes);
  }

  static Future<M3U8> _buildM3U8(String url) async {
    var body = await get(url);
    return parseM3U8(body);
  }

  static Future<M3U8Encrypt> _buildEncrypt(
      M3U8Key keySegment, DownloaderConfig config) async {
    if (keySegment.method == 'AES-128') {
      var key = await getBytes(keySegment.url!.startsWith(httpRegExp)
          ? keySegment.url!
          : _getUrlPrefix(config.sourceUrl) + keySegment.url!);
      var iv = keySegment.iv == null
          ? null
          : e.decodeHexString(keySegment.iv!.startsWith('0x')
              ? keySegment.iv!.substring(2)
              : keySegment.iv!);
      var encrypter = e.Encrypter(e.AES(e.Key(key), mode: e.AESMode.cbc));
      return M3U8Encrypt(keySegment.method!, key, iv, encrypter);
    } else {
      throw M3U8ParesException('nonsupport encrypt method');
    }
  }

  static String _getUrlPrefix(String url) =>
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

class _DownloadParam {
  M3U8 m3u8;
  DownloaderConfig config;
  SendPort sendPort;

  _DownloadParam(this.m3u8, this.config, this.sendPort);
}

class _DownloadReq {
  int segmentIndex;
  int retryCount;

  _DownloadReq(this.segmentIndex, this.retryCount);
}

class _DownloadResp {
  int segmentIndex;
  bool isSuccess;
  int retryCount;

  _DownloadResp(this.segmentIndex, this.isSuccess, this.retryCount);
}

class M3U8Encrypt {
  String method;
  Uint8List key;
  Uint8List? iv;
  e.Encrypter encrypter;

  M3U8Encrypt(this.method, this.key, this.iv, this.encrypter);
}

class M3U8Exception implements Exception {
  String message;

  M3U8Exception(this.message);
}

class M3U8ParesException extends M3U8Exception {
  M3U8ParesException(String message) : super(message);
}

class M3U8DownloadException extends M3U8Exception {
  M3U8DownloadException(String message) : super(message);
}

class M3U8MergeException extends M3U8Exception {
  M3U8MergeException(String message) : super(message);
}

class M3U8ConvertException extends M3U8Exception {
  M3U8ConvertException(String message) : super(message);
}

class M3U8CleanException extends M3U8Exception {
  M3U8CleanException(String message) : super(message);
}

class M3U8InterruptException extends M3U8Exception {
  M3U8InterruptException(String message) : super(message);
}
