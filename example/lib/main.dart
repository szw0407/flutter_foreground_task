import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

void main() {
  FlutterForegroundTask.initCommunicationPort();
  runApp(const ExampleApp());
}

// ==================== Foreground Service Callback ====================

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

class MyTaskHandler extends TaskHandler {
  static const String incrementCountCommand = 'incrementCount';

  int _count = 0;

  void _incrementCount() {
    _count++;

    FlutterForegroundTask.updateService(
      notificationTitle: 'Hello MyTaskHandler :)',
      notificationText: 'count: $_count',
    );

    FlutterForegroundTask.sendDataToMain(_count);
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('onStart(starter: ${starter.name})');
    _incrementCount();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _incrementCount();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    print('onDestroy(isTimeout: $isTimeout)');
  }

  @override
  void onReceiveData(Object data) {
    print('onReceiveData: $data');
    if (data == incrementCountCommand) {
      _incrementCount();
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    print('onNotificationButtonPressed: $id');
  }

  @override
  void onNotificationPressed() {
    print('onNotificationPressed');
  }

  @override
  void onNotificationDismissed() {
    print('onNotificationDismissed');
  }
}

// ==================== Continued Processing Task Callback ====================

@pragma('vm:entry-point')
void continuedProcessingCallback() {
  FlutterForegroundTask.setTaskHandler(ContinuedProcessingHandler());
}

class ContinuedProcessingHandler extends TaskHandler {
  int _eventCount = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _eventCount = 0;
    print('[CP] onStart(starter: ${starter.name})');
    FlutterForegroundTask.sendDataToMain({
      'type': 'onStart',
      'starter': starter.name,
      'timestamp': timestamp.toIso8601String(),
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _eventCount++;
    print('[CP] onRepeatEvent #$_eventCount');
    FlutterForegroundTask.sendDataToMain({
      'type': 'onRepeatEvent',
      'count': _eventCount,
      'timestamp': timestamp.toIso8601String(),
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    print('[CP] onDestroy(isTimeout: $isTimeout, eventCount: $_eventCount)');
    FlutterForegroundTask.sendDataToMain({
      'type': 'onDestroy',
      'isTimeout': isTimeout,
      'eventCount': _eventCount,
      'timestamp': timestamp.toIso8601String(),
    });
  }

  @override
  void onReceiveData(Object data) {
    print('[CP] onReceiveData: $data');
    FlutterForegroundTask.sendDataToMain({
      'type': 'onReceiveData',
      'data': data,
    });
  }

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}
}

// ============================== App UI ==============================

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      routes: {
        '/': (context) => const ExamplePage(),
        '/second': (context) => const SecondPage(),
      },
      initialRoute: '/',
    );
  }
}

class ExamplePage extends StatefulWidget {
  const ExamplePage({super.key});

  @override
  State<StatefulWidget> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  final ValueNotifier<Object?> _taskDataListenable = ValueNotifier(null);
  final ValueNotifier<Object?> _cpDataListenable = ValueNotifier(null);

  // ===================== Permissions & Init =====================

  Future<void> _requestPermissions() async {
    final NotificationPermission notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (Platform.isAndroid) {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }

      if (!await FlutterForegroundTask.canScheduleExactAlarms) {
        await FlutterForegroundTask.openAlarmsAndRemindersSettings();
      }
    }
  }

  void _initService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'foreground_service',
        channelName: 'Foreground Service Notification',
        channelDescription:
            'This notification appears when the foreground service is running.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  // =================== Foreground Service ===================

  Future<ServiceRequestResult> _startService() async {
    if (await FlutterForegroundTask.isRunningService) {
      return FlutterForegroundTask.restartService();
    } else {
      return FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'Foreground Service is running',
        notificationText: 'Tap to return to the app',
        notificationIcon: null,
        notificationButtons: [
          const NotificationButton(id: 'btn_hello', text: 'hello'),
        ],
        notificationInitialRoute: '/second',
        callback: startCallback,
      );
    }
  }

  Future<ServiceRequestResult> _stopService() {
    return FlutterForegroundTask.stopService();
  }

  void _incrementCount() {
    FlutterForegroundTask.sendDataToTask(MyTaskHandler.incrementCountCommand);
  }

  // ============== Continued Processing Task ==============

  Future<void> _startContinuedProcessingTask() async {
    if (!await FlutterForegroundTask.isContinuedProcessingTaskSupported) {
      _cpDataListenable.value = {
        'type': 'error',
        'message': 'BGContinuedProcessingTask not supported on this device',
      };
      return;
    }

    await FlutterForegroundTask.startContinuedProcessingTask(
      options: const ContinuedProcessingTaskOptions(
        title: 'Processing Data',
        subtitle: 'Task is running...',
        requiresGPU: false,
        submissionStrategy: ContinuedProcessingSubmissionStrategy.queue,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
      ),
      callback: continuedProcessingCallback,
    );

    _cpDataListenable.value = {
      'type': 'submitted',
      'message':
          'Task submitted to system scheduler. It will run when the system decides.',
    };
  }

  Future<void> _stopContinuedProcessingTask() async {
    if (!await FlutterForegroundTask.isRunningContinuedProcessingTask) {
      _cpDataListenable.value = {
        'type': 'error',
        'message': 'No continued processing task is running',
      };
      return;
    }

    await FlutterForegroundTask.stopContinuedProcessingTask();
    _cpDataListenable.value = {
      'type': 'stopped',
      'message': 'Continued processing task stopped',
    };
  }

  // ==================== Data Callbacks ====================

  void _onReceiveTaskData(Object data) {
    print('onReceiveTaskData: $data');
    _taskDataListenable.value = data;
    _cpDataListenable.value = data;
  }

  // ===================== Lifecycle =====================

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissions();
      _initService();
    });
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    _taskDataListenable.dispose();
    _cpDataListenable.dispose();
    super.dispose();
  }

  // ===================== UI Build =====================

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter Foreground Task'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildForegroundServiceSection(),
                const Divider(height: 1, thickness: 1),
                _buildContinuedProcessingSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============ Foreground Service Section ============

  Widget _buildForegroundServiceSection() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Foreground Service',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          ValueListenableBuilder(
            valueListenable: _taskDataListenable,
            builder: (context, data, _) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Task Data:', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('$data',
                        style: Theme.of(context).textTheme.headlineSmall),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                    onPressed: _startService,
                    child: const Text('start service')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                    onPressed: _stopService, child: const Text('stop service')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                    onPressed: _incrementCount,
                    child: const Text('increment count')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============ Continued Processing Section ============

  Widget _buildContinuedProcessingSection() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('BGContinuedProcessingTask (iOS 26+)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildStatusRow(
            'isContinuedProcessingTaskSupported',
            'isContinuedProcessingTaskSupported',
          ),
          _buildStatusRow(
            'isGPUResourceSupported',
            'isGPUResourceSupported',
          ),
          _buildStatusRow(
            'isRunningContinuedProcessingTask',
            'isRunningContinuedProcessingTask',
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder(
            valueListenable: _cpDataListenable,
            builder: (context, data, _) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Events:', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('$data', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _startContinuedProcessingTask,
                  child: const Text('start CP Task'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _stopContinuedProcessingTask,
                  child: const Text('stop CP Task'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String getter) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: FutureBuilder<bool>(
        future: _resolveStatus(getter),
        builder: (context, snapshot) {
          final value = snapshot.data;
          return Row(
            children: [
              Expanded(
                  child:
                      Text('$label: ', style: const TextStyle(fontSize: 13))),
              Text(
                value == null
                    ? '...'
                    : value
                        ? 'true'
                        : 'false',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: value == true ? Colors.green : Colors.red.shade300,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _resolveStatus(String getter) async {
    switch (getter) {
      case 'isContinuedProcessingTaskSupported':
        return FlutterForegroundTask.isContinuedProcessingTaskSupported;
      case 'isGPUResourceSupported':
        return FlutterForegroundTask.isGPUResourceSupported;
      case 'isRunningContinuedProcessingTask':
        return FlutterForegroundTask.isRunningContinuedProcessingTask;
      default:
        return false;
    }
  }
}

class SecondPage extends StatelessWidget {
  const SecondPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Second Page'),
        centerTitle: true,
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: Navigator.of(context).pop,
          child: const Text('pop this page'),
        ),
      ),
    );
  }
}
