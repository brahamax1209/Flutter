import 'dart:async';
import 'dart:convert';
import 'dart:io';
// ignore: unnecessary_import
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'padded_button.dart';
import 'plugin.dart';
import 'repeating.dart' as repeating;

/// Streams are created so that app can respond to notification-related events
/// since the plugin is initialized in the `main` function
final StreamController<NotificationResponse> selectNotificationStream =
StreamController<NotificationResponse>.broadcast();

const MethodChannel platform =
MethodChannel('dexterx.dev/flutter_local_notifications_example');

const String portName = 'notification_send_port';

class ReceivedNotification {
  ReceivedNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
    this.data,
  });

  final int id;
  final String? title;
  final String? body;
  final String? payload;
  final Map<String, dynamic>? data;
}

String? selectedNotificationPayload;

/// A notification action which triggers a url launch event
const String urlLaunchActionId = 'id_1';

/// A notification action which triggers a App navigation event
const String navigationActionId = 'id_3';

/// Defines a iOS notification category for text input actions.
const String darwinNotificationCategoryText = 'textCategory';

/// Defines a iOS notification category for plain actions.
const String darwinNotificationCategoryPlain = 'plainCategory';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  // ignore: avoid_print
  print('notification(${notificationResponse.id}) action tapped: '
      '${notificationResponse.actionId} with'
      ' payload: ${notificationResponse.payload}');
  if (notificationResponse.input?.isNotEmpty ?? false) {
    // ignore: avoid_print
    print(
        'notification action tapped with input: ${notificationResponse.input}');
  }
}

/// IMPORTANT: running the following code on its own won't work as there is
/// setup required for each platform head project.
///
/// Please download the complete example app from the GitHub repository where
/// all the setup has been done
Future<void> main() async {
  // needed if you intend to initialize in the `main` function
  WidgetsFlutterBinding.ensureInitialized();

  await _configureLocalTimeZone();

  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('app_icon');

  final List<DarwinNotificationCategory> darwinNotificationCategories =
  <DarwinNotificationCategory>[
    DarwinNotificationCategory(
      darwinNotificationCategoryText,
      actions: <DarwinNotificationAction>[
        DarwinNotificationAction.text(
          'text_1',
          'Action 1',
          buttonTitle: 'Send',
          placeholder: 'Placeholder',
        ),
      ],
    ),
    DarwinNotificationCategory(
      darwinNotificationCategoryPlain,
      actions: <DarwinNotificationAction>[
        DarwinNotificationAction.plain('id_1', 'Action 1'),
        DarwinNotificationAction.plain(
          'id_2',
          'Action 2 (destructive)',
          options: <DarwinNotificationActionOption>{
            DarwinNotificationActionOption.destructive,
          },
        ),
        DarwinNotificationAction.plain(
          navigationActionId,
          'Action 3 (foreground)',
          options: <DarwinNotificationActionOption>{
            DarwinNotificationActionOption.foreground,
          },
        ),
        DarwinNotificationAction.plain(
          'id_4',
          'Action 4 (auth required)',
          options: <DarwinNotificationActionOption>{
            DarwinNotificationActionOption.authenticationRequired,
          },
        ),
      ],
      options: <DarwinNotificationCategoryOption>{
        DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
      },
    )
  ];

  /// Note: permissions aren't requested here just to demonstrate that can be
  /// done later
  final DarwinInitializationSettings initializationSettingsDarwin =
  DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
    notificationCategories: darwinNotificationCategories,
  );



  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: selectNotificationStream.add,
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  final NotificationAppLaunchDetails? notificationAppLaunchDetails =
  await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
  String initialRoute = HomePage.routeName;
  if (notificationAppLaunchDetails?.didNotificationLaunchApp ?? false) {
    selectedNotificationPayload =
        notificationAppLaunchDetails!.notificationResponse?.payload;
    initialRoute = SecondPage.routeName;
  }

  runApp(
    MaterialApp(
      initialRoute: initialRoute,
      routes: <String, WidgetBuilder>{
        HomePage.routeName: (_) => HomePage(notificationAppLaunchDetails),
        SecondPage.routeName: (_) => SecondPage(selectedNotificationPayload)
      },
    ),
  );
}

Future<void> _configureLocalTimeZone() async {
  tz.initializeTimeZones();
  final String timeZoneName = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(timeZoneName));
}

class HomePage extends StatefulWidget {
  const HomePage(
      this.notificationAppLaunchDetails, {
        super.key,
      });

  static const String routeName = '/';

  final NotificationAppLaunchDetails? notificationAppLaunchDetails;

  bool get didNotificationLaunchApp =>
      notificationAppLaunchDetails?.didNotificationLaunchApp ?? false;

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {

  bool _notificationsEnabled = false;

  @override
  void initState() {
    super.initState();
    _isAndroidPermissionGranted();
    _requestPermissions();
    _configureSelectNotificationSubject();
  }

  Future<void> _isAndroidPermissionGranted() async {
    if (Platform.isAndroid) {
      final bool granted = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled() ??
          false;

      setState(() {
        _notificationsEnabled = granted;
      });
    }
  }

  Future<void> _requestPermissions() async {
    if (Platform.isIOS) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    } else if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      final bool? grantedNotificationPermission =
      await androidImplementation?.requestNotificationsPermission();
      setState(() {
        _notificationsEnabled = grantedNotificationPermission ?? false;
      });
    }
  }

  Future<void> _requestPermissionsWithCriticalAlert() async {
    if (Platform.isIOS ) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
        critical: true,
      );

    }
  }

  void _configureSelectNotificationSubject() {
    selectNotificationStream.stream
        .listen((NotificationResponse? response) async {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            SecondPage(response?.payload, data: response?.data),
      ));
    });
  }

  @override
  void dispose() {
    selectNotificationStream.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Local Notification'),
    ),
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(0, 0, 0, 8),
                child:
                Text('Tap on a notification when it appears to trigger'
                    ' navigation'),
              ),
              _InfoValueString(
                title: 'Did notification launch app?',
                value: widget.didNotificationLaunchApp,
              ),
              if (widget.didNotificationLaunchApp) ...<Widget>[
                const Text('Launch notification details'),
                _InfoValueString(
                    title: 'Notification id',
                    value: widget.notificationAppLaunchDetails!
                        .notificationResponse?.id),
                _InfoValueString(
                    title: 'Action id',
                    value: widget.notificationAppLaunchDetails!
                        .notificationResponse?.actionId),
                _InfoValueString(
                    title: 'Input',
                    value: widget.notificationAppLaunchDetails!
                        .notificationResponse?.input),
                _InfoValueString(
                  title: 'Payload:',
                  value: widget.notificationAppLaunchDetails!
                      .notificationResponse?.payload,
                ),
              ],
              PaddedElevatedButton(
                buttonText: 'Show plain notification with payload',
                onPressed: () async {
                  await _showNotification();
                },
              ),
              PaddedElevatedButton(
                buttonText:
                'Show plain notification that has no title with '
                    'payload',
                onPressed: () async {
                  await _showNotificationWithNoTitle();
                },
              ),
              PaddedElevatedButton(
                buttonText: 'Show plain notification that has no body with '
                    'payload',
                onPressed: () async {
                  await _showNotificationWithNoBody();
                },
              ),
              PaddedElevatedButton(
                buttonText: 'Show notification with custom sound',
                onPressed: () async {
                  await _showNotificationCustomSound();
                },
              ),

              PaddedElevatedButton(
                buttonText: 'Show notification from silent channel',
                onPressed: () async {
                  await _showNotificationWithNoSound();
                },
              ),
              PaddedElevatedButton(
                buttonText:
                'Show silent notification from channel with sound',
                onPressed: () async {
                  await _showNotificationSilently();
                },
              ),
              PaddedElevatedButton(
                buttonText: 'Cancel latest notification',
                onPressed: () async {
                  await _cancelNotification();
                },
              ),
              PaddedElevatedButton(
                buttonText: 'Cancel all notifications',
                onPressed: () async {
                  await _cancelAllNotifications();
                },
              ),
              ...repeating.examples(context),
              const Divider(),
              const Text(
                'Notifications with actions',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              PaddedElevatedButton(
                buttonText: 'Show notification with plain actions',
                onPressed: () async {
                  await _showNotificationWithActions();
                },
              ),

                PaddedElevatedButton(
                  buttonText: 'Show notification with text action',
                  onPressed: () async {
                    await _showNotificationWithTextAction();
                  },
                ),

                PaddedElevatedButton(
                  buttonText: 'Show notification with text choice',
                  onPressed: () async {
                    await _showNotificationWithTextChoice();
                  },
                ),
              const Divider(),
              if (Platform.isAndroid) ...<Widget>[
                const Text(
                  'Android-specific examples',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('notifications enabled: $_notificationsEnabled'),
                PaddedElevatedButton(
                  buttonText:
                  'Check if notifications are enabled for this app',
                  onPressed: _areNotifcationsEnabledOnAndroid,
                ),
                PaddedElevatedButton(
                  buttonText: 'Request permission (API 33+)',
                  onPressed: () => _requestPermissions(),
                ),
                PaddedElevatedButton(
                  buttonText:
                  'Show plain notification with payload and update '
                      'channel description',
                  onPressed: () async {
                    await _showNotificationUpdateChannelDescription();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show plain notification as public on every '
                      'lockscreen',
                  onPressed: () async {
                    await _showPublicNotification();
                  },
                ),
                PaddedElevatedButton(
                  buttonText:
                  'Show notification with custom vibration pattern, '
                      'red LED and red icon',
                  onPressed: () async {
                    await _showNotificationCustomVibrationIconLed();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show notification using Android Uri sound',
                  onPressed: () async {
                    await _showSoundUriNotification();
                  },
                ),
                PaddedElevatedButton(
                  buttonText:
                  'Show notification that times out after 3 seconds',
                  onPressed: () async {
                    await _showTimeoutNotification();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show insistent notification',
                  onPressed: () async {
                    await _showInsistentNotification();
                  },
                ),
                PaddedElevatedButton(
                  buttonText:
                  'Show big picture notification using local images',
                  onPressed: () async {
                    await _showBigPictureNotification();
                  },
                ),
                PaddedElevatedButton(
                  buttonText:
                  'Show big picture notification using base64 String '
                      'for images',
                  onPressed: () async {
                    await _showBigPictureNotificationBase64();
                  },
                ),
                PaddedElevatedButton(
                  buttonText:
                  'Show big picture notification using URLs for '
                      'Images',
                  onPressed: () async {
                    await _showBigPictureNotificationURL();
                  },
                ),
                PaddedElevatedButton(
                  buttonText:
                  'Show big picture notification, hide large icon '
                      'on expand',
                  onPressed: () async {
                    await _showBigPictureNotificationHiddenLargeIcon();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show media notification',
                  onPressed: () async {
                    await _showNotificationMediaStyle();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show big text notification',
                  onPressed: () async {
                    await _showBigTextNotification();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show inbox notification',
                  onPressed: () async {
                    await _showInboxNotification();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show messaging notification',
                  onPressed: () async {
                    await _showMessagingNotification();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show grouped notifications',
                  onPressed: () async {
                    await _showGroupedNotifications();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show notification with tag',
                  onPressed: () async {
                    await _showNotificationWithTag();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Cancel notification with tag',
                  onPressed: () async {
                    await _cancelNotificationWithTag();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show ongoing notification',
                  onPressed: () async {
                    await _showOngoingNotification();
                  },
                ),
                PaddedElevatedButton(
                  buttonText:
                  'Show notification with no badge, alert only once',
                  onPressed: () async {
                    await _showNotificationWithNoBadge();
                  },
                ),
                PaddedElevatedButton(
                  buttonText:
                  'Show progress notification - updates every second',
                  onPressed: () async {
                    await _showProgressNotification();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show indeterminate progress notification',
                  onPressed: () async {
                    await _showIndeterminateProgressNotification();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show notification without timestamp',
                  onPressed: () async {
                    await _showNotificationWithoutTimestamp();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show notification with custom timestamp',
                  onPressed: () async {
                    await _showNotificationWithCustomTimestamp();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show notification with custom sub-text',
                  onPressed: () async {
                    await _showNotificationWithCustomSubText();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show notification with chronometer',
                  onPressed: () async {
                    await _showNotificationWithChronometer();
                  },
                ),
                PaddedElevatedButton(
                  buttonText:
                  'Request full-screen intent permission (API 34+)',
                  onPressed: () async {
                    await _requestFullScreenIntentPermission();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show full-screen notification',
                  onPressed: () async {
                    await _showFullScreenNotification();
                  },
                ),
                PaddedElevatedButton(
                  buttonText:
                  'Show notification with number if the launcher '
                      'supports',
                  onPressed: () async {
                    await _showNotificationWithNumber();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show notification with sound controlled by '
                      'alarm volume',
                  onPressed: () async {
                    await _showNotificationWithAudioAttributeAlarm();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Create grouped notification channels',
                  onPressed: () async {
                    await _createNotificationChannelGroup();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Delete notification channel group',
                  onPressed: () async {
                    await _deleteNotificationChannelGroup();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Create notification channel',
                  onPressed: () async {
                    await _createNotificationChannel();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Delete notification channel',
                  onPressed: () async {
                    await _deleteNotificationChannel();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Get notification channels',
                  onPressed: () async {
                    await _getNotificationChannels();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Start foreground service',
                  onPressed: () async {
                    await _startForegroundService();
                  },
                ),
                PaddedElevatedButton(
                  buttonText:
                  'Start foreground service with blue background '
                      'notification',
                  onPressed: () async {
                    await _startForegroundServiceWithBlueBackgroundNotification();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Stop foreground service',
                  onPressed: () async {
                    await _stopForegroundService();
                  },
                ),
              ],
              if (Platform.isIOS) ...<Widget>[
                const Text(
                  'iOS specific examples',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                PaddedElevatedButton(
                  buttonText: 'Check permissions',
                  onPressed: _checkNotificationsOnCupertino,
                ),
                PaddedElevatedButton(
                  buttonText: 'Request permission',
                  onPressed: _requestPermissions,
                ),
                PaddedElevatedButton(
                  buttonText:
                  'Request permission with critical alert permission',
                  onPressed: _requestPermissionsWithCriticalAlert,
                ),
                PaddedElevatedButton(
                  buttonText: 'Show notification with subtitle',
                  onPressed: () async {
                    await _showNotificationWithSubtitle();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show notification with critical sound',
                  onPressed: () async {
                    await _showNotificationWithCriticalSound();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show notification with icon badge',
                  onPressed: () async {
                    await _showNotificationWithIconBadge();
                  },
                ),
                PaddedElevatedButton(
                  buttonText:
                  'Show notification with attachment (clipped thumbnail)',
                  onPressed: () async {
                    await _showNotificationWithClippedThumbnailAttachment();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show notifications with thread identifier',
                  onPressed: () async {
                    await _showNotificationsWithThreadIdentifier();
                  },
                ),
                PaddedElevatedButton(
                  buttonText:
                  'Show notification with time sensitive interruption '
                      'level',
                  onPressed: () async {
                    await _showNotificationWithTimeSensitiveInterruptionLevel();
                  },
                ),
                PaddedElevatedButton(
                  buttonText: 'Show notification with banner but not in '
                      'notification centre',
                  onPressed: () async {
                    await _showNotificationWithBannerNotInNotificationCentre();
                  },
                ),
                PaddedElevatedButton(
                  buttonText:
                  'Show notification in notification centre only',
                  onPressed: () async {
                    await _showNotificationInNotificationCentreOnly();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _showNotification() async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails('your channel id', 'your channel name',
        channelDescription: 'your channel description',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker');
    const NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++, 'plain title', 'plain body', notificationDetails,
        payload: 'item x');
  }

  Future<void> _showNotificationWithActions() async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails(
      'your channel id',
      'your channel name',
      channelDescription: 'your channel description',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          urlLaunchActionId,
          'Action 1',
          icon: DrawableResourceAndroidBitmap('food'),
          contextual: true,
        ),
        AndroidNotificationAction(
          'id_2',
          'Action 2',
          titleColor: Color.fromARGB(255, 255, 0, 0),
          icon: DrawableResourceAndroidBitmap('secondary_icon'),
        ),
        AndroidNotificationAction(
          navigationActionId,
          'Action 3',
          icon: DrawableResourceAndroidBitmap('secondary_icon'),
          showsUserInterface: true,
          // By default, Android plugin will dismiss the notification when the
          // user tapped on a action (this mimics the behavior on iOS).
          cancelNotification: false,
        ),
      ],
    );

    const DarwinNotificationDetails iosNotificationDetails =
    DarwinNotificationDetails(
      categoryIdentifier: darwinNotificationCategoryPlain,
    );




    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: iosNotificationDetails,
    );
    await flutterLocalNotificationsPlugin.show(
        id++, 'plain title', 'plain body', notificationDetails,
        payload: 'item z');
  }

  Future<void> _showNotificationWithTextAction() async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails(
      'your channel id',
      'your channel name',
      channelDescription: 'your channel description',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'text_id_1',
          'Enter Text',
          icon: DrawableResourceAndroidBitmap('food'),
          inputs: <AndroidNotificationActionInput>[
            AndroidNotificationActionInput(
              label: 'Enter a message',
            ),
          ],
        ),
      ],
    );

    const DarwinNotificationDetails darwinNotificationDetails =
    DarwinNotificationDetails(
      categoryIdentifier: darwinNotificationCategoryText,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: darwinNotificationDetails,
    );

    await flutterLocalNotificationsPlugin.show(id++, 'Text Input Notification',
        'Expand to see input action', notificationDetails,
        payload: 'item x');
  }

  Future<void> _showNotificationWithTextChoice() async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails(
      'your channel id',
      'your channel name',
      channelDescription: 'your channel description',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'text_id_2',
          'Action 2',
          icon: DrawableResourceAndroidBitmap('food'),
          inputs: <AndroidNotificationActionInput>[
            AndroidNotificationActionInput(
              choices: <String>['ABC', 'DEF'],
              allowFreeFormInput: false,
            ),
          ],
          contextual: true,
        ),
      ],
    );

    const DarwinNotificationDetails darwinNotificationDetails =
    DarwinNotificationDetails(
      categoryIdentifier: darwinNotificationCategoryText,
    );



    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: darwinNotificationDetails,
    );
    await flutterLocalNotificationsPlugin.show(
        id++, 'plain title', 'plain body', notificationDetails,
        payload: 'item x');
  }

  Future<void> _requestFullScreenIntentPermission() async {
    final bool permissionGranted = await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestFullScreenIntentPermission() ??
        false;
    await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          content: Text(
              'Full screen intent permission granted: $permissionGranted'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        ));
  }

  Future<void> _showFullScreenNotification() async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Turn off your screen'),
        content: const Text(
            'to see the full-screen intent in 5 seconds, press OK and TURN '
                'OFF your screen. Note that the full-screen intent permission must '
                'be granted for this to work too'),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await flutterLocalNotificationsPlugin.zonedSchedule(
                  0,
                  'scheduled title',
                  'scheduled body',
                  tz.TZDateTime.now(tz.local).add(const Duration(seconds: 5)),
                  const NotificationDetails(
                      android: AndroidNotificationDetails(
                          'full screen channel id', 'full screen channel name',
                          channelDescription: 'full screen channel description',
                          priority: Priority.high,
                          importance: Importance.high,
                          fullScreenIntent: true)),
                  androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle);

              Navigator.pop(context);
            },
            child: const Text('OK'),
          )
        ],
      ),
    );
  }

  Future<void> _showNotificationWithNoBody() async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails('your channel id', 'your channel name',
        channelDescription: 'your channel description',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker');
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
    );
    await flutterLocalNotificationsPlugin.show(
        id++, 'plain title', null, notificationDetails,
        payload: 'item x');
  }

  Future<void> _showNotificationWithNoTitle() async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails('your channel id', 'your channel name',
        channelDescription: 'your channel description',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker');
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
    );
    await flutterLocalNotificationsPlugin
        .show(id++, null, 'plain body', notificationDetails, payload: 'item x');
  }

  Future<void> _cancelNotification() async {
    await flutterLocalNotificationsPlugin.cancel(--id);
  }

  Future<void> _cancelNotificationWithTag() async {
    await flutterLocalNotificationsPlugin.cancel(--id, tag: 'tag');
  }

  Future<void> _showNotificationCustomSound() async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails(
      'your other channel id',
      'your other channel name',
      channelDescription: 'your other channel description',
      sound: RawResourceAndroidNotificationSound('slow_spring_board'),
    );
    const DarwinNotificationDetails darwinNotificationDetails =
    DarwinNotificationDetails(
      sound: 'slow_spring_board.aiff',
    );


    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: darwinNotificationDetails,
    );
    await flutterLocalNotificationsPlugin.show(
      id++,
      'custom sound notification title',
      'custom sound notification body',
      notificationDetails,
    );
  }

  Future<void> _showNotificationCustomVibrationIconLed() async {
    final Int64List vibrationPattern = Int64List(4);
    vibrationPattern[0] = 0;
    vibrationPattern[1] = 1000;
    vibrationPattern[2] = 5000;
    vibrationPattern[3] = 2000;

    final AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails(
        'other custom channel id', 'other custom channel name',
        channelDescription: 'other custom channel description',
        icon: 'secondary_icon',
        largeIcon: const DrawableResourceAndroidBitmap('sample_large_icon'),
        vibrationPattern: vibrationPattern,
        enableLights: true,
        color: const Color.fromARGB(255, 255, 0, 0),
        ledColor: const Color.fromARGB(255, 255, 0, 0),
        ledOnMs: 1000,
        ledOffMs: 500);

    final NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++,
        'title of notification with custom vibration pattern, LED and icon',
        'body of notification with custom vibration pattern, LED and icon',
        notificationDetails);
  }

  Future<void> _showNotificationWithNoSound() async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails('silent channel id', 'silent channel name',
        channelDescription: 'silent channel description',
        playSound: false,
        styleInformation: DefaultStyleInformation(true, true));
    const DarwinNotificationDetails darwinNotificationDetails =
    DarwinNotificationDetails(
      presentSound: false,
    );
    final NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: darwinNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++, '<b>silent</b> title', '<b>silent</b> body', notificationDetails);
  }

  Future<void> _showNotificationSilently() async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails('your channel id', 'your channel name',
        channelDescription: 'your channel description',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker',
        silent: true);
    const DarwinNotificationDetails darwinNotificationDetails =
    DarwinNotificationDetails(
      presentSound: false,
    );
    final NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: darwinNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++, '<b>silent</b> title', '<b>silent</b> body', notificationDetails);
  }

  Future<void> _showSoundUriNotification() async {
    /// this calls a method over a platform channel implemented within the
    /// example app to return the Uri for the default alarm sound and uses
    /// as the notification sound
    final String? alarmUri = await platform.invokeMethod<String>('getAlarmUri');
    final UriAndroidNotificationSound uriSound =
    UriAndroidNotificationSound(alarmUri!);
    final AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails('uri channel id', 'uri channel name',
        channelDescription: 'uri channel description',
        sound: uriSound,
        styleInformation: const DefaultStyleInformation(true, true));
    final NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++, 'uri sound title', 'uri sound body', notificationDetails);
  }

  Future<void> _showTimeoutNotification() async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails('silent channel id', 'silent channel name',
        channelDescription: 'silent channel description',
        timeoutAfter: 3000,
        styleInformation: DefaultStyleInformation(true, true));
    const NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(id++, 'timeout notification',
        'Times out after 3 seconds', notificationDetails);
  }

  Future<void> _showInsistentNotification() async {
    // This value is from: https://developer.android.com/reference/android/app/Notification.html#FLAG_INSISTENT
    const int insistentFlag = 4;
    final AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails('your channel id', 'your channel name',
        channelDescription: 'your channel description',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker',
        additionalFlags: Int32List.fromList(<int>[insistentFlag]));
    final NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++, 'insistent title', 'insistent body', notificationDetails,
        payload: 'item x');
  }

  Future<String> _downloadAndSaveFile(String url, String fileName) async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final String filePath = '${directory.path}/$fileName';
    final http.Response response = await http.get(Uri.parse(url));
    final File file = File(filePath);
    await file.writeAsBytes(response.bodyBytes);
    return filePath;
  }

  Future<void> _showBigPictureNotification() async {
    final String largeIconPath =
    await _downloadAndSaveFile('https://dummyimage.com/48x48', 'largeIcon');
    final String bigPicturePath = await _downloadAndSaveFile(
        'https://dummyimage.com/400x800', 'bigPicture');
    final BigPictureStyleInformation bigPictureStyleInformation =
    BigPictureStyleInformation(FilePathAndroidBitmap(bigPicturePath),
        largeIcon: FilePathAndroidBitmap(largeIconPath),
        contentTitle: 'overridden <b>big</b> content title',
        htmlFormatContentTitle: true,
        summaryText: 'summary <i>text</i>',
        htmlFormatSummaryText: true);
    final AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails(
        'big text channel id', 'big text channel name',
        channelDescription: 'big text channel description',
        styleInformation: bigPictureStyleInformation);
    final NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++, 'big text title', 'silent body', notificationDetails);
  }

  Future<String> _base64encodedImage(String url) async {
    final http.Response response = await http.get(Uri.parse(url));
    final String base64Data = base64Encode(response.bodyBytes);
    return base64Data;
  }

  Future<void> _showBigPictureNotificationBase64() async {
    final String largeIcon =
    await _base64encodedImage('https://dummyimage.com/48x48');
    final String bigPicture =
    await _base64encodedImage('https://dummyimage.com/400x800');

    final BigPictureStyleInformation bigPictureStyleInformation =
    BigPictureStyleInformation(
        ByteArrayAndroidBitmap.fromBase64String(
            bigPicture), //Base64AndroidBitmap(bigPicture),
        largeIcon: ByteArrayAndroidBitmap.fromBase64String(largeIcon),
        contentTitle: 'overridden <b>big</b> content title',
        htmlFormatContentTitle: true,
        summaryText: 'summary <i>text</i>',
        htmlFormatSummaryText: true);
    final AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails(
        'big text channel id', 'big text channel name',
        channelDescription: 'big text channel description',
        styleInformation: bigPictureStyleInformation);
    final NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++, 'big text title', 'silent body', notificationDetails);
  }

  Future<Uint8List> _getByteArrayFromUrl(String url) async {
    final http.Response response = await http.get(Uri.parse(url));
    return response.bodyBytes;
  }

  Future<void> _showBigPictureNotificationURL() async {
    final ByteArrayAndroidBitmap largeIcon = ByteArrayAndroidBitmap(
        await _getByteArrayFromUrl('https://dummyimage.com/48x48'));
    final ByteArrayAndroidBitmap bigPicture = ByteArrayAndroidBitmap(
        await _getByteArrayFromUrl('https://dummyimage.com/400x800'));

    final BigPictureStyleInformation bigPictureStyleInformation =
    BigPictureStyleInformation(bigPicture,
        largeIcon: largeIcon,
        contentTitle: 'overridden <b>big</b> content title',
        htmlFormatContentTitle: true,
        summaryText: 'summary <i>text</i>',
        htmlFormatSummaryText: true);
    final AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails(
        'big text channel id', 'big text channel name',
        channelDescription: 'big text channel description',
        styleInformation: bigPictureStyleInformation);
    final NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++, 'big text title', 'silent body', notificationDetails);
  }

  Future<void> _showBigPictureNotificationHiddenLargeIcon() async {
    final String largeIconPath =
    await _downloadAndSaveFile('https://dummyimage.com/48x48', 'largeIcon');
    final String bigPicturePath = await _downloadAndSaveFile(
        'https://dummyimage.com/400x800', 'bigPicture');
    final BigPictureStyleInformation bigPictureStyleInformation =
    BigPictureStyleInformation(FilePathAndroidBitmap(bigPicturePath),
        hideExpandedLargeIcon: true,
        contentTitle: 'overridden <b>big</b> content title',
        htmlFormatContentTitle: true,
        summaryText: 'summary <i>text</i>',
        htmlFormatSummaryText: true);
    final AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails(
        'big text channel id', 'big text channel name',
        channelDescription: 'big text channel description',
        largeIcon: FilePathAndroidBitmap(largeIconPath),
        styleInformation: bigPictureStyleInformation);
    final NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++, 'big text title', 'silent body', notificationDetails);
  }

  Future<void> _showNotificationMediaStyle() async {
    final String largeIconPath = await _downloadAndSaveFile(
        'https://dummyimage.com/128x128/00FF00/000000', 'largeIcon');
    final AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails(
      'media channel id',
      'media channel name',
      channelDescription: 'media channel description',
      largeIcon: FilePathAndroidBitmap(largeIconPath),
      styleInformation: const MediaStyleInformation(),
    );
    final NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++, 'notification title', 'notification body', notificationDetails);
  }

  Future<void> _showBigTextNotification() async {
    const BigTextStyleInformation bigTextStyleInformation =
    BigTextStyleInformation(
      'Lorem <i>ipsum dolor sit</i> amet, consectetur <b>adipiscing elit</b>, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.',
      htmlFormatBigText: true,
      contentTitle: 'overridden <b>big</b> content title',
      htmlFormatContentTitle: true,
      summaryText: 'summary <i>text</i>',
      htmlFormatSummaryText: true,
    );
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails(
        'big text channel id', 'big text channel name',
        channelDescription: 'big text channel description',
        styleInformation: bigTextStyleInformation);
    const NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++, 'big text title', 'silent body', notificationDetails);
  }

  Future<void> _showInboxNotification() async {
    final List<String> lines = <String>['line <b>1</b>', 'line <i>2</i>'];
    final InboxStyleInformation inboxStyleInformation = InboxStyleInformation(
        lines,
        htmlFormatLines: true,
        contentTitle: 'overridden <b>inbox</b> context title',
        htmlFormatContentTitle: true,
        summaryText: 'summary <i>text</i>',
        htmlFormatSummaryText: true);
    final AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails('inbox channel id', 'inboxchannel name',
        channelDescription: 'inbox channel description',
        styleInformation: inboxStyleInformation);
    final NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++, 'inbox title', 'inbox body', notificationDetails);
  }

  Future<void> _showMessagingNotification() async {
    // use a platform channel to resolve an Android drawable resource to a URI.
    // This is NOT part of the notifications plugin. Calls made over this
    /// channel is handled by the app
    final String? imageUri =
    await platform.invokeMethod('drawableToUri', 'food');

    /// First two person objects will use icons that part of the Android app's
    /// drawable resources
    const Person me = Person(
      name: 'Me',
      key: '1',
      uri: 'tel:1234567890',
      icon: DrawableResourceAndroidIcon('me'),
    );
    const Person coworker = Person(
      name: 'Coworker',
      key: '2',
      uri: 'tel:9876543210',
      icon: FlutterBitmapAssetAndroidIcon('icons/coworker.png'),
    );
    // download the icon that would be use for the lunch bot person
    final String largeIconPath =
    await _downloadAndSaveFile('https://dummyimage.com/48x48', 'largeIcon');
    // this person object will use an icon that was downloaded
    final Person lunchBot = Person(
      name: 'Lunch bot',
      key: 'bot',
      bot: true,
      icon: BitmapFilePathAndroidIcon(largeIconPath),
    );
    final Person chef = Person(
        name: 'Master Chef',
        key: '3',
        uri: 'tel:111222333444',
        icon: ByteArrayAndroidIcon.fromBase64String(
            await _base64encodedImage('https://placekitten.com/48/48')));

    final List<Message> messages = <Message>[
      Message('Hi', DateTime.now(), null),
      Message("What's up?", DateTime.now().add(const Duration(minutes: 5)),
          coworker),
      Message('Lunch?', DateTime.now().add(const Duration(minutes: 10)), null,
          dataMimeType: 'image/png', dataUri: imageUri),
      Message('What kind of food would you prefer?',
          DateTime.now().add(const Duration(minutes: 10)), lunchBot),
      Message('You do not have time eat! Keep working!',
          DateTime.now().add(const Duration(minutes: 11)), chef),
    ];
    final MessagingStyleInformation messagingStyle = MessagingStyleInformation(
        me,
        groupConversation: true,
        conversationTitle: 'Team lunch',
        htmlFormatContent: true,
        htmlFormatTitle: true,
        messages: messages);
    final AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails('message channel id', 'message channel name',
        channelDescription: 'message channel description',
        category: AndroidNotificationCategory.message,
        styleInformation: messagingStyle);
    final NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id, 'message title', 'message body', notificationDetails);

    // wait 10 seconds and add another message to simulate another response
    await Future<void>.delayed(const Duration(seconds: 10), () async {
      messages.add(Message("I'm so sorry!!! But I really like thai food ...",
          DateTime.now().add(const Duration(minutes: 11)), null));
      await flutterLocalNotificationsPlugin.show(
          id++, 'message title', 'message body', notificationDetails);
    });
  }

  Future<void> _showGroupedNotifications() async {
    const String groupKey = 'com.android.example.WORK_EMAIL';
    const String groupChannelId = 'grouped channel id';
    const String groupChannelName = 'grouped channel name';
    const String groupChannelDescription = 'grouped channel description';
    // example based on https://developer.android.com/training/notify-user/group.html
    const AndroidNotificationDetails firstNotificationAndroidSpecifics =
    AndroidNotificationDetails(groupChannelId, groupChannelName,
        channelDescription: groupChannelDescription,
        importance: Importance.max,
        priority: Priority.high,
        groupKey: groupKey);
    const NotificationDetails firstNotificationPlatformSpecifics =
    NotificationDetails(android: firstNotificationAndroidSpecifics);
    await flutterLocalNotificationsPlugin.show(id++, 'Alex Faarborg',
        'You will not believe...', firstNotificationPlatformSpecifics);
    const AndroidNotificationDetails secondNotificationAndroidSpecifics =
    AndroidNotificationDetails(groupChannelId, groupChannelName,
        channelDescription: groupChannelDescription,
        importance: Importance.max,
        priority: Priority.high,
        groupKey: groupKey);
    const NotificationDetails secondNotificationPlatformSpecifics =
    NotificationDetails(android: secondNotificationAndroidSpecifics);
    await flutterLocalNotificationsPlugin.show(
        id++,
        'Jeff Chang',
        'Please join us to celebrate the...',
        secondNotificationPlatformSpecifics);

    // Create the summary notification to support older devices that pre-date
    /// Android 7.0 (API level 24).
    ///
    /// Recommended to create this regardless as the behaviour may vary as
    /// mentioned in https://developer.android.com/training/notify-user/group
    const List<String> lines = <String>[
      'Alex Faarborg  Check this out',
      'Jeff Chang    Launch Party'
    ];
    const InboxStyleInformation inboxStyleInformation = InboxStyleInformation(
        lines,
        contentTitle: '2 messages',
        summaryText: 'janedoe@example.com');
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails(groupChannelId, groupChannelName,
        channelDescription: groupChannelDescription,
        styleInformation: inboxStyleInformation,
        groupKey: groupKey,
        setAsGroupSummary: true);
    const NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++, 'Attention', 'Two messages', notificationDetails);
  }

  Future<void> _showNotificationWithTag() async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails('your channel id', 'your channel name',
        channelDescription: 'your channel description',
        importance: Importance.max,
        priority: Priority.high,
        tag: 'tag');
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
    );
    await flutterLocalNotificationsPlugin.show(
        id++, 'first notification', null, notificationDetails);
  }

  Future<void> _cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }

  Future<void> _showOngoingNotification() async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails('your channel id', 'your channel name',
        channelDescription: 'your channel description',
        importance: Importance.max,
        priority: Priority.high,
        ongoing: true,
        autoCancel: false);
    const NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++,
        'ongoing notification title',
        'ongoing notification body',
        notificationDetails);
  }

  Future<void> _showNotificationWithNoBadge() async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails('no badge channel', 'no badge name',
        channelDescription: 'no badge description',
        channelShowBadge: false,
        importance: Importance.max,
        priority: Priority.high,
        onlyAlertOnce: true);
    const NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++, 'no badge title', 'no badge body', notificationDetails,
        payload: 'item x');
  }

  Future<void> _showProgressNotification() async {
    id++;
    final int progressId = id;
    const int maxProgress = 5;
    for (int i = 0; i <= maxProgress; i++) {
      await Future<void>.delayed(const Duration(seconds: 1), () async {
        final AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails('progress channel', 'progress channel',
            channelDescription: 'progress channel description',
            channelShowBadge: false,
            importance: Importance.max,
            priority: Priority.high,
            onlyAlertOnce: true,
            showProgress: true,
            maxProgress: maxProgress,
            progress: i);
        final NotificationDetails notificationDetails =
        NotificationDetails(android: androidNotificationDetails);
        await flutterLocalNotificationsPlugin.show(
            progressId,
            'progress notification title',
            'progress notification body',
            notificationDetails,
            payload: 'item x');
      });
    }
  }

  Future<void> _showIndeterminateProgressNotification() async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails(
        'indeterminate progress channel', 'indeterminate progress channel',
        channelDescription: 'indeterminate progress channel description',
        channelShowBadge: false,
        importance: Importance.max,
        priority: Priority.high,
        onlyAlertOnce: true,
        showProgress: true,
        indeterminate: true);
    const NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++,
        'indeterminate progress notification title',
        'indeterminate progress notification body',
        notificationDetails,
        payload: 'item x');
  }

  Future<void> _showNotificationUpdateChannelDescription() async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails('your channel id', 'your channel name',
        channelDescription: 'your updated channel description',
        importance: Importance.max,
        priority: Priority.high,
        channelAction: AndroidNotificationChannelAction.update);
    const NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++,
        'updated notification channel',
        'check settings to see updated channel description',
        notificationDetails,
        payload: 'item x');
  }

  Future<void> _showPublicNotification() async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails('your channel id', 'your channel name',
        channelDescription: 'your channel description',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker',
        visibility: NotificationVisibility.public);
    const NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++,
        'public notification title',
        'public notification body',
        notificationDetails,
        payload: 'item x');
  }

  Future<void> _showNotificationWithSubtitle() async {
    const DarwinNotificationDetails darwinNotificationDetails =
    DarwinNotificationDetails(
      subtitle: 'the subtitle',
    );
    const NotificationDetails notificationDetails = NotificationDetails(
        iOS: darwinNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++,
        'title of notification with a subtitle',
        'body of notification with a subtitle',
        notificationDetails,
        payload: 'item x');
  }

  Future<void> _showNotificationWithIconBadge() async {
    const DarwinNotificationDetails darwinNotificationDetails =
    DarwinNotificationDetails(badgeNumber: 1);
    const NotificationDetails notificationDetails = NotificationDetails(
        iOS: darwinNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++, 'icon badge title', 'icon badge body', notificationDetails,
        payload: 'item x');
  }

  Future<void> _showNotificationsWithThreadIdentifier() async {
    NotificationDetails buildNotificationDetailsForThread(
        String threadIdentifier,
        ) {
      final DarwinNotificationDetails darwinNotificationDetails =
      DarwinNotificationDetails(
        threadIdentifier: threadIdentifier,
      );
      return NotificationDetails(
          iOS: darwinNotificationDetails);
    }

    final NotificationDetails thread1PlatformChannelSpecifics =
    buildNotificationDetailsForThread('thread1');
    final NotificationDetails thread2PlatformChannelSpecifics =
    buildNotificationDetailsForThread('thread2');

    await flutterLocalNotificationsPlugin.show(id++, 'thread 1',
        'first notification', thread1PlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(id++, 'thread 1',
        'second notification', thread1PlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(id++, 'thread 1',
        'third notification', thread1PlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(id++, 'thread 2',
        'first notification', thread2PlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(id++, 'thread 2',
        'second notification', thread2PlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(id++, 'thread 2',
        'third notification', thread2PlatformChannelSpecifics);
  }

  Future<void> _showNotificationWithTimeSensitiveInterruptionLevel() async {
    const DarwinNotificationDetails darwinNotificationDetails =
    DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
    );
    const NotificationDetails notificationDetails = NotificationDetails(
        iOS: darwinNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++,
        'title of time sensitive notification',
        'body of time sensitive notification',
        notificationDetails,
        payload: 'item x');
  }

  Future<void> _showNotificationWithBannerNotInNotificationCentre() async {
    const DarwinNotificationDetails darwinNotificationDetails =
    DarwinNotificationDetails(
      presentBanner: true,
      presentList: false,
    );
    const NotificationDetails notificationDetails = NotificationDetails(
        iOS: darwinNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++,
        'title of banner notification',
        'body of banner notification',
        notificationDetails,
        payload: 'item x');
  }

  Future<void> _showNotificationInNotificationCentreOnly() async {
    const DarwinNotificationDetails darwinNotificationDetails =
    DarwinNotificationDetails(
      presentBanner: false,
      presentList: true,
    );
    const NotificationDetails notificationDetails = NotificationDetails(
        iOS: darwinNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++,
        'title of notification shown only in notification centre',
        'body of notification shown only in notification centre',
        notificationDetails,
        payload: 'item x');
  }

  Future<void> _showNotificationWithoutTimestamp() async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails('your channel id', 'your channel name',
        channelDescription: 'your channel description',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: false);
    const NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++, 'plain title', 'plain body', notificationDetails,
        payload: 'item x');
  }

  Future<void> _showNotificationWithCustomTimestamp() async {
    final AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails(
      'your channel id',
      'your channel name',
      channelDescription: 'your channel description',
      importance: Importance.max,
      priority: Priority.high,
      when: DateTime.now().millisecondsSinceEpoch - 120 * 1000,
    );
    final NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++, 'plain title', 'plain body', notificationDetails,
        payload: 'item x');
  }

  Future<void> _showNotificationWithCustomSubText() async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails(
      'your channel id',
      'your channel name',
      channelDescription: 'your channel description',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
      subText: 'custom subtext',
    );
    const NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++, 'plain title', 'plain body', notificationDetails,
        payload: 'item x');
  }

  Future<void> _showNotificationWithChronometer() async {
    final AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails(
      'your channel id',
      'your channel name',
      channelDescription: 'your channel description',
      importance: Importance.max,
      priority: Priority.high,
      when: DateTime.now().millisecondsSinceEpoch - 120 * 1000,
      usesChronometer: true,
      chronometerCountDown: true,
    );
    final NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++, 'plain title', 'plain body', notificationDetails,
        payload: 'item x');
  }

  Future<void> _showNotificationWithClippedThumbnailAttachment() async {
    final String bigPicturePath = await _downloadAndSaveFile(
        'https://dummyimage.com/600x200', 'bigPicture.jpg');
    final DarwinNotificationDetails darwinNotificationDetails =
    DarwinNotificationDetails(
      attachments: <DarwinNotificationAttachment>[
        DarwinNotificationAttachment(
          bigPicturePath,
          thumbnailClippingRect:
          // lower right quadrant of the attachment
          const DarwinNotificationAttachmentThumbnailClippingRect(
            x: 0.5,
            y: 0.5,
            height: 0.5,
            width: 0.5,
          ),
        )
      ],
    );
    final NotificationDetails notificationDetails = NotificationDetails(
        iOS: darwinNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++,
        'notification with attachment title',
        'notification with attachment body',
        notificationDetails);
  }

  Future<void> _createNotificationChannelGroup() async {
    const String channelGroupId = 'your channel group id';
    // create the group first
    const AndroidNotificationChannelGroup androidNotificationChannelGroup =
    AndroidNotificationChannelGroup(
        channelGroupId, 'your channel group name',
        description: 'your channel group description');
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()!
        .createNotificationChannelGroup(androidNotificationChannelGroup);

    // create channels associated with the group
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()!
        .createNotificationChannel(const AndroidNotificationChannel(
        'grouped channel id 1', 'grouped channel name 1',
        description: 'grouped channel description 1',
        groupId: channelGroupId));

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()!
        .createNotificationChannel(const AndroidNotificationChannel(
        'grouped channel id 2', 'grouped channel name 2',
        description: 'grouped channel description 2',
        groupId: channelGroupId));

    await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          content: Text('Channel group with name '
              '${androidNotificationChannelGroup.name} created'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        ));
  }

  Future<void> _deleteNotificationChannelGroup() async {
    const String channelGroupId = 'your channel group id';
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.deleteNotificationChannelGroup(channelGroupId);

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        content: const Text('Channel group with id $channelGroupId deleted'),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _startForegroundService() async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails('your channel id', 'your channel name',
        channelDescription: 'your channel description',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker');
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.startForegroundService(1, 'plain title', 'plain body',
        notificationDetails: androidNotificationDetails, payload: 'item x');
  }

  Future<void> _startForegroundServiceWithBlueBackgroundNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'your channel id',
      'your channel name',
      channelDescription: 'color background channel description',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      color: Colors.blue,
      colorized: true,
    );

    /// only using foreground service can color the background
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.startForegroundService(
        1, 'colored background text title', 'colored background text body',
        notificationDetails: androidPlatformChannelSpecifics,
        payload: 'item x');
  }

  Future<void> _stopForegroundService() async {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.stopForegroundService();
  }

  Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel androidNotificationChannel =
    AndroidNotificationChannel(
      'your channel id 2',
      'your channel name 2',
      description: 'your channel description 2',
    );
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidNotificationChannel);

    await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          content:
          Text('Channel with name ${androidNotificationChannel.name} '
              'created'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        ));
  }

  Future<void> _areNotifcationsEnabledOnAndroid() async {
    final bool? areEnabled = await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.areNotificationsEnabled();
    await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          content: Text(areEnabled == null
              ? 'ERROR: received null'
              : (areEnabled
              ? 'Notifications are enabled'
              : 'Notifications are NOT enabled')),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        ));
  }

  Future<void> _checkNotificationsOnCupertino() async {
    final NotificationsEnabledOptions? isEnabled =
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
            ?.checkPermissions();
    final String isEnabledString = isEnabled == null
        ? 'ERROR: received null'
        : '''
    isEnabled: ${isEnabled.isEnabled}
    isSoundEnabled: ${isEnabled.isSoundEnabled}
    isAlertEnabled: ${isEnabled.isAlertEnabled}
    isBadgeEnabled: ${isEnabled.isBadgeEnabled}
    isProvisionalEnabled: ${isEnabled.isProvisionalEnabled}
    isCriticalEnabled: ${isEnabled.isCriticalEnabled}
    ''';
    await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          content: Text(isEnabledString),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        ));
  }

  Future<void> _deleteNotificationChannel() async {
    const String channelId = 'your channel id 2';
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.deleteNotificationChannel(channelId);

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        content: const Text('Channel with id $channelId deleted'),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _getNotificationChannels() async {
    final Widget notificationChannelsDialogContent =
    await _getNotificationChannelsDialogContent();
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        content: notificationChannelsDialogContent,
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<Widget> _getNotificationChannelsDialogContent() async {
    try {
      final List<AndroidNotificationChannel>? channels =
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()!
          .getNotificationChannels();

      return SizedBox(
        width: double.maxFinite,
        child: ListView(
          children: <Widget>[
            const Text(
              'Notifications Channels',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Divider(color: Colors.black),
            if (channels?.isEmpty ?? true)
              const Text('No notification channels')
            else
              for (final AndroidNotificationChannel channel in channels!)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('id: ${channel.id}\n'
                        'name: ${channel.name}\n'
                        'description: ${channel.description}\n'
                        'groupId: ${channel.groupId}\n'
                        'importance: ${channel.importance.value}\n'
                        'playSound: ${channel.playSound}\n'
                        'sound: ${channel.sound?.sound}\n'
                        'enableVibration: ${channel.enableVibration}\n'
                        'vibrationPattern: ${channel.vibrationPattern}\n'
                        'showBadge: ${channel.showBadge}\n'
                        'enableLights: ${channel.enableLights}\n'
                        'ledColor: ${channel.ledColor}\n'
                        'audioAttributesUsage: ${channel.audioAttributesUsage}\n'),
                    const Divider(color: Colors.black),
                  ],
                ),
          ],
        ),
      );
    } on PlatformException catch (error) {
      return Text(
        'Error calling "getNotificationChannels"\n'
            'code: ${error.code}\n'
            'message: ${error.message}',
      );
    }
  }

  Future<void> _showNotificationWithNumber() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails('your channel id', 'your channel name',
        channelDescription: 'your channel description',
        importance: Importance.max,
        priority: Priority.high,
        number: 1);
    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(
        0, 'icon badge title', 'icon badge body', platformChannelSpecifics,
        payload: 'item x');
  }

  Future<void> _showNotificationWithAudioAttributeAlarm() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'your alarm channel id',
      'your alarm channel name',
      channelDescription: 'your alarm channel description',
      importance: Importance.max,
      priority: Priority.high,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );
    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(
      0,
      'notification sound controlled by alarm volume',
      'alarm notification sound body',
      platformChannelSpecifics,
    );
  }

  Future<void> _showNotificationWithCriticalSound() async {
    const DarwinNotificationDetails darwinNotificationDetails =
    DarwinNotificationDetails(
      // Between 0.0 and 1.0
      criticalSoundVolume: 0.5,
      // If sound is not specified, the default sound will be used
      sound: 'slow_spring_board.aiff',
    );
    const NotificationDetails notificationDetails = NotificationDetails(
      iOS: darwinNotificationDetails,
    );
    await flutterLocalNotificationsPlugin.show(
      id++,
      'Critical sound notification title',
      'Critical sound notification body',
      notificationDetails,
    );
  }
}

class SecondPage extends StatefulWidget {
  const SecondPage(
      this.payload, {
        this.data,
        super.key,
      });

  static const String routeName = '/secondPage';

  final String? payload;
  final Map<String, dynamic>? data;

  @override
  State<StatefulWidget> createState() => SecondPageState();
}

class SecondPageState extends State<SecondPage> {
  String? _payload;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _payload = widget.payload;
    _data = widget.data;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Second Screen'),
    ),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('payload ${_payload ?? ''}'),
          Text('data ${_data ?? ''}'),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Go back!'),
          ),
        ],
      ),
    ),
  );
}

class _InfoValueString extends StatelessWidget {
  const _InfoValueString({
    required this.title,
    required this.value,
  });

  final String title;
  final Object? value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
    child: Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: '$title ',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(
            text: '$value',
          )
        ],
      ),
    ),
  );
}