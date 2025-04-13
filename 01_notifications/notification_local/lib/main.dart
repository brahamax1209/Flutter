import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'padded_button.dart';
import 'plugin.dart';

final StreamController<NotificationResponse> selectNotificationStream =
StreamController<NotificationResponse>.broadcast();

const MethodChannel platform =
MethodChannel('dexterx.dev/flutter_local_notifications_example');

const String portName = 'notification_send_port';

String? selectedNotificationPayload;

const String urlLaunchActionId = 'id_1';
const String navigationActionId = 'id_3';

int _id = 0;


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const initializationSettings = InitializationSettings(
    android: AndroidInitializationSettings('app_icon'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    ),
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: selectNotificationStream.add,
  );

  final notificationAppLaunchDetails =
  await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();

  String initialRoute = HomePage.routeName;
  if (notificationAppLaunchDetails?.didNotificationLaunchApp ?? false) {
    selectedNotificationPayload =
        notificationAppLaunchDetails!.notificationResponse?.payload;
    initialRoute = SecondPage.routeName;
  }

  runApp(MaterialApp(
    initialRoute: initialRoute,
    routes: {
      HomePage.routeName: (_) => HomePage(notificationAppLaunchDetails),
      SecondPage.routeName: (_) => SecondPage(selectedNotificationPayload),
    },
  ));
}

class HomePage extends StatefulWidget {
  const HomePage(this.notificationAppLaunchDetails, {super.key});

  static const String routeName = '/';
  final NotificationAppLaunchDetails? notificationAppLaunchDetails;

  bool get didNotificationLaunchApp =>
      notificationAppLaunchDetails?.didNotificationLaunchApp ?? false;

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {

  @override
  void initState() {
    super.initState();
    _isAndroidPermissionGranted();
    _requestPermissions();
    _configureSelectNotificationSubject();
  }

  Future<void> _isAndroidPermissionGranted() async {
    if (Platform.isAndroid) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled() ??
          false;
    }
  }

  Future<void> _requestPermissions() async {
    if (Platform.isIOS) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isAndroid) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  void _configureSelectNotificationSubject() {
    selectNotificationStream.stream.listen(_handleNotificationResponse);
  }

  void _handleNotificationResponse(NotificationResponse? response) {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SecondPage(response?.payload, data: response?.data),
      ),
    );
  }

  @override
  void dispose() {
    selectNotificationStream.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Local Notification')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tap on a notification when it appears to trigger navigation',
          ),
          _InfoValueString(
            title: 'Did notification launch app?',
            value: widget.didNotificationLaunchApp,
          ),
          if (widget.didNotificationLaunchApp)
            ..._buildLaunchDetails(),
          PaddedElevatedButton(
            buttonText: 'Show plain notification with payload',
            onPressed: () => _showNotification(title: 'plain title', body: 'plain body'),
          ),
          PaddedElevatedButton(
            buttonText: 'Show plain notification that has no title with payload',
            onPressed: () => _showNotification(body: 'plain body'),
          ),
          PaddedElevatedButton(
            buttonText: 'Show plain notification that has no body with payload',
            onPressed: () => _showNotification(title: 'plain title'),
          ),
          PaddedElevatedButton(
            buttonText: 'Show notification from silent channel',
            onPressed: () => _showNotification(title: 'Silent', body: 'Shhh', playSound: false),
          ),
          PaddedElevatedButton(
            buttonText: 'Show silent notification from channel with sound',
            onPressed: () => _showNotification(title: 'Shh', body: 'Silent', silent: true),
          ),
          PaddedElevatedButton(
            buttonText: 'Cancel latest notification',
            onPressed: _cancelNotification,
          ),
          PaddedElevatedButton(
            buttonText: 'Cancel all notification',
            onPressed: _cancelAllNotifications,
          ),
        ],
      ),
    ),
  );

  List<Widget> _buildLaunchDetails() {
    final response = widget.notificationAppLaunchDetails!.notificationResponse;
    return [
      const Text('Launch notification details'),
      _InfoValueString(title: 'Notification id', value: response?.id),
      _InfoValueString(title: 'Action id', value: response?.actionId),
      _InfoValueString(title: 'Input', value: response?.input),
      _InfoValueString(title: 'Payload:', value: response?.payload),
    ];
  }

  Future<void> _showNotification({
    String? title,
    String? body,
    bool playSound = true,
    bool silent = false,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'your channel id',
      'your channel name',
      channelDescription: 'your channel description',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      playSound: playSound,
      silent: silent,
    );

    final iOSDetails = DarwinNotificationDetails(presentSound: playSound);

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      _id++,
      title,
      body,
      details,
      payload: 'item x',
    );
  }

  Future<void> _cancelNotification() async {
    await flutterLocalNotificationsPlugin.cancel(--_id);
  }

  Future<void> _cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }
}

class SecondPage extends StatelessWidget {
  const SecondPage(this.payload, {this.data, super.key});

  static const String routeName = '/secondPage';

  final String? payload;
  final Map<String, dynamic>? data;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Second Screen')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('payload ${payload ?? ''}'),
          Text('data ${data ?? ''}'),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Go back!'),
          ),
        ],
      ),
    ),
  );
}

class _InfoValueString extends StatelessWidget {
  const _InfoValueString({required this.title, required this.value});

  final String title;
  final Object? value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$title ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: '$value'),
        ],
      ),
    ),
  );
}
