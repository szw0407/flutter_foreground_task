//
//  BackgroundServicePrefsKey.swift
//  flutter_foreground_task
//
//  Created by WOO JIN HWANG on 2021/08/11.
//

// service status
let BACKGROUND_SERVICE_ACTION = "backgroundServiceAction"

// notification options
let SHOW_NOTIFICATION = "showNotification"
let PLAY_SOUND = "playSound"

// notification content
let NOTIFICATION_CONTENT_TITLE = "notificationContentTitle"
let NOTIFICATION_CONTENT_TEXT = "notificationContentText"
let NOTIFICATION_CONTENT_BUTTONS = "buttons"

// task options
let TASK_EVENT_ACTION = "taskEventAction" // new
let INTERVAL = "interval" // deprecated
let IS_ONCE_EVENT = "isOnceEvent" // deprecated

// task data
let CALLBACK_HANDLE = "callbackHandle"

// continued processing task options (iOS 26+)
let CONTINUED_PROCESSING_ENABLED = "continuedProcessingEnabled"
let CONTINUED_PROCESSING_TITLE = "continuedProcessingTitle"
let CONTINUED_PROCESSING_SUBTITLE = "continuedProcessingSubtitle"
let CONTINUED_PROCESSING_REQUIRES_GPU = "continuedProcessingRequiresGPU"
let CONTINUED_PROCESSING_STRATEGY = "continuedProcessingStrategy"
let CONTINUED_PROCESSING_ARGS = "continuedProcessingArgs"
