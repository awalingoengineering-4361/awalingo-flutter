import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.google.gms.google-services")
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val uploadKeyFile = rootProject.file("key.properties")
val uploadKey = Properties().apply {
    if (uploadKeyFile.isFile) FileInputStream(uploadKeyFile).use { load(it) }
}
val requiredUploadKeyFields = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val validateReleaseSigning = tasks.register("validateReleaseSigning") {
    doLast {
        check(uploadKeyFile.isFile && requiredUploadKeyFields.all {
            !uploadKey.getProperty(it).isNullOrBlank() && uploadKey.getProperty(it) != "REPLACE_LOCALLY"
        }) { "Release signing requires android/key.properties. See android/key.properties.example." }
        check(file(uploadKey.getProperty("storeFile")).isFile) { "The configured upload keystore does not exist." }
    }
}
tasks.configureEach {
    if (name == "preReleaseBuild") dependsOn(validateReleaseSigning)
}

android {
    namespace = "org.awalingo.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "org.awalingo.app"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (requiredUploadKeyFields.all { !uploadKey.getProperty(it).isNullOrBlank() }) {
                storeFile = file(uploadKey.getProperty("storeFile"))
                storePassword = uploadKey.getProperty("storePassword")
                keyAlias = uploadKey.getProperty("keyAlias")
                keyPassword = uploadKey.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:35.0.2"))
    implementation("com.google.firebase:firebase-messaging")
    implementation("androidx.core:core-ktx:1.17.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16.1")
    androidTestImplementation("androidx.test:runner:1.3.0")
}
