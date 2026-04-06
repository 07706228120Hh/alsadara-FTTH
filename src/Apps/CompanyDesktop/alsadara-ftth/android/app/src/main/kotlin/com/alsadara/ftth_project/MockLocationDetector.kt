package com.alsadara.ftth_project

import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.provider.Settings

/**
 * كشف تطبيقات الموقع الوهمي (Fake GPS) على مستوى Android Native
 * — يتجاوز كل الثغرات التي تتيحها isMocked في Flutter
 */
object MockLocationDetector {

    // قائمة أشهر تطبيقات الفيك لوكيشن المعروفة
    private val KNOWN_MOCK_APPS = listOf(
        "com.lexa.fakegps",
        "com.blogspot.newapphorizons.fakegps",
        "com.incorporateapps.fakegps.fre",
        "com.incorporateapps.fakegps",
        "com.lkr.fakelocation",
        "com.evezzon.fakeGPS",
        "com.gsmartstudio.fakegps",
        "com.fake.gps.go.location.spoofer.free",
        "com.fakegps.mock",
        "ru.gavrikov.mocklocations",
        "com.divi.fakeGPS",
        "org.hola.gpslocation",
        "com.theappninjas.fakegpsjoystick",
        "com.theappninjas.gpsjoystick",
        "com.ltp.pro.fakelocation",
        "com.illusion.fakegps",
        "com.fakegps.route",
        "com.rosteam.gpsemulator",
        "com.tennyson.fakegps",
        "com.pe.fakegpsrun",
        "com.byterev.mock.location",
        "com.uzumapps.fakegps",
        "com.usefullapps.fakegpslocationpro",
        "com.dkwon.fakegps",
        "location.changer.fake.gps.spoofer",
        "com.fakegps.joystick",
        "com.huizhong.fakegps",
    )

    /**
     * الفحص الشامل — يُرجع Map فيه كل نتائج الكشف
     */
    fun detectAll(context: Context): Map<String, Any> {
        val result = mutableMapOf<String, Any>()

        // 1️⃣ فحص تطبيقات الفيك المثبتة
        val installedMockApps = getInstalledMockApps(context)
        result["mockAppsInstalled"] = installedMockApps.isNotEmpty()
        result["mockApps"] = installedMockApps

        // 2️⃣ فحص Developer Options
        result["developerOptionsEnabled"] = isDeveloperOptionsEnabled(context)

        // 3️⃣ فحص Mock Location Setting (Android < 6)
        result["mockLocationEnabled"] = isMockLocationSettingEnabled(context)

        // 4️⃣ فحص أي تطبيق لديه صلاحية Mock Location
        val appsWithMockPermission = getAppsWithMockPermission(context)
        result["appsWithMockPermission"] = appsWithMockPermission
        result["hasMockPermissionApps"] = appsWithMockPermission.isNotEmpty()

        // 5️⃣ فحص هل GPS Provider فعلاً شغال
        result["gpsProviderEnabled"] = isGpsProviderEnabled(context)

        // 6️⃣ النتيجة النهائية — هل الجهاز مشبوه؟
        val isSuspicious = installedMockApps.isNotEmpty() ||
                appsWithMockPermission.isNotEmpty() ||
                isMockLocationSettingEnabled(context)
        result["isSuspicious"] = isSuspicious

        return result
    }

    /**
     * فحص سريع — true إذا الجهاز مشبوه
     */
    fun isDeviceSuspicious(context: Context): Boolean {
        return getInstalledMockApps(context).isNotEmpty() ||
                getAppsWithMockPermission(context).isNotEmpty() ||
                isMockLocationSettingEnabled(context)
    }

    /**
     * 1️⃣ كشف تطبيقات الفيك المثبتة على الجهاز
     */
    private fun getInstalledMockApps(context: Context): List<String> {
        val pm = context.packageManager
        val found = mutableListOf<String>()
        for (pkg in KNOWN_MOCK_APPS) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    pm.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(0))
                } else {
                    @Suppress("DEPRECATION")
                    pm.getPackageInfo(pkg, 0)
                }
                found.add(pkg)
            } catch (_: PackageManager.NameNotFoundException) {
                // غير مثبت — عادي
            }
        }

        // بحث إضافي بالاسم: أي تطبيق يحتوي "fake" + "gps" أو "mock" + "location"
        val allApps = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.getInstalledApplications(0)
        }

        for (app in allApps) {
            val name = app.packageName.lowercase()
            if (name in found.map { it.lowercase() }) continue
            if ((name.contains("fake") && name.contains("gps")) ||
                (name.contains("mock") && name.contains("location")) ||
                (name.contains("gps") && name.contains("spoof")) ||
                (name.contains("gps") && name.contains("joystick")) ||
                (name.contains("location") && name.contains("changer"))
            ) {
                found.add(app.packageName)
            }
        }

        return found
    }

    /**
     * 2️⃣ هل Developer Options مفعّلة؟
     */
    private fun isDeveloperOptionsEnabled(context: Context): Boolean {
        return try {
            Settings.Global.getInt(
                context.contentResolver,
                Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0
            ) != 0
        } catch (_: Exception) {
            false
        }
    }

    /**
     * 3️⃣ هل Mock Location مفعّل في إعدادات المطور (Android < 6)
     */
    @Suppress("DEPRECATION")
    private fun isMockLocationSettingEnabled(context: Context): Boolean {
        return try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                Settings.Secure.getString(
                    context.contentResolver,
                    Settings.Secure.ALLOW_MOCK_LOCATION
                ) != "0"
            } else {
                // Android 6+ لا يوجد هذا الإعداد — نعتمد على فحص الصلاحيات
                false
            }
        } catch (_: Exception) {
            false
        }
    }

    /**
     * 4️⃣ كشف التطبيقات التي لديها صلاحية ACCESS_MOCK_LOCATION
     */
    private fun getAppsWithMockPermission(context: Context): List<String> {
        val pm = context.packageManager
        val found = mutableListOf<String>()

        val allApps = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.getInstalledApplications(0)
        }

        for (app in allApps) {
            try {
                val pkgInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    pm.getPackageInfo(
                        app.packageName,
                        PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong())
                    )
                } else {
                    @Suppress("DEPRECATION")
                    pm.getPackageInfo(app.packageName, PackageManager.GET_PERMISSIONS)
                }

                pkgInfo.requestedPermissions?.let { perms ->
                    if (perms.any { it == "android.permission.ACCESS_MOCK_LOCATION" }) {
                        // استبعاد تطبيقات النظام
                        if (app.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM == 0) {
                            found.add(app.packageName)
                        }
                    }
                }
            } catch (_: Exception) { }
        }

        return found
    }

    /**
     * 5️⃣ هل GPS Provider فعلاً يعمل؟
     */
    private fun isGpsProviderEnabled(context: Context): Boolean {
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        return lm?.isProviderEnabled(LocationManager.GPS_PROVIDER) ?: false
    }
}
