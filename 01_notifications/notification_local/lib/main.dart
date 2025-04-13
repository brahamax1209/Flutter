import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final StreamController<NotificationResponse> selectNotificationStream =
StreamController<NotificationResponse>.broadcast();

String? selectedNotificationPayload;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

int _id = 0;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const paramInit = InitializationSettings(
    android: AndroidInitializationSettings('app_icon'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    ),
  );

  await flutterLocalNotificationsPlugin.initialize(
    paramInit,
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
    _demanderPermissions();
    _ecouterNotification();
  }

  Future<void> _demanderPermissions() async {
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

  void _ecouterNotification() {
    selectNotificationStream.stream.listen(_gererNotification);
  }

  void _gererNotification(NotificationResponse? response) {
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
    appBar: AppBar(title: const Text('Notification Locale')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PaddedElevatedButton(
            buttonText: 'Afficher une notification avec payload',
            onPressed: () =>
                _afficherNotification(titre: 'Titre simple', corps: 'Contenu simple'),
          ),
          PaddedElevatedButton(
            buttonText: 'Afficher une notification sans titre',
            onPressed: () => _afficherNotification(corps: 'Contenu simple'),
          ),
          PaddedElevatedButton(
            buttonText: 'Afficher une notification sans contenu',
            onPressed: () => _afficherNotification(titre: 'Titre simple'),
          ),
          PaddedElevatedButton(
            buttonText: 'Notification silencieuse (aucun son)',
            onPressed: () =>
                _afficherNotification(titre: 'Silencieuse', corps: 'Chut', playSound: false),
          ),
          PaddedElevatedButton(
            buttonText: 'Notification silencieuse (canal avec son activé)',
            onPressed: () =>
                _afficherNotification(titre: 'Shh', corps: 'Silencieux', silent: true),
          ),
          PaddedElevatedButton(
            buttonText: 'Annuler toutes les notifications',
            onPressed: _annulerToutesNotifications,
          ),
        ],
      ),
    ),
  );

  Future<void> _afficherNotification({
    String? titre,
    String? corps,
    bool playSound = true,
    bool silent = false,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'canal_id',
      'canal_nom',
      channelDescription: 'Description du canal',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      playSound: playSound,
      silent: silent,
    );

    final iosDetails = DarwinNotificationDetails(presentSound: playSound);

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      _id++,
      titre,
      corps,
      details,
      payload: 'item x',
    );
  }


  Future<void> _annulerToutesNotifications() async {
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
    appBar: AppBar(title: const Text('Deuxième Écran')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Payload : ${payload ?? ''}'),
          Text('Données : ${data ?? ''}'),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Retour'),
          ),
        ],
      ),
    ),
  );
}

class PaddedElevatedButton extends StatelessWidget {
  const PaddedElevatedButton({
    required this.buttonText,
    required this.onPressed,
    super.key,
  });

  final String buttonText;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
    child: ElevatedButton(
      onPressed: onPressed,
      child: Text(buttonText),
    ),
  );
}
