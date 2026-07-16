import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Handles daily motivational finance reminder notifications.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int _dailyNotificationId = 1001;
  static const String _channelId = 'brightledger_daily';
  static const String _channelName = 'Daily Reminders';
  static const String _channelDesc =
      'Motivational finance tips and reminders to help you spend wisely.';

  /// Motivational finance quotes shown in daily reminders
  static const List<String> _quotes = [
    '💡 A penny saved is a penny earned. Check your budget today!',
    '📊 Track every ringgit — small leaks sink big ships.',
    '🎯 Set a savings goal this week and stick to it!',
    '☕ Think before you spend: need or want?',
    '💸 Avoid impulse buys. Sleep on it for 24 hours first.',
    '🌱 Investing RM10 today can be worth much more tomorrow.',
    '🧾 Scan your receipts to stay on top of spending.',
    '💰 Pay yourself first — save before you spend.',
    '📉 Review your subscriptions. Cancel what you don\'t use!',
    '🚀 Financial freedom starts with one good habit at a time.',
    '🛒 Shop with a list. It saves both time and money.',
    '🔍 Where did your money go last week? Review your records!',
    '💪 Being frugal isn\'t being cheap — it\'s being smart.',
    '📅 30-day rule: wait a month before big non-essential purchases.',
    '🌟 Every RM you save today is a future version of you saying thank you!',
  ];

  /// Initialize the notification plugin and request permissions.
  Future<void> initialize() async {
    tz.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (details) {
        debugPrint('Notification tapped: ${details.payload}');
      },
    );

    await _createNotificationChannel();
    await _requestPermission();
  }

  /// Creates the Android notification channel (required on Android 8+).
  Future<void> _createNotificationChannel() async {
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.defaultImportance,
      enableLights: true,
      enableVibration: true,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Requests POST_NOTIFICATIONS permission on Android 13+.
  Future<void> _requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      debugPrint('Notification permission granted: $granted');
    }
  }

  /// Schedules a daily notification at [hour]:[minute] (24h).
  /// Default is 9:00 AM.
  Future<void> scheduleDailyReminder({int hour = 9, int minute = 0}) async {
    await _plugin.cancelAll(); // Clear any existing scheduled notifications

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    // If the scheduled time has already passed today, schedule for tomorrow
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id: _dailyNotificationId,
      title: '💸 BrightLedger Daily Tip',
      body: _randomQuote(),
      scheduledDate: scheduledDate,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: '@mipmap/launcher_icon',
          styleInformation: BigTextStyleInformation(_randomQuote()),
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // Repeats daily
    );

    debugPrint('Daily reminder scheduled for $hour:$minute');
  }

  /// Shows an immediate test notification (useful for debugging).
  Future<void> showTestNotification() async {
    await _plugin.show(
      id: 0,
      title: '💸 BrightLedger',
      body: _randomQuote(),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/launcher_icon',
        ),
      ),
    );
  }

  /// Cancels all scheduled notifications.
  Future<void> cancelAll() => _plugin.cancelAll();

  String _randomQuote() {
    final idx = Random().nextInt(_quotes.length);
    return _quotes[idx];
  }
}
