import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class ReminderNotificationService {
  ReminderNotificationService._();

  static final ReminderNotificationService instance =
      ReminderNotificationService._();

  static const _dailyScheduleNotificationId = 1001;
  static const _testNotificationId = 1002;
  static const _channelId = 'policy_reminder_channel';
  static const _channelName = '保單提醒';
  static const _channelDescription = '保費繳納與保單到期提醒';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _timeZoneConfigured = false;

  Future<void> _configureLocalTimeZone() async {
    if (_timeZoneConfigured) return;
    tzdata.initializeTimeZones();
    try {
      final timezoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneName.identifier));
    } catch (_) {
      // Keep default timezone if platform lookup is unavailable.
    }
    _timeZoneConfigured = true;
  }

  NotificationDetails get _notificationDetails {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );
  }

  Future<bool> initialize() async {
    if (_initialized) return true;
    await _configureLocalTimeZone();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    try {
      await _plugin.initialize(settings: settings);
      _initialized = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestPermissions() async {
    if (!await initialize()) return false;

    try {
      final permissionResults = <bool>[];

      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final androidGranted = await android?.requestNotificationsPermission();
      if (androidGranted != null) {
        permissionResults.add(androidGranted);
      }

      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final iosGranted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      if (iosGranted != null) {
        permissionResults.add(iosGranted);
      }

      final macos = _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      final macosGranted = await macos?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      if (macosGranted != null) {
        permissionResults.add(macosGranted);
      }

      if (permissionResults.isEmpty) return true;
      return permissionResults.any((isGranted) => isGranted);
    } catch (_) {
      return false;
    }
  }

  tz.TZDateTime _nextNineAM() {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, 9);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  Future<bool> scheduleDailyReminderAtNineAM({
    required int total,
    required int paymentCount,
    required int expiryCount,
    required String sample,
  }) async {
    if (!await initialize()) return false;
    if (total <= 0) return false;

    final body =
        '$sample${total > 1 ? '，另有 ${total - 1} 筆提醒' : ''}'
        '（繳費 $paymentCount / 到期 $expiryCount）';

    try {
      await _plugin.zonedSchedule(
        id: _dailyScheduleNotificationId,
        scheduledDate: _nextNineAM(),
        title: '每日保單提醒（09:00）',
        body: body,
        notificationDetails: _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancelDailyReminderSchedule() async {
    if (!await initialize()) return;
    try {
      await _plugin.cancel(id: _dailyScheduleNotificationId);
    } catch (_) {
      // No-op when scheduling isn't available.
    }
  }

  Future<bool> showTestNotification() async {
    if (!await initialize()) return false;

    try {
      await _plugin.show(
        id: _testNotificationId,
        title: '保單提醒測試',
        body: '系統通知已啟用，之後會自動推送近期繳費與到期提醒。',
        notificationDetails: _notificationDetails,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
