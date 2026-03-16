import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: TestPop()));

class TestPop extends StatefulWidget {
  const TestPop({super.key});
  @override
  State<TestPop> createState() => _TestPopState();
}

class _TestPopState extends State<TestPop> {
  bool canPop = false;
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        print('didPop: $didPop');
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Test Pop')),
        body: Center(
          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Pop'),
          ),
        ),
      ),
    );
  }
}
