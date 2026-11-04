import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Local upload key; never fall back to the Android debug certificate.
val uploadProperties = Properties()
val uploadPropertiesFile = rootProject.file("key.properties")
if (uploadPropertiesFile.isFile) {
    uploadPropertiesFile.inputStream().use { uploadProperties.load(it) }
}
val uploadStore = uploadProperties.getProperty("storeFile")?.let { rootProject.file(it) }
val uploadSigningConfigured = uploadStore?.isFile == true &&
    listOf("storePassword", "keyPassword", "keyAlias").all {
        !uploadProperties.getProperty(it).isNullOrBlank()
    }

android {
    namespace = "com.aipersonalcompanion"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.aipersonalcompanion"
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
    }

    signingConfigs {
        create("release") {
            storeFile = uploadStore
            storePassword = uploadProperties.getProperty("storePassword")
            keyPassword = uploadProperties.getProperty("keyPassword")
            keyAlias = uploadProperties.getProperty("keyAlias")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name == "validateSigningRelease" } &&
        !uploadSigningConfigured) {
        throw GradleException("Release signing is missing. Configure android/key.properties and its existing upload keystore; see docs/internal-testing.md. Debug signing is not used for release builds.")
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
