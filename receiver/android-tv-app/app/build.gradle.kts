import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val releasePropsFile = rootProject.file("key.properties")
val releaseProps = Properties()
if (releasePropsFile.exists()) releaseProps.load(releasePropsFile.inputStream())

android {
    namespace = "com.deeprows.receiver"
    compileSdk = 35

    // Keep Java and Kotlin bytecode targets aligned for release builds.
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.deeprows.receiver"
        minSdk = 23
        targetSdk = 35
        versionCode = providers.gradleProperty("appVersionCode").orElse("1").get().toInt()
        versionName = providers.gradleProperty("appVersionName").orElse("1.0.0").get()
    }

    signingConfigs {
        create("release") {
            if (releasePropsFile.exists()) {
                storeFile = rootProject.file(releaseProps.getProperty("storeFile"))
                storePassword = releaseProps.getProperty("storePassword")
                keyAlias = releaseProps.getProperty("keyAlias")
                keyPassword = releaseProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Use the same long-lived upload keystore as the main Deeprowss app when configured.
            // Debug signing is only a fallback for first-run testing, not recommended for public updates.
            signingConfig = if (releasePropsFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            isMinifyEnabled = false
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
}
