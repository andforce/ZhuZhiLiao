package com.azhegezhege.zhuzhiliao

import android.app.Activity
import android.app.Application
import android.os.Bundle

class ZhuZhiLiaoApplication : Application(), Application.ActivityLifecycleCallbacks {
    lateinit var coordinator: ExperienceCoordinator
        private set
    private var startedActivities = 0
    private var hasStartedExperience = false

    override fun onCreate() {
        super.onCreate()
        coordinator = ExperienceCoordinator(this)
        registerActivityLifecycleCallbacks(this)
    }

    override fun onActivityStarted(activity: Activity) {
        startedActivities += 1
        if (startedActivities == 1) {
            coordinator.start()
            if (hasStartedExperience) coordinator.recalibrate()
            hasStartedExperience = true
        }
    }

    override fun onActivityStopped(activity: Activity) {
        startedActivities = (startedActivities - 1).coerceAtLeast(0)
        if (startedActivities == 0) coordinator.pause()
    }

    override fun onActivityCreated(activity: Activity, state: Bundle?) = Unit
    override fun onActivityResumed(activity: Activity) = Unit
    override fun onActivityPaused(activity: Activity) = Unit
    override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) = Unit
    override fun onActivityDestroyed(activity: Activity) = Unit
}
