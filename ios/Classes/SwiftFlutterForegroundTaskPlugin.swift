import Flutter
import UIKit
import BackgroundTasks
import ObjectiveC

public class SwiftFlutterForegroundTaskPlugin: NSObject, FlutterPlugin {
  // ====================== Plugin ======================
  static private(set) var registerPlugins: FlutterPluginRegistrantCallback? = nil

  private var notificationPermissionManager: NotificationPermissionManager? = nil
  private var backgroundServiceManager: BackgroundServiceManager? = nil

  private var foregroundChannel: FlutterMethodChannel? = nil

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SwiftFlutterForegroundTaskPlugin()
    instance.initServices()
    instance.initChannels(registrar.messenger())
    registrar.addApplicationDelegate(instance)
  }

  public static func setPluginRegistrantCallback(_ callback: @escaping FlutterPluginRegistrantCallback) {
    registerPlugins = callback
  }

  public static func addTaskLifecycleListener(_ listener: FlutterForegroundTaskLifecycleListener) {
    BackgroundService.sharedInstance.addTaskLifecycleListener(listener)
  }

  public static func removeTaskLifecycleListener(_ listener: FlutterForegroundTaskLifecycleListener) {
    BackgroundService.sharedInstance.removeTaskLifecycleListener(listener)
  }

  private func initServices() {
    notificationPermissionManager = NotificationPermissionManager()
    backgroundServiceManager = BackgroundServiceManager()
  }

  private func initChannels(_ messenger: FlutterBinaryMessenger) {
    foregroundChannel = FlutterMethodChannel(name: "flutter_foreground_task/methods", binaryMessenger: messenger)
    foregroundChannel?.setMethodCallHandler(onMethodCall)
  }

  private func onMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments
    do {
      switch call.method {
        case "checkNotificationPermission":
          notificationPermissionManager!.checkPermission { permission in
            result(permission.rawValue)
          }
        case "requestNotificationPermission":
          notificationPermissionManager!.requestPermission { permission in
            result(permission.rawValue)
          }
        case "startService":
          try backgroundServiceManager!.start(arguments: args)
          result(true)
        case "restartService":
          try backgroundServiceManager!.restart(arguments: args)
          result(true)
        case "updateService":
          try backgroundServiceManager!.update(arguments: args)
          result(true)
        case "stopService":
          try backgroundServiceManager!.stop()
          result(true)
        case "sendData":
          backgroundServiceManager!.sendData(data: args)
        case "isRunningService":
          result(backgroundServiceManager!.isRunningService())
        case "startContinuedProcessingTask":
          if #available(iOS 13.0, *) {
            try startContinuedProcessingTask(arguments: args)
            result(true)
          } else {
            throw ServiceError.ServiceNotSupportedException
          }
        case "stopContinuedProcessingTask":
          if #available(iOS 13.0, *) {
            stopContinuedProcessingTask()
            result(true)
          } else {
            throw ServiceError.ServiceNotSupportedException
          }
        case "isRunningContinuedProcessingTask":
          if #available(iOS 13.0, *) {
            result(BackgroundService.sharedInstance.isRunningContinuedProcessing)
          } else {
            result(false)
          }
        case "isContinuedProcessingTaskSupported":
          result(SwiftFlutterForegroundTaskPlugin.isContinuedProcessingTaskSupported())
        case "isGPUResourceSupported":
          result(SwiftFlutterForegroundTaskPlugin.isGPUResourceSupported())
        case "minimizeApp":
          UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
        case "isAppOnForeground":
          result(UIApplication.shared.applicationState == .active)
        default:
          result(FlutterMethodNotImplemented)
      }
    } catch {
      let code = String(describing: error.self)
      let message = error.localizedDescription
      let flutterError = FlutterError(code: code, message: message, details: nil)
      result(flutterError)
    }
  }

  // ================== App Lifecycle ===================
  public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [AnyHashable : Any] = [:]) -> Bool {
    UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
    if #available(iOS 13.0, *) {
      SwiftFlutterForegroundTaskPlugin.registerAppRefresh()
    }
    if #available(iOS 13.0, *), SwiftFlutterForegroundTaskPlugin.isContinuedProcessingTaskSupported() {
      SwiftFlutterForegroundTaskPlugin.registerContinuedProcessingTask()
    }
    return true
  }

  public func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) -> Bool {
    completionHandler(.newData)
    return true
  }

  public func applicationDidEnterBackground(_ application: UIApplication) {
    if #available(iOS 13.0, *) {
      SwiftFlutterForegroundTaskPlugin.scheduleAppRefresh()
    }
  }

  public func applicationWillTerminate(_ application: UIApplication) {
    if !BackgroundService.sharedInstance.isRunningService {
      return
    }

    BackgroundServiceStatus.setData(action: BackgroundServiceAction.APP_TERMINATE)
    BackgroundService.sharedInstance.run()

    // Chance to handle onDestroy before app terminates
    sleep(5)
  }

  // ================= Service Delegate =================
  @available(iOS 10.0, *)
  public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                     didReceive response: UNNotificationResponse,
                                     withCompletionHandler completionHandler: @escaping () -> Void) {
    BackgroundService.sharedInstance.userNotificationCenter(center, response, completionHandler)
  }

  @available(iOS 10.0, *)
  public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                     willPresent notification: UNNotification,
                                     withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    BackgroundService.sharedInstance.userNotificationCenter(center, notification, completionHandler)
  }

  // ============== Background App Refresh ==============
  public static var refreshIdentifier: String = "com.pravera.flutter_foreground_task.refresh"

  @available(iOS 13.0, *)
  private static func registerAppRefresh() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshIdentifier, using: nil) { task in
      handleAppRefresh(task: task as! BGAppRefreshTask)
    }
  }

  @available(iOS 13.0, *)
  private static func scheduleAppRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      print("Could not schedule app refresh: \(error)")
    }
  }

  @available(iOS 13.0, *)
  private static func cancelAppRefresh() {
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshIdentifier)
  }

  @available(iOS 13.0, *)
  private static func handleAppRefresh(task: BGAppRefreshTask) {
    let queue = OperationQueue()
    let operation = AppRefreshOperation()

    task.expirationHandler = {
      operation.cancel()
    }

    operation.completionBlock = {
      // Schedule a new refresh task
      scheduleAppRefresh()

      task.setTaskCompleted(success: true)
    }

    queue.addOperation(operation)
  }
}

class AppRefreshOperation: Operation {
  override func main() {
    let semaphore = DispatchSemaphore(value: 0)

    // avoid non-platform thread
    DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
      semaphore.signal()
    }

    semaphore.wait()
  }
}

// MARK: - BGContinuedProcessingTask Support (iOS 26+)

extension SwiftFlutterForegroundTaskPlugin {
  private static var continuedProcessingIdentifier: String {
    return Bundle.main.bundleIdentifier! + ".continuedProcessing.*"
  }

  @available(iOS 13.0, *)
  private static func registerContinuedProcessingTask() {
    let identifier = continuedProcessingIdentifier
    BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
      handleContinuedProcessingTask(task: task)
    }
  }

  @available(iOS 13.0, *)
  private static func handleContinuedProcessingTask(task: BGTask) {
    BackgroundService.sharedInstance.startContinuedProcessingTask(bgTask: task)
  }

  static func isContinuedProcessingTaskSupported() -> Bool {
    if #available(iOS 26.0, *) {
      return NSClassFromString("BGContinuedProcessingTaskRequest") != nil
    }

    return false
  }

  static func isGPUResourceSupported() -> Bool {
    if #available(iOS 26.0, *) {
      return supportedContinuedProcessingResources() & 1 == 1
    }

    return false
  }

  @available(iOS 13.0, *)
  private func startContinuedProcessingTask(arguments: Any?) throws {
    guard SwiftFlutterForegroundTaskPlugin.isContinuedProcessingTaskSupported() else {
      throw ServiceError.ServiceNotSupportedException
    }

    guard let args = arguments as? Dictionary<String, Any> else {
      throw ServiceError.ServiceArgumentNullException
    }

    // Save configuration (using separate keys to survive foreground service stop)
    ContinuedProcessingTaskOptions.setData(args: args)
    saveContinuedProcessingTaskArgs(args)

    // Get options
    guard let options = ContinuedProcessingTaskOptions.getData() else {
      throw ServiceError.ServiceArgumentNullException
    }

    let identifier = SwiftFlutterForegroundTaskPlugin.continuedProcessingIdentifier
    guard let request = SwiftFlutterForegroundTaskPlugin.createContinuedProcessingTaskRequest(
      identifier: identifier,
      title: options.title,
      subtitle: options.subtitle
    ) else {
      throw ServiceError.ServiceNotSupportedException
    }

    // Set submission strategy
    switch options.submissionStrategy {
      case .fail:
        request.setValue(0, forKey: "strategy")
      case .queue:
        request.setValue(1, forKey: "strategy")
    }

    // Set required resources
    if options.requiresGPU {
      guard SwiftFlutterForegroundTaskPlugin.isGPUResourceSupported() else {
        throw ServiceError.ServiceNotSupportedException
      }
      request.setValue(1, forKey: "requiredResources")
    }

    // Submit request
    do {
      try BGTaskScheduler.shared.submit(request)
      print("BGContinuedProcessingTask submitted successfully with identifier: \(identifier)")
    } catch {
      print("Failed to submit BGContinuedProcessingTask: \(error)")
      throw error
    }
  }

  @available(iOS 13.0, *)
  private func stopContinuedProcessingTask() {
    BackgroundService.sharedInstance.stopContinuedProcessingTask()

    // Cancel pending continued processing task
    BGTaskScheduler.shared.cancel(
      taskRequestWithIdentifier: SwiftFlutterForegroundTaskPlugin.continuedProcessingIdentifier
    )

    // Clear configuration
    ContinuedProcessingTaskOptions.clearData()
    clearContinuedProcessingTaskArgs()
  }

  // MARK: - Separate Storage for Continued Processing Task Args

  private func saveContinuedProcessingTaskArgs(_ args: Dictionary<String, Any>) {
    let prefs = UserDefaults.standard
    if let jsonData = try? JSONSerialization.data(withJSONObject: args, options: []) {
      prefs.set(jsonData, forKey: CONTINUED_PROCESSING_ARGS)
    }
  }

  private func clearContinuedProcessingTaskArgs() {
    UserDefaults.standard.removeObject(
      forKey: CONTINUED_PROCESSING_ARGS
    )
  }

  @available(iOS 13.0, *)
  private static func createContinuedProcessingTaskRequest(
    identifier: String,
    title: String,
    subtitle: String
  ) -> BGTaskRequest? {
    guard let requestClass = NSClassFromString("BGContinuedProcessingTaskRequest") else {
      return nil
    }

    let selector = NSSelectorFromString("initWithIdentifier:title:subtitle:")
    guard let method = class_getInstanceMethod(requestClass, selector),
          let allocated = class_createInstance(requestClass, 0) else {
      return nil
    }

    typealias InitFunction = @convention(c) (
      AnyObject,
      Selector,
      NSString,
      NSString,
      NSString
    ) -> AnyObject

    let implementation = method_getImplementation(method)
    let initFunction = unsafeBitCast(implementation, to: InitFunction.self)
    let request = initFunction(
      allocated as AnyObject,
      selector,
      identifier as NSString,
      title as NSString,
      subtitle as NSString
    )

    return request as? BGTaskRequest
  }

  private static func supportedContinuedProcessingResources() -> Int {
    guard #available(iOS 26.0, *) else {
      return 0
    }

    let selector = NSSelectorFromString("supportedResources")
    guard let method = class_getClassMethod(BGTaskScheduler.self, selector) else {
      return 0
    }

    typealias SupportedResourcesFunction = @convention(c) (AnyClass, Selector) -> Int

    let implementation = method_getImplementation(method)
    let supportedResourcesFunction = unsafeBitCast(
      implementation,
      to: SupportedResourcesFunction.self
    )

    return supportedResourcesFunction(BGTaskScheduler.self, selector)
  }
}
