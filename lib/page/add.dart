import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home.dart';

class AddPage extends StatefulWidget {
  final String _title;

  const AddPage(this._title, {Key? key}) : super(key: key);

  @override
  _AddPageState createState() => _AddPageState();
}

class _AddPageState extends State<AddPage> {
  bool _canOpenFilePicker = true;
  bool? _cleanTsFiles = true;
  final TextEditingController _taskNameController = TextEditingController();
  final TextEditingController _m3u8Controller = TextEditingController();
  final TextEditingController _dictionaryController = TextEditingController();
  final TextEditingController _concurrencyController =
      TextEditingController(text: '5');

  void _cancelTapped() {
    Navigator.pop(context);
  }

  Future<void> _filePickerTapped() async {
    if (!_canOpenFilePicker) {
      return;
    }
    _canOpenFilePicker = false;
    var directory = await FilePicker.platform.getDirectoryPath();
    if (directory != null) {
      _dictionaryController.text = directory;
    }
    _canOpenFilePicker = true;
  }

  Future<void> _concurrencyInfoTapped() {
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Concurrency Info'),
          content: const Text(
              "It's not recommended to set too large, otherwise it may lead to download failure. The recommended concurrency is 5."),
          actions: <Widget>[
            TextButton(
              child: const Text('Got it'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  void _startTapped() {
    var taskName = _taskNameController.text.isNotEmpty
        ? _taskNameController.text
        : DateTime.now().millisecondsSinceEpoch.toString();
    var sourceUrl = _m3u8Controller.text;
    var dictionary = _dictionaryController.text.isNotEmpty
        ? _dictionaryController.text
        : '~/Downloads';
    var concurrency = int.parse(_concurrencyController.text);
    Navigator.pop(
        context,
        DownloaderTaskConfig(taskName, sourceUrl, dictionary, concurrency,
            _cleanTsFiles ?? true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget._title),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.6,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextField(
                controller: _taskNameController,
                cursorColor: Theme.of(context).textSelectionTheme.cursorColor,
                decoration: InputDecoration(
                  icon: const Icon(Icons.task),
                  labelText: 'TaskName',
                  hintText: 'default use timestamp',
                  labelStyle: TextStyle(
                    color: Theme.of(context).primaryColor,
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide:
                        BorderSide(color: Theme.of(context).primaryColor),
                  ),
                ),
              ),
              TextField(
                controller: _m3u8Controller,
                cursorColor: Theme.of(context).textSelectionTheme.cursorColor,
                decoration: InputDecoration(
                  icon: const Icon(Icons.movie),
                  labelText: 'M3U8',
                  hintText: 'video source url',
                  labelStyle: TextStyle(
                    color: Theme.of(context).primaryColor,
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide:
                        BorderSide(color: Theme.of(context).primaryColor),
                  ),
                ),
              ),
              TextField(
                controller: _dictionaryController,
                cursorColor: Theme.of(context).textSelectionTheme.cursorColor,
                decoration: InputDecoration(
                  icon: const Icon(Icons.save),
                  labelText: 'Dictionary',
                  hintText: 'default use ~/Downloads',
                  labelStyle: TextStyle(
                    color: Theme.of(context).primaryColor,
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide:
                        BorderSide(color: Theme.of(context).primaryColor),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.folder_open),
                    onPressed: () async => await _filePickerTapped(),
                  ),
                ),
              ),
              TextField(
                controller: _concurrencyController,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly
                ],
                cursorColor: Theme.of(context).textSelectionTheme.cursorColor,
                decoration: InputDecoration(
                    icon: const Icon(Icons.double_arrow),
                    labelText: 'Concurrency',
                    helperText: 'number only',
                    labelStyle: TextStyle(
                      color: Theme.of(context).primaryColor,
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: Theme.of(context).primaryColor),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.info),
                      onPressed: () async => await _concurrencyInfoTapped(),
                    )),
              ),
              Row(
                children: [
                  Checkbox(
                    value: _cleanTsFiles,
                    activeColor: Theme.of(context).primaryColor,
                    onChanged: (value) {
                      setState(() => _cleanTsFiles = value);
                    },
                  ),
                  Text(
                    'clean ts files after merge',
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 80,
                    height: 35,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        primary: Colors.grey,
                      ),
                      child: const Text("cancel"),
                      onPressed: () => _cancelTapped(),
                    ),
                  ),
                  const SizedBox(
                    width: 20,
                  ),
                  SizedBox(
                    width: 80,
                    height: 35,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        primary: Theme.of(context).primaryColor,
                      ),
                      child: const Text("start"),
                      onPressed: () => _startTapped(),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
