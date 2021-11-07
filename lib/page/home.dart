import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:m3u8_downloader/m3u8/downloader.dart';
import 'package:provider/provider.dart';

import 'add.dart';

final _logger = Logger('page.home');

class HomePage extends StatefulWidget {
  final String _title = 'Downloader';

  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DownloaderTaskList taskList = DownloaderTaskList();

  Future<void> _addTapped() async {
    var downloaderTaskConfig = await Navigator.push<DownloaderTaskConfig?>(
        context,
        MaterialPageRoute(builder: (context) => const AddPage('New M3U8')));
    if (downloaderTaskConfig == null) {
      return;
    }
    _logger.info(downloaderTaskConfig.toString());
    var downloaderTask = DownloaderTask(downloaderTaskConfig);
    taskList.add(downloaderTask);
    downloaderTask.execute();
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
          ),
        ],
      ),
      body: Center(
        child: ChangeNotifierProvider.value(
          value: taskList,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.6,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Consumer<DownloaderTaskList>(
              builder: (context, downloaderTaskList, child) {
                return Column(
                  children: _buildDownloaderTaskList(),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDownloaderTaskList() {
    var columns = <Widget>[];
    for (var task in taskList.list) {
      columns.add(
        ChangeNotifierProvider.value(
          value: task,
          child: Consumer<DownloaderTask>(
            builder: (context, downloaderTask, child) {
              return Card(
                child: Column(
                  children: [
                    Text(task.config.taskName),
                    Text(task.config.sourceUrl),
                    Text('progress: ${task.progress}'),
                    Text('total: ${task.total}'),
                  ],
                ),
              );
            },
          ),
        ),
      );
    }
    return columns;
  }
}

class DownloaderTaskList with ChangeNotifier {
  List<DownloaderTask> list = [];

  void add(DownloaderTask task) {
    list.add(task);
    notifyListeners();
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

class DownloaderTask with ChangeNotifier {
  DownloaderTaskConfig config;
  late M3U8Downloader downloader;
  int progress = 0;
  int? total;
  int status = 0;

  DownloaderTask(this.config);

  void incrementProgress(int i) {
    progress += i;
    notifyListeners();
  }

  Future<void> init() async {
    downloader = await M3U8Downloader.create(config.sourceUrl,
        path: config.dictionary,
        name: config.taskName,
        parallelism: config.concurrency);
    total = downloader.m3u8.segments.length;
  }

  Future<void> execute() async {
    await init();
    notifyListeners();
    await downloader.download();
    notifyListeners();
    await downloader.merge();
    notifyListeners();
    await downloader.convert();
    notifyListeners();
    if (config.cleanTsFiles) {
      await downloader.clean();
      notifyListeners();
    }
  }
}
