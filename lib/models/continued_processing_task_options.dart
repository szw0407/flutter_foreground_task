/// Options for BGContinuedProcessingTask (iOS 26+).
///
/// This allows long-running user-initiated tasks to continue in the background
/// with Live Activity UI showing progress.
class ContinuedProcessingTaskOptions {
  /// The localized title displayed to the user.
  final String title;

  /// The localized subtitle displayed to the user.
  final String subtitle;

  /// Whether the task requires GPU access.
  ///
  /// Requires the `com.apple.developer.background-tasks.continued-processing.gpu`
  /// entitlement. Not all devices support GPU in background.
  final bool requiresGPU;

  /// The submission strategy for the task.
  ///
  /// - [ContinuedProcessingSubmissionStrategy.fail]: Fail immediately if system
  ///   cannot run the task.
  /// - [ContinuedProcessingSubmissionStrategy.queue]: Queue the task if system
  ///   is busy. Queued tasks are cancelled when app is removed from app switcher.
  final ContinuedProcessingSubmissionStrategy submissionStrategy;

  /// Constructs an instance of [ContinuedProcessingTaskOptions].
  const ContinuedProcessingTaskOptions({
    required this.title,
    required this.subtitle,
    this.requiresGPU = false,
    this.submissionStrategy = ContinuedProcessingSubmissionStrategy.queue,
  });

  /// Returns the data fields of [ContinuedProcessingTaskOptions] in JSON format.
  Map<String, dynamic> toJson() {
    return {
      'continuedProcessingEnabled': true,
      'continuedProcessingTitle': title,
      'continuedProcessingSubtitle': subtitle,
      'continuedProcessingRequiresGPU': requiresGPU,
      'continuedProcessingStrategy': submissionStrategy.value,
    };
  }
}

/// Submission strategy for BGContinuedProcessingTask.
enum ContinuedProcessingSubmissionStrategy {
  /// Fail the submission if there is no room for the task request,
  /// or if the system is under substantial load.
  fail('fail'),

  /// Add the request to a queue if there is no room for the task
  /// or if the system is under substantial load.
  ///
  /// Queued tasks will be cancelled when the user removes your app
  /// from the app switcher.
  queue('queue');

  const ContinuedProcessingSubmissionStrategy(this.value);

  final String value;
}
