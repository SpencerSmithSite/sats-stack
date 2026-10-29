import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials, kept out of the repository.
//
// `android/key.properties` is gitignored (along with *.jks and *.keystore), so
// it exists on a machine that is set up to publish and nowhere else. Create it
// with storeFile, storePassword, keyAlias and keyPassword.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keyProperties.getProperty("storeFile") != null

android {
    namespace = "app.satsstack.satsstack"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

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

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // The real key when key.properties is present, and nothing at all
            // when it is not.
            //
            // It used to say `signingConfigs.getByName("debug")`, straight from
            // the Flutter template, which meant a release build was signed with
            // the publicly-known debug key: Play rejects such an artifact
            // outright, and anything that did ship would carry a key anyone can
            // reproduce. An unsigned build fails loudly at the upload step
            // instead, which is the right place to find out.
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                null
            }
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
