plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.satsstack.satsstack"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.satsstack.satsstack"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // ML Kit's GenAI Prompt API (Gemini Nano) requires API 26, above
        // Flutter's default floor. Pinned explicitly rather than left to
        // `flutter.minSdkVersion` so a Flutter upgrade that lowers the default
        // cannot silently break the Gemini Nano build.
        minSdk = maxOf(26, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Gemini Nano through ML Kit's on-device GenAI Prompt API. Runs against
    // AICore, so there is no model to bundle and nothing to ship — the weights
    // are fetched by Android on request. Devices without AICore, or with an
    // unlocked bootloader, simply report the feature unavailable and the
    // backend is not offered.
    implementation("com.google.mlkit:genai-prompt:1.0.0-beta2")

    // The Prompt API is coroutine-first: `checkStatus` suspends and both
    // `download()` and `generateContentStream()` return Flow, so the bridge
    // needs a dispatcher to collect them on.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
