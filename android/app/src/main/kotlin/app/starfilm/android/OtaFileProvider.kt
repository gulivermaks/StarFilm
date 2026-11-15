package app.starfilm.android

import androidx.core.content.FileProvider

/** Dedicated FileProvider for verified OTA APK installs to avoid manifest authority collisions. */
class OtaFileProvider : FileProvider()
