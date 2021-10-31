import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

void main() {
  Logger.root.level = Level.INFO;
  recordStackTraceAtLevel = Level.SEVERE;
  Logger.root.onRecord.listen((record) {
    print(
        '${record.time} [${record.level.name}] [${record.loggerName}] ${record.message}');
  });
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'M3U8-Downloader',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MainApp(),
    );
  }
}

class MainApp extends StatelessWidget {
  const MainApp({Key? key}) : super(key: key);

  void _onPressed() {
    debugPrint("HELLO");
    FFmpegKit.executeAsync(
        '-i /Users/qgaye/Downloads/194770.ts -c:v libx264 -c:a aac /Users/qgaye/Downloads/output.mp4',
        (session) async {
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        debugPrint('Success');
      } else if (ReturnCode.isCancel(returnCode)) {
        debugPrint('Cancel');
      } else {
        debugPrint('Error');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 150,
        height: 50,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.send),
          label: const Text("发送"),
          onPressed: _onPressed,
        ),
      ),
    );
  }
}
