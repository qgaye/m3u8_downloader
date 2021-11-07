import 'package:flutter/material.dart';

class AccountPage extends StatefulWidget {
  final String _title = 'Account';

  const AccountPage({Key? key}) : super(key: key);

  @override
  _AccountPageState createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget._title),
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
