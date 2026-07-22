plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Attempt to load signing config from key.properties (local) or environment variables (CI)
fun loadSigningProperty(name: String): String? {
    val keyFile = rootProject.file("key.properties")
    if (keyFile.exists()) {
        val props = java.util.Properties()
        props.load(keyFile.inputStream())
        if (props.containsKey(name)) return props.getProperty(name)
    }
    return System.getenv("ANDROID_SIGNING_${name.uppercase().replace(".", "_")}")
}

android {
    namespace = "com.peadra.peadra"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            storeFile = loadSigningProperty("storeFile")?.let { file(it) }
            storePassword = loadSigningProperty("storePassword")
            keyAlias = loadSigningProperty("keyAlias")
            keyPassword = loadSigningProperty("keyPassword")
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.peadra.peadra"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            if (loadSigningProperty("storePassword") != null) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
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
