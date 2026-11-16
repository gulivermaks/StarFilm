package app.starfilm.android

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.speech.RecognizerIntent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    companion object {
        private const val REQ_VOICE_INPUT = 4107
        private const val REQ_NOTIF_PERM = 4108
        private const val RELEASE_CHANNEL_ID = "starfilm_releases"
    }

    private var pendingVoiceResult: MethodChannel.Result? = null
    private var pendingNotifResult: MethodChannel.Result? = null
    private var pendingNotifTitle: String? = null
    private var pendingNotifBody: String? = null
    private var pendingNotifId: Int = 7101

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.starfilm.android/launcher"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "launchPackage" -> {
                    val packageName = call.argument<String>("packageName")?.trim().orEmpty()
                    if (packageName.isEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    var launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                    if (launchIntent == null && packageName == "com.mxtech.videoplayer.ad") {
                        launchIntent = packageManager.getLaunchIntentForPackage("com.mxtech.videoplayer.pro")
                    }
                    if (launchIntent != null) {
                        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(launchIntent)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "verifyAndInstallApk" -> {
                    val apkPath = call.argument<String>("apkPath")?.trim().orEmpty()
                    result.success(verifyAndInstallApk(apkPath))
                }
                "startVoiceInput" -> {
                    val language = call.argument<String>("language")?.trim().orEmpty()
                    val prompt = call.argument<String>("prompt")?.trim().orEmpty()
                    startVoiceInput(language, prompt, result)
                }
                "showReleaseNotification" -> {
                    val title = call.argument<String>("title")?.trim().orEmpty()
                    val body = call.argument<String>("body")?.trim().orEmpty()
                    val notifyId = call.argument<Int>("notifyId") ?: 7101
                    showReleaseNotification(title, body, notifyId, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startVoiceInput(language: String, prompt: String, result: MethodChannel.Result) {
        pendingVoiceResult?.success("")
        pendingVoiceResult = result

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            if (language.isNotEmpty()) {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
            }
            if (prompt.isNotEmpty()) {
                putExtra(RecognizerIntent.EXTRA_PROMPT, prompt)
            }
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQ_VOICE_INPUT)
        } catch (_: ActivityNotFoundException) {
            pendingVoiceResult = null
            result.success(null)
        } catch (_: Exception) {
            pendingVoiceResult = null
            result.success(null)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_VOICE_INPUT) {
            val cb = pendingVoiceResult
            pendingVoiceResult = null
            if (resultCode == Activity.RESULT_OK && data != null) {
                val matches = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                cb?.success(matches?.firstOrNull()?.trim().orEmpty())
            } else {
                cb?.success("")
            }
        }
    }

    private fun showReleaseNotification(
        title: String,
        body: String,
        notifyId: Int,
        result: MethodChannel.Result
    ) {
        if (title.isEmpty() || body.isEmpty()) {
            result.success(false)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingNotifResult?.success(false)
            pendingNotifResult = result
            pendingNotifTitle = title
            pendingNotifBody = body
            pendingNotifId = notifyId
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIF_PERM)
            return
        }
        result.success(postReleaseNotification(title, body, notifyId))
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_NOTIF_PERM) {
            val cb = pendingNotifResult
            val t = pendingNotifTitle
            val b = pendingNotifBody
            val id = pendingNotifId
            pendingNotifResult = null
            pendingNotifTitle = null
            pendingNotifBody = null
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted && !t.isNullOrEmpty() && !b.isNullOrEmpty()) {
                cb?.success(postReleaseNotification(t, b, id))
            } else {
                cb?.success(false)
            }
        }
    }

    private fun postReleaseNotification(title: String, body: String, notifyId: Int): Boolean {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val existing = manager.getNotificationChannel(RELEASE_CHANNEL_ID)
            if (existing == null) {
                val channel = NotificationChannel(
                    RELEASE_CHANNEL_ID,
                    "Movie digital releases",
                    NotificationManager.IMPORTANCE_DEFAULT
                )
                manager.createNotificationChannel(channel)
            }
        }
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            this,
            notifyId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = Notification.Builder(this, RELEASE_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_starfilm)
            .setColor(0xFFA3E635.toInt())
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        manager.notify(notifyId, notification)
        return true
    }

    private fun verifyAndInstallApk(apkPath: String): String {
        if (apkPath.isEmpty()) return "file_missing"
        val apkFile = File(apkPath)
        if (!apkFile.exists()) return "file_missing"

        val installedCerts = getInstalledSigningSha256()
        val archiveCerts = getArchiveSigningSha256(apkFile.absolutePath)
        if (installedCerts.isEmpty() || archiveCerts.isEmpty() || installedCerts.intersect(archiveCerts).isEmpty()) {
            apkFile.delete()
            return "signature_mismatch"
        }

        if (!packageManager.canRequestPackageInstalls()) {
            val permissionIntent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            return try {
                startActivity(permissionIntent)
                "permission_required"
            } catch (e: Exception) {
                "error:${e.message ?: "install_permission_denied"}"
            }
        }

        val apkUri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.ota.fileprovider",
            apkFile
        )
        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            startActivity(installIntent)
            "ok"
        } catch (e: Exception) {
            "error:${e.message ?: "unknown"}"
        }
    }

    @Suppress("DEPRECATION")
    private fun getInstalledSigningSha256(): Set<String> {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        val info = packageManager.getPackageInfo(packageName, flags)
        return extractCertSha256(info)
    }

    @Suppress("DEPRECATION")
    private fun getArchiveSigningSha256(apkPath: String): Set<String> {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        val info = packageManager.getPackageArchiveInfo(apkPath, flags) ?: return emptySet()
        return extractCertSha256(info)
    }

    @Suppress("DEPRECATION")
    private fun extractCertSha256(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = info.signingInfo ?: return emptySet()
            if (signingInfo.hasMultipleSigners()) {
                signingInfo.apkContentsSigners
            } else {
                signingInfo.signingCertificateHistory
            }
        } else {
            info.signatures
        } ?: return emptySet()

        val digest = MessageDigest.getInstance("SHA-256")
        return signatures.map { sig ->
            digest.reset()
            digest.digest(sig.toByteArray()).joinToString("") { "%02x".format(it) }
        }.toSet()
    }
}
