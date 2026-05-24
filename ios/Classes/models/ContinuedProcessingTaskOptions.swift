//
//  ContinuedProcessingTaskOptions.swift
//  flutter_foreground_task
//
//  Created for BGContinuedProcessingTask support (iOS 26+)
//

import Foundation

struct ContinuedProcessingTaskOptions {
  let enabled: Bool
  let title: String
  let subtitle: String
  let requiresGPU: Bool
  let submissionStrategy: SubmissionStrategy

  enum SubmissionStrategy: String {
    case fail = "fail"
    case queue = "queue"
  }

  static func getData() -> ContinuedProcessingTaskOptions? {
    let prefs = UserDefaults.standard

    guard prefs.bool(forKey: CONTINUED_PROCESSING_ENABLED) else {
      return nil
    }

    let title = prefs.string(forKey: CONTINUED_PROCESSING_TITLE) ?? "Processing"
    let subtitle = prefs.string(forKey: CONTINUED_PROCESSING_SUBTITLE) ?? "Task in progress"
    let requiresGPU = prefs.bool(forKey: CONTINUED_PROCESSING_REQUIRES_GPU)
    let strategyString = prefs.string(forKey: CONTINUED_PROCESSING_STRATEGY) ?? "queue"
    let strategy = SubmissionStrategy(rawValue: strategyString) ?? .queue

    return ContinuedProcessingTaskOptions(
      enabled: true,
      title: title,
      subtitle: subtitle,
      requiresGPU: requiresGPU,
      submissionStrategy: strategy
    )
  }

  static func setData(args: Dictionary<String, Any>) {
    let prefs = UserDefaults.standard

    if let enabled = args[CONTINUED_PROCESSING_ENABLED] as? Bool {
      prefs.set(enabled, forKey: CONTINUED_PROCESSING_ENABLED)
    }

    if let title = args[CONTINUED_PROCESSING_TITLE] as? String {
      prefs.set(title, forKey: CONTINUED_PROCESSING_TITLE)
    }

    if let subtitle = args[CONTINUED_PROCESSING_SUBTITLE] as? String {
      prefs.set(subtitle, forKey: CONTINUED_PROCESSING_SUBTITLE)
    }

    if let requiresGPU = args[CONTINUED_PROCESSING_REQUIRES_GPU] as? Bool {
      prefs.set(requiresGPU, forKey: CONTINUED_PROCESSING_REQUIRES_GPU)
    }

    if let strategy = args[CONTINUED_PROCESSING_STRATEGY] as? String {
      prefs.set(strategy, forKey: CONTINUED_PROCESSING_STRATEGY)
    }
  }

  static func updateData(args: Dictionary<String, Any>) {
    setData(args: args)
  }

  static func clearData() {
    let prefs = UserDefaults.standard
    prefs.removeObject(forKey: CONTINUED_PROCESSING_ENABLED)
    prefs.removeObject(forKey: CONTINUED_PROCESSING_TITLE)
    prefs.removeObject(forKey: CONTINUED_PROCESSING_SUBTITLE)
    prefs.removeObject(forKey: CONTINUED_PROCESSING_REQUIRES_GPU)
    prefs.removeObject(forKey: CONTINUED_PROCESSING_STRATEGY)
  }
}
