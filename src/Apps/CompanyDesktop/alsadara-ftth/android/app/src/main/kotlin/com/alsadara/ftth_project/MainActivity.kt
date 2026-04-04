package com.alsadara.ftth_project

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val MOCK_CHANNEL = "com.alsadara/mock_detector"
    private val INSTALL_CHANNEL = "com.alsadara/installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Mock Location Detector channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MOCK_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "detectAll" -> {
                        val detection = MockLocationDetector.detectAll(applicationContext)
                        result.success(detection)
                    }
                    "isSuspicious" -> {
                        val suspicious = MockLocationDetector.isDeviceSuspicious(applicationContext)
                        result.success(suspicious)
                    }
                    else -> result.notImplemented()
                }
            }

        // APK Installer channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath == null) {
                            result.error("NO_PATH", "filePath is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = File(filePath)
                            if (!file.exists()) {
                                result.error("NOT_FOUND", "APK file not found", null)
                                return@setMethodCallHandler
                            }

                            val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                FileProvider.getUriForFile(
                                    applicationContext,
                                    "${applicationContext.packageName}.provider",
                                    file
                                )
                            } else {
                                Uri.fromFile(file)
                            }

                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.message, null)
                        }
                    }
                    "uninstallApp" -> {
                        // فتح شاشة حذف التطبيق — عند فشل التحديث بسبب اختلاف التوقيع
                        try {
                            val intent = Intent(Intent.ACTION_DELETE).apply {
                                data = Uri.parse("package:${applicationContext.packageName}")
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("UNINSTALL_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
