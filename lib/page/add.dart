import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'home.dart';

class AddPage extends StatefulWidget {
  final String _title;

  const AddPage(this._title, {Key? key}) : super(key: key);

  @override
  _AddPageState createState() => _AddPageState();
}

class _AddPageState extends State<AddPage> {
  final _formKey = GlobalKey<FormState>();

  bool _canOpenFilePicker = true;
  bool? _cleanTsFiles = true;
  final TextEditingController _taskNameController = TextEditingController();
  final TextEditingController _m3u8Controller = TextEditingController();
  final TextEditingController _directoryController = TextEditingController();
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
      _directoryController.text = directory;
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
              "It's not recommended to set too large, otherwise it may lead to download failure."),
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

  Future<void> _startTapped() async {
    if (!(_formKey.currentState!.validate())) {
      return;
    }

    var taskName = _taskNameController.text.isNotEmpty
        ? _taskNameController.text
        : DateTime.now().millisecondsSinceEpoch.toString();
    var sourceUrl = _m3u8Controller.text;
    var directory = _directoryController.text.isNotEmpty
        ? _directoryController.text
        : (await getApplicationDocumentsDirectory()).path;
    var concurrency = int.parse(_concurrencyController.text);
    Navigator.pop(
        context,
        DownloaderConfig(taskName, sourceUrl, directory, concurrency, true,
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
            maxWidth: MediaQuery.of(context).size.width * 0.8,
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextFormField(
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
                TextFormField(
                  controller: _m3u8Controller,
                  cursorColor: Theme.of(context).textSelectionTheme.cursorColor,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'please enter m3u8 url';
                    }
                    if (!value.startsWith(RegExp('https?://')) ||
                        !value.endsWith('.m3u8')) {
                      return 'invalid m3u8 url';
                    }
                    return null;
                  },
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
                TextFormField(
                  controller: _directoryController,
                  cursorColor: Theme.of(context).textSelectionTheme.cursorColor,
                  decoration: InputDecoration(
                    icon: const Icon(Icons.save),
                    labelText: 'Directory',
                    hintText: 'default use Documents',
                    labelStyle: TextStyle(
                      color: Theme.of(context).primaryColor,
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide:
                      BorderSide(color: Theme.of(context).primaryColor),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.folder_open),
                      hoverColor: Colors.transparent,
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      onPressed: () async => await _filePickerTapped(),
                    ),
                  ),
                ),
                TextFormField(
                  controller: _concurrencyController,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  cursorColor: Theme.of(context).textSelectionTheme.cursorColor,
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      var num = int.parse(value);
                      if (num <= 0 || num > 100) {
                        return 'concurrency range 1 to 100';
                      }
                    }
                    return null;
                  },
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
                        hoverColor: Colors.transparent,
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
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
                        onPressed: () async => await _startTapped(),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
