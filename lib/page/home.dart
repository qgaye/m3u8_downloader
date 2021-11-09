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

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin {
  final DownloaderList downloaderList = DownloaderList();

  Future<void> _addTapped() async {
    var downloaderTaskConfig = await Navigator.push<DownloaderTaskConfig?>(
        context,
        MaterialPageRoute(builder: (context) => const AddPage('New M3U8')));
    if (downloaderTaskConfig == null) {
      return;
    }
    _logger.info(downloaderTaskConfig.toString());
    var downloader = M3U8Downloader(downloaderTaskConfig);
    downloaderList.add(downloader);
    downloader.execute();  // not await
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
          value: downloaderList,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.6,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Consumer<DownloaderList>(
              builder: (context, downloaderTaskList, child) {
                return Column(
                  children: _buildDownloaderList(),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDownloaderList() {
    var columns = <Widget>[];
    for (var downloader in downloaderList.list) {
      columns.add(
        ChangeNotifierProvider.value(
          value: downloader,
          child: Consumer<M3U8Downloader>(
            builder: (context, downloaderTask, child) {
              return Card(
                child: Column(
                  children: [
                    Text(downloader.config.taskName),
                    Text(downloader.config.sourceUrl),
                    Text('progress: ${downloader.progress}'),
                    Text('total: ${downloader.total}'),
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

  @override
  bool get wantKeepAlive => true;
}

class DownloaderList with ChangeNotifier {
  List<M3U8Downloader> list = [];

  void add(M3U8Downloader downloader) {
    list.add(downloader);
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

