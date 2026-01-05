pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        // 清华
        maven { url = uri("https://mirrors.tuna.tsinghua.edu.cn/maven/google/") }
        maven { url = uri("https://mirrors.tuna.tsinghua.edu.cn/maven/central/") }
        // 华为
        maven { url = uri("https://repo.huaweicloud.com/repository/maven/") }
        maven { url = uri("https://developer.huawei.com/repo/") }
        google()
        mavenCentral()
        gradlePluginPortal()
    }

}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
