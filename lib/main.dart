import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(const MyApp());
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'download_service', // id
    'Background Download Service', // title
    description:
        'This service handles background file downloads.', // description
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('ic_bg_service_small'),
    ),
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'download_service',
      initialNotificationTitle: 'Download Service',
      initialNotificationContent: 'Initializing...',
      foregroundServiceNotificationId: 123,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
    ),
  );

  service.startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  service.on('startDownload').listen((event) async {
    final url = event?['url'] as String?;
    if (url != null) {
      await _downloadFile(url, service);
    }
  });

  if (service is AndroidServiceInstance) {
    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    service.setForegroundNotificationInfo(
      title: "Download Service",
      content: "Waiting for tasks...",
    );
  }
}

Future<Directory?> getDownloadPath() async {
  try {
    if (Platform.isIOS) {
      return await getApplicationDocumentsDirectory();
    } else {
      var directory = Directory('/storage/emulated/0/Download');
      if (!await directory.exists()) {
        directory = await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory();
      }
      return directory;
    }
  } catch (err) {
    return null;
  }
}

Future<void> _downloadFile(String url, ServiceInstance service) async {
  final dio = Dio();

  try {
    final path = await getDownloadPath();
    if (path == null) {
      throw Exception("Failed to get a valid path for database storage.");
    }

    final filePath = join(path.path, 'BG-Download', url.split('/').last);
    debugPrint("Download started: $url");

    await dio.download(
      url,
      filePath,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          debugPrint("Downloaded :  $received/$total");
          final progress = (received / total * 100).toStringAsFixed(0);
          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: "Downloading...",
              content: "Progress: $progress%",
            );
          }
        }
      },
    ).then((_) {
      isDownloading.value = false;
      if (service is AndroidServiceInstance) {
        debugPrint("Download completed: $filePath");
        service.setForegroundNotificationInfo(
          title: "Download Completed",
          content: "File saved: ${filePath.split('/').last}",
        );

        scaffKey.currentState?.showSnackBar(
          SnackBar(
            content: Text("Download Completed : ${filePath.split('/').last}"),
          ),
        );
      }
    });
  } catch (e) {
    isDownloading.value = false;
    debugPrint("Download error: $e");
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "Download Error",
        content: e.toString(),
      );
    }
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

final GlobalKey<ScaffoldMessengerState> scaffKey =
    GlobalKey<ScaffoldMessengerState>();

final ValueNotifier<bool> isDownloading = ValueNotifier(false);

class _MyAppState extends State<MyApp> {
  final TextEditingController urlController = TextEditingController(
      text: "https://www.sample-videos.com/img/Sample-jpg-image-10mb.jpg");

  Future<void> startDownload(String url) async {
    if (url.isNotEmpty) {
      FlutterBackgroundService().invoke('startDownload', {'url': url});
    } else {
      scaffKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Please enter a valid URL')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffKey,
      home: Scaffold(
        appBar: AppBar(title: const Text('Background Downloader')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Enter File URL',
                ),
              ),
              const SizedBox(height: 20),
              ValueListenableBuilder(
                valueListenable: isDownloading,
                builder: (context, value, child) {
                  return ElevatedButton(
                    onPressed: value
                        ? null
                        : () async {
                            isDownloading.value = true;
                            await startDownload(urlController.text);
                          },
                    child: Text(value ? "Downloading..." : 'Start Download'),
                  );
                },
              )
            ],
          ),
        ),
      ),
    );
  }
}
