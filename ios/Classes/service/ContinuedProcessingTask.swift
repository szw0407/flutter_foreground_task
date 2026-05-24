//
//  ContinuedProcessingTask.swift
//  flutter_foreground_task
//

import BackgroundTasks
import Flutter
import Foundation

private let BG_ISOLATE_NAME = "flutter_foreground_task/continuedProcessingIsolate"
private let BG_CHANNEL_NAME = "flutter_foreground_task/background"

private let ACTION_TASK_START = "onStart"
private let ACTION_TASK_REPEAT_EVENT = "onRepeatEvent"
private let ACTION_TASK_DESTROY = "onDestroy"

class ContinuedProcessingTask {
  private let serviceStatus: BackgroundServiceStatus
  private let taskData: ForegroundTaskData
  private var taskEventAction: ForegroundTaskEventAction
  private let taskLifecycleListener: FlutterForegroundTaskLifecycleListener
  private let bgTask: BGTask
  private let onFinished: () -> Void

  private var flutterEngine: FlutterEngine? = nil
  private var backgroundChannel: FlutterMethodChannel? = nil
  private var repeatTask: Timer? = nil
  private var progress: Progress? = nil
  private var isDestroyed: Bool = false

  init(
    serviceStatus: BackgroundServiceStatus,
    taskData: ForegroundTaskData,
    taskEventAction: ForegroundTaskEventAction,
    taskLifecycleListener: FlutterForegroundTaskLifecycleListener,
    bgTask: BGTask,
    onFinished: @escaping () -> Void
  ) {
    self.serviceStatus = serviceStatus
    self.taskData = taskData
    self.taskEventAction = taskEventAction
    self.taskLifecycleListener = taskLifecycleListener
    self.bgTask = bgTask
    self.onFinished = onFinished
    self.progress = (bgTask as? ProgressReporting)?.progress

    initialize()
  }

  private func initialize() {
    guard let registerPlugins = SwiftFlutterForegroundTaskPlugin.registerPlugins else {
      print("Please register the registerPlugins function using the SwiftFlutterForegroundTaskPlugin.setPluginRegistrantCallback.")
      completeTask(success: false)
      return
    }

    guard let callbackHandle = taskData.callbackHandle else {
      completeTask(success: false)
      return
    }

    bgTask.expirationHandler = { [weak self] in
      self?.handleExpiration()
    }

    let callbackInfo = FlutterCallbackCache.lookupCallbackInformation(callbackHandle)
    guard let entrypoint = callbackInfo?.callbackName else {
      print("Entrypoint not found in callback information.")
      completeTask(success: false)
      return
    }
    guard let libraryURI = callbackInfo?.callbackLibraryPath else {
      print("LibraryURI not found in callback information.")
      completeTask(success: false)
      return
    }

    let flutterEngine = FlutterEngine(name: BG_ISOLATE_NAME, project: nil, allowHeadlessExecution: true)
    let isRunningEngine = flutterEngine.run(withEntrypoint: entrypoint, libraryURI: libraryURI)

    if isRunningEngine {
      registerPlugins(flutterEngine)
      taskLifecycleListener.onEngineCreate(flutterEngine: flutterEngine)

      let messenger = flutterEngine.binaryMessenger
      let backgroundChannel = FlutterMethodChannel(name: BG_CHANNEL_NAME, binaryMessenger: messenger)
      backgroundChannel.setMethodCallHandler(onMethodCall)

      self.flutterEngine = flutterEngine
      self.backgroundChannel = backgroundChannel
    } else {
      completeTask(success: false)
    }
  }

  func onMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
      case "start":
        start()
        result(nil)
      case "updateProgress":
        if let args = call.arguments as? Dictionary<String, Any>,
           let completed = args["completed"] as? Int64,
           let total = args["total"] as? Int64 {
          updateProgress(completed: completed, total: total)
        } else if let args = call.arguments as? Dictionary<String, Any>,
                  let completed = args["completed"] as? Int,
                  let total = args["total"] as? Int {
          updateProgress(completed: Int64(completed), total: Int64(total))
        }
        result(nil)
      case "updateTitle":
        if let args = call.arguments as? Dictionary<String, Any>,
           let title = args["title"] as? String,
           let subtitle = args["subtitle"] as? String {
          updateTitle(title: title, subtitle: subtitle)
        }
        result(nil)
      case "complete":
        completeTask(success: call.arguments as? Bool ?? true)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
    }
  }

  private func start() {
    runIfNotDestroyed {
      runIfCallbackHandleExists {
        let serviceAction = serviceStatus.action
        let starter: FlutterForegroundTaskStarter
        if serviceAction == .API_START || serviceAction == .API_RESTART || serviceAction == .API_UPDATE {
          starter = .DEVELOPER
        } else {
          starter = .SYSTEM
        }

        backgroundChannel?.invokeMethod(ACTION_TASK_START, arguments: starter.rawValue) { _ in
          self.runIfNotDestroyed {
            self.startRepeatTask()
          }
        }
        taskLifecycleListener.onTaskStart(starter: starter)
      }
    }
  }

  private func invokeTaskRepeatEvent() {
    backgroundChannel?.invokeMethod(ACTION_TASK_REPEAT_EVENT, arguments: nil)
    taskLifecycleListener.onTaskRepeatEvent()
  }

  private func startRepeatTask() {
    stopRepeatTask()

    let type = taskEventAction.type
    let interval = TimeInterval(Double(taskEventAction.interval) / 1000)

    if type == .NOTHING {
      return
    }

    if type == .ONCE {
      invokeTaskRepeatEvent()
      return
    }

    repeatTask = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
      self.invokeTaskRepeatEvent()
    }
  }

  private func stopRepeatTask() {
    repeatTask?.invalidate()
    repeatTask = nil
  }

  func invokeMethod(_ method: String, arguments: Any?) {
    runIfNotDestroyed {
      backgroundChannel?.invokeMethod(method, arguments: arguments)
    }
  }

  func updateProgress(completed: Int64, total: Int64) {
    runIfNotDestroyed {
      progress?.totalUnitCount = total
      progress?.completedUnitCount = completed
    }
  }

  func updateTitle(title: String, subtitle: String) {
    runIfNotDestroyed {
      let selector = NSSelectorFromString("updateTitle:subtitle:")
      if bgTask.responds(to: selector) {
        bgTask.perform(selector, with: title, with: subtitle)
      }
    }
  }

  private func handleExpiration() {
    completeTask(success: false, isTimeout: true)
  }

  func completeTask(
    success: Bool,
    isTimeout: Bool = false,
    notifyTaskDestroy: Bool = true
  ) {
    runIfNotDestroyed {
      stopRepeatTask()
      backgroundChannel?.setMethodCallHandler(nil)

      if notifyTaskDestroy && taskData.callbackHandle != nil {
        backgroundChannel?.invokeMethod(ACTION_TASK_DESTROY, arguments: isTimeout) { _ in
          self.destroyEngine()
        }
        taskLifecycleListener.onTaskDestroy()
        taskLifecycleListener.onEngineWillDestroy()
      } else {
        destroyEngine()
      }

      bgTask.setTaskCompleted(success: success)
      isDestroyed = true
      onFinished()
    }
  }

  func destroy() {
    completeTask(success: true)
  }

  private func destroyEngine() {
    flutterEngine?.destroyContext()
    flutterEngine = nil
  }

  private func runIfCallbackHandleExists(call: () -> Void) {
    if taskData.callbackHandle == nil {
      return
    }
    call()
  }

  private func runIfNotDestroyed(call: () -> Void) {
    if isDestroyed {
      return
    }
    call()
  }
}
