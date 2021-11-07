import 'package:flutter/material.dart';
import 'package:m3u8_downloader/common/logger.dart';
import 'package:m3u8_downloader/page/account.dart';
import 'package:m3u8_downloader/page/add.dart';
import 'package:m3u8_downloader/page/home.dart';

void main() {
  initLoggerConfig();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'M3U8-Downloader',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
      ),
      home: const MainApp(),
    );
  }
}

class MainApp extends StatefulWidget {
  const MainApp({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final _bottomNavPages = <Widget>[
    const HomePage(),
    const AccountPage(),
  ];
  var _selectedPageIndex = 0;

  void _onNavBottomTapped(int index) {
    setState(() => _selectedPageIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _bottomNavPages[_selectedPageIndex],
      bottomNavigationBar: BottomAppBar(
        color: Theme.of(context).primaryColor,
        child: Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(
                Icons.home,
                color: Colors.white,
              ),
              onPressed: () => _onNavBottomTapped(0),
            ),
            const SizedBox(),
            IconButton(
              icon: const Icon(
                Icons.account_circle,
                color: Colors.white,
              ),
              onPressed: () => _onNavBottomTapped(1),
            ),
          ],
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        ),
      ),
    );
  }
}
