package app.starfilm.android

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
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
                    val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
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
                else -> result.notImplemented()
            }
        }
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
