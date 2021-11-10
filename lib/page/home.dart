import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:m3u8_downloader/m3u8/downloader.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'add.dart';

final _logger = Logger('page.home');

class HomePage extends StatefulWidget {
  final String _title = 'Downloader';

  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
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
    downloader.execute(); // not await
  }

  Future<void> _folderTapped(DownloaderTaskConfig config) async {
    var path = 'file://${config.dictionary}';
    if (await canLaunch(path)) {
      await launch(path);
    } else {
      _logger.severe('cannot launch path: $path');
    }
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
      body: SingleChildScrollView(
        child: Center(
          child: ChangeNotifierProvider.value(
            value: downloaderList,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.6,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
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
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      leading: IconButton(
                        icon: const Icon(Icons.info),
                        hoverColor: Colors.transparent,
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        onPressed: () {},
                      ),
                      title: Text(downloader.config.taskName),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: LinearProgressIndicator(
                        color: downloader.status == 'Failure'
                            ? Colors.red
                            : Theme.of(context).primaryColor,
                        value: downloader.status == 'Failure'
                            ? 1
                            : downloader.total <= 0
                                ? 0
                                : downloader.progress / downloader.total,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(DateFormat('yyyy-MM-dd HH:mm:ss')
                              .format(downloader.createTime)),
                          Text(downloader.status),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            child: const Text("folder"),
                            onPressed: () async =>
                                await _folderTapped(downloader.config),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            child: const Text("stop"),
                            onPressed: () {},
                          )
                        ],
                      ),
                    ),
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
    list.insert(0, downloader);
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
