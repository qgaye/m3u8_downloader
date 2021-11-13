import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:m3u8_downloader/common/extensions.dart';
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

  Future<bool> parse() async {
    try {
      if (!config.sourceUrl.startsWith(httpRegExp) ||
          !config.sourceUrl.endsWith('.m3u8')) {
        return false;
      }
      m3u8 = parseM3U8(await get(config.sourceUrl));
      if (!_checkM3U8(m3u8)) {
        return false;
      }
    } on M3U8Exception catch (e) {
      _logger.severe('parse: occur m3u8Exception $e');
      return false;
    }
    _interruptCheck('parse');
    return true;
  }

  Future<bool> download() async {
    var dir = Directory('${config.directory}/${config.taskName}');
    if (!(await dir.exists())) {
      _logger.info('target directory not exists, create ${dir.path}');
      await dir.create();
    }

    var m3u8Encrypt =
        m3u8.key == null ? null : await _buildEncrypt(m3u8.key!, config);

    // retry时候
    downloadSegmentIndex = 0;
    successSegmentIndexes = [];
    retrySegmentIndexes = {};
    failedSegmentIndexes = [];
    progress = 0;

    var completers = <Completer>[];
    var sendPortMap = <ReceivePort, SendPort>{};
    var isolateMap = <ReceivePort, Isolate>{};

    for (var i = 0; i < config.concurrency; i++) {
      var random = Random();
      var completer = Completer();
      completers.add(completer);
      var receivePort = ReceivePort();
      var isolate = await Isolate.spawn(_isolateDownload,
          _DownloadParam(m3u8, config, m3u8Encrypt, receivePort.sendPort),
          debugName: 'downloader-$i');
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
          return;
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

    _interruptCheck('download');
    return successSegmentIndexes.length == m3u8.segments.length;
  }

  Future<bool> merge() async {
    var file = File(_buildTargetFile(config.taskName, 'ts'));
    if (await file.exists()) {
      _logger.info('merge: exist target file, delete ${file.path}');
      await file.delete();
    }

    for (var segment in m3u8.segments) {
      var ts = File('${config.directory}/${config.taskName}/${segment.uri}');
      if (await ts.exists()) {
        await file.writeAsBytes(await ts.readAsBytes(), mode: FileMode.append);
      } else {
        _logger.severe('merge: cannot find ts segment: ${ts.path}');
        return false;
      }
    }
    _interruptCheck('merge');
    return true;
  }

  Future<bool> convert() async {
    var targetFile = File(_buildTargetFile(config.taskName, 'mp4'));
    if (await targetFile.exists()) {
      _logger.info('convert: exist target file, delete ${targetFile.path}');
      await targetFile.delete();
    }

    var command =
        '-n -i ${_buildTargetFile(config.taskName, 'ts')} -c:v copy -c:a copy ${_buildTargetFile(config.taskName, 'mp4')}';
    _logger.info('convert: ffmpeg $command');
    ReturnCode? returnCode;
    var completer = Completer();
    await FFmpegKit.executeAsync(command, (session) async {
      returnCode = await session.getReturnCode();
      completer.complete();
    });
    await Future.wait([completer.future]);

    if (!ReturnCode.isSuccess(returnCode)) {
      _logger.severe('convert: ffmpeg returnCode ${returnCode?.getValue()}');
      return false;
    }

    _interruptCheck('convert');
    return true;
  }

  Future<bool> clean() async {
    for (var segment in m3u8.segments) {
      var ts = File('${config.directory}/${config.taskName}/${segment.uri}');
      if (await ts.exists()) {
        await ts.delete();
      } else {
        _logger.severe('clean: not exist ts, file: ${ts.path}');
        return false;
      }
    }
    _interruptCheck('clean');
    return true;
  }

  Future<bool> execute() async {
    _logger.info('execute: m3u8 task: $config');
    try {
      // Parse
      status = DownloaderStatus.Parsing;
      if (!await parse()) {
        status = DownloaderStatus.ParseFail;
        return false;
      }
      total = m3u8.segments.length;

      // Downlaod
      status = DownloaderStatus.Downloading;
      if (!await download()) {
        status = DownloaderStatus.DownloadFail;
        return false;
      }

      // Merge
      status = DownloaderStatus.Merging;
      if (!await merge()) {
        status = DownloaderStatus.MergeFail;
        return false;
      }

      // Convert
      if (config.convertTs) {
        status = DownloaderStatus.Converting;
        if (!await convert()) {
          status = DownloaderStatus.ConvertFail;
          return false;
        }
      }

      // Clean
      if (config.cleanTsFiles) {
        status = DownloaderStatus.Cleaning;
        if (!await clean()) {
          status = DownloaderStatus.CleanFail;
          return false;
        }
      }
      status = DownloaderStatus.Success;
    } on M3U8InterruptException catch (e) {
      _logger.info('execute: interrupt in ${e.message}');
      status = DownloaderStatus.Interrupted;
      return false;
    } on M3U8Exception catch (e) {
      _logger.severe('execute: occur m3u8Exception', e);
      status = DownloaderStatus.Fail;
      return false;
    } catch (e) {
      _logger.severe('execute: occur unknown exception', e);
      status = DownloaderStatus.Fail;
      return false;
    }
    return true;
  }

  String _buildTargetFile(String fileName, String fileSuffix) {
    return '${config.directory}/${config.taskName}/$fileName.$fileSuffix';
  }

  Future<void> interrupt() async {
    isInterrupt = true;
  }

  void _interruptCheck(String method) {
    if (isInterrupt) {
      throw M3U8InterruptException(method);
    }
  }

  String buildStatus() {
    if (status == DownloaderStatus.Downloading) {
      return '${status.name()}($progress/$total)';
    }
    return status.name();
  }

  static Future<void> _isolateDownload(_DownloadParam param) async {
    initLoggerConfig();

    var receivePort = ReceivePort();
    param.sendPort.send(receivePort.sendPort);
    receivePort.listen((req) async {
      if (req is _DownloadReq) {
        _logger.info(
            '_isolateDownload: download segmentIndex: ${req.segmentIndex}, retryCount: ${req.retryCount}');
        var isSuccess = await _download(param.m3u8.segments[req.segmentIndex],
            param.m3u8Encrypt, param.config);
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
      throw M3U8Exception('nonsupport encrypt method');
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
  M3U8Encrypt? m3u8Encrypt;
  SendPort sendPort;

  _DownloadParam(this.m3u8, this.config, this.m3u8Encrypt, this.sendPort);
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

class M3U8InterruptException extends M3U8Exception {
  M3U8InterruptException(String message) : super(message);
}
