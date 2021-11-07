import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:m3u8_downloader/m3u8/downloader.dart';

import 'add.dart';

final _logger = Logger('page.home');

class HomePage extends StatefulWidget {
  final String _title = 'Downloader';

  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<DownloaderTask> taskLists = [
    DownloaderTask(DownloaderTaskConfig('test', 'url', 'path', 2, true), 1111),
  ];

  Future<void> _addTapped() async {
    var downloaderTaskConfig = await Navigator.push<DownloaderTaskConfig?>(
        context,
        MaterialPageRoute(
            builder: (context) => const AddPage('New M3U8')));
    if (downloaderTaskConfig == null) {
      return;
    }
    _logger.info(downloaderTaskConfig.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget._title),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            iconSize: 30,
            onPressed: () async => await _addTapped(),
          )
        ],
      ),
      body: Center(
        child: Text(
          '${widget._title}内容',
          style: const TextStyle(fontSize: 20),
        ),
      ),
    );
  }
}

class DownloaderTaskConfig {
  String taskName;
  String sourceUrl;
  String dictionary;
  int concurrency;
  bool cleanTsFiles;

  DownloaderTaskConfig(this.taskName, this.sourceUrl, this.dictionary,
      this.concurrency, this.cleanTsFiles);

  @override
  String toString() {
    return 'DownloaderTaskConfig{taskName: $taskName, sourceUrl: $sourceUrl, dictionary: $dictionary, concurrency: $concurrency, cleanTsFiles: $cleanTsFiles}';
  }
}

class DownloaderTask {
  DownloaderTaskConfig config;
  late M3U8Downloader downloader;
  int progress = 0;
  int total;
  int status = 0;

  DownloaderTask(this.config, this.total);

}

