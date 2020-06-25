import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record_example/audio_player.dart';
import 'package:record_example/audio_recorder.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool showPlayer;
  String path;

  @override
  void initState() {
    showPlayer = false;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: FutureBuilder<String>(
            future: getPath(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                if (showPlayer) {
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: 25),
                    child: AudioPlayer(
                      path: snapshot.data,
                      onDelete: () {
                        setState(() {
                          showPlayer = false;
                        });
                      },
                    ),
                  );
                } else {
                  return AudioRecorder(
                    path: snapshot.data,
                    onStop: () {
                      setState(() {
                        showPlayer = true;
                      });
                    },
                  );
                }
              } else {
                return Center(child: CircularProgressIndicator());
              }
            },
          ),
        ),
      ),
    );
  }

  Future<String> getPath() async {
    if (path == null) {
      final dir = await getApplicationDocumentsDirectory();
      path = dir.path +
          '/' +
          DateTime.now().millisecondsSinceEpoch.toString() +
          '.m4a';
    }
    return path;
  }
}
