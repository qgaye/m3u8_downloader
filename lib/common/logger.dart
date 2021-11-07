import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

void initLoggerConfig() {
  Logger.root.level = Level.INFO;
  recordStackTraceAtLevel = Level.SEVERE;
  Logger.root.onRecord.listen((record) {
    debugPrint(
        '${record.time} [${record.level.name}] [${Isolate.current.debugName} | ${record.loggerName}] ${record.message}');
  });
}