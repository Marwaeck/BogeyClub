// Die Android-App zeigt dieselbe Oberfläche wie Mac und Windows (web/index.html, vorbereitet von
// mac/prepare-web.mjs --target android nach android/build/web). Versionsnummer aus package.json im Projektordner.
import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

@Suppress("UNCHECKED_CAST")
val appVersion = (JsonSlurper().parse(rootProject.file("../package.json")) as Map<String, Any>)["version"] as String
val versionParts = appVersion.split("-")[0].split(".").map { it.toIntOrNull() ?: 0 } + listOf(0, 0, 0)
val webDir = rootProject.file("build/web")

// Signatur: Mit eigenem Schlüssel (BOGEY_KEYSTORE …, siehe scripts/android-key.sh) lassen sich Updates
// über die installierte App spielen. Ohne Schlüssel wird mit dem Testschlüssel des Rechners signiert.
val keystorePath = System.getenv("BOGEY_KEYSTORE")?.takeIf { it.isNotBlank() && file(it).exists() }

android {
    namespace = "club.bogey.android"
    compileSdk = 35

    defaultConfig {
        applicationId = "club.bogey.android"
        minSdk = 26
        targetSdk = 35
        versionCode = versionParts[0] * 10000 + versionParts[1] * 100 + versionParts[2]
        versionName = appVersion
    }

    signingConfigs {
        if (keystorePath != null) {
            create("bogey") {
                storeFile = file(keystorePath)
                storePassword = System.getenv("BOGEY_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("BOGEY_KEY_ALIAS") ?: "bogeyclub"
                keyPassword = System.getenv("BOGEY_KEY_PASSWORD") ?: System.getenv("BOGEY_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.findByName("bogey") ?: signingConfigs.getByName("debug")
        }
    }

    sourceSets["main"].assets.srcDirs(webDir)

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { buildConfig = true }
}

dependencies {
    implementation("androidx.activity:activity-ktx:1.9.3")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.webkit:webkit:1.12.1")
}

tasks.named("preBuild") {
    doFirst {
        if (!webDir.resolve("index.html").exists())
            throw GradleException("android/build/web fehlt – zuerst: node mac/prepare-web.mjs --target android")
    }
}
