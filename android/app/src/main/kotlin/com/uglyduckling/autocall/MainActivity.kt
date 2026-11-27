package com.uglyduckling.autocall

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var dialBridge: DialBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        dialBridge = DialBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        dialBridge?.onRequestPermissionsResult(requestCode, grantResults)
    }

    override fun onResume() {
        super.onResume()
        // App 回到前台 → 继续拨号倒计时
        AutoDialService.onAppForeground()
    }

    override fun onPause() {
        // App 离开前台 → 冻结倒计时
        AutoDialService.onAppBackground()
        super.onPause()
    }
}

