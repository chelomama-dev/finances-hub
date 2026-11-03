import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Flutter hands the --dart-define values to Gradle as base64 "KEY=value" pairs. The signature hashes for MSAL's
// redirect come from there, so the app and its manifest always agree (core/config.dart reads the same values)
val dartDefines: Map<String, String> = (project.findProperty("dart-defines") as String?)
    ?.split(",")
    ?.map { String(Base64.getDecoder().decode(it)).split("=", limit = 2) }
    ?.filter { it.size == 2 }
    ?.associate { it[0] to it[1] }
    ?: emptyMap()

// Without auth (local API, demo, CI) any value will do: the login is never opened
fun msalSignatureHash(key: String) = dartDefines[key]?.takeIf { it.isNotBlank() } ?: "none"

android {
    namespace = "dev.chelomama.finances_hub"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.chelomama.financeshub"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Debug and profile builds are signed with the debug key
        manifestPlaceholders["msalSignatureHash"] = msalSignatureHash("AUTH_DEBUG_SIGNATURE_HASH")
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            manifestPlaceholders["msalSignatureHash"] = msalSignatureHash("AUTH_RELEASE_SIGNATURE_HASH")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
