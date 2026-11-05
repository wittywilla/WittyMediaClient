plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "com.wittywilla.wittymediaclient"
    compileSdk = 37
    // Named here so a machine with only these tools doesn't go looking for the plugin's own default.
    buildToolsVersion = "37.0.0"

    defaultConfig {
        applicationId = "com.wittywilla.wittymediaclient"
        minSdk = 23
        // Target 37 adds a local-network permission: raise this with discovery tested on a device.
        targetSdk = 36
        versionCode = 8
        versionName = "0.4.1"
    }

    // One APK for each processor, as WebRTC's native library is 7 to 16 MB a processor, and a universal APK with all four
    // for anyone who doesn't know which they have. 32-bit ARM stays, for old TV sticks and phones. All five have the same
    // version code, so any one of them can replace another. scripts/check-abis.sh fails if a library is missing from one.
    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
            isUniversalApk = true
        }
    }

    // The theme, wording and test data every client shares.
    sourceSets.getByName("main").assets.directories.add("../../shared/data")

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
        // Release speed, signed with the throwaway debug key. For trying the app
        // on a device without a signing key. Debug builds run far slower on a TV stick.
        create("sideload") {
            initWith(getByName("release"))
            signingConfig = signingConfigs.getByName("debug")
            matchingFallbacks += "release"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.09.00"))
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.core:core-ktx:1.19.1")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.11.0")
    implementation("androidx.media3:media3-exoplayer:1.11.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.11.1")
    implementation("androidx.media3:media3-session:1.11.1")
    implementation("androidx.media3:media3-ui:1.11.1")
    implementation("io.coil-kt.coil3:coil-compose:3.6.3")
    implementation("io.coil-kt.coil3:coil-network-okhttp:3.6.3")
    implementation("com.squareup.okhttp3:okhttp:5.5.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.12.0")
    // Ed25519 for the server's identity: Android only has its own from API 33.
    implementation("org.bouncycastle:bcprov-jdk18on:1.86")
    // The QR code on the TV sign-in screen.
    implementation("com.google.zxing:core:3.5.4")
    // WittyPlay's stream, version 2: WebRTC first (the server's docs/GAMING-STREAM.md). libwebrtc decodes with MediaCodec.
    implementation("io.github.webrtc-sdk:android:144.7559.15")

    testImplementation("junit:junit:4.13.2")
}
