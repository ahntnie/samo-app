pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }

    // Thêm đoạn này để ép Gradle Kotlin DSL dùng Kotlin 1.8.22 (tránh xung đột Kotlin)
    resolutionStrategy {
        eachPlugin {
            if (requested.id.id == "kotlin-dsl") {
                useVersion("1.8.22")
            }
        }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.1.0" apply false // Đồng bộ với AGP 8.1.0
    id("org.jetbrains.kotlin.android") version "1.8.22" apply false
}

include(":app")