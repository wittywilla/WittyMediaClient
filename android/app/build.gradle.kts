// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

// Peer to peer is WittyMediaServer's connector library in app/libs. It decides which sources and dependencies the app is
// built with, so when it is missing and an installable build is asked for (sideload or release), it is built here, while
// the build is set up: android/scripts/build-wittyconnect.sh --if-available, which skips with a warning where Go, the
// NDK or the server's source isn't there. Debug builds and unit tests don't wait for it.
fun wittyconnectAar(): File? = file("libs/wittyconnect.aar").takeIf { it.isFile && it.length() > 0 }
val installable = gradle.startParameter.taskNames.any { t -> listOf("sideload", "release", "bundle").any { t.contains(it, ignoreCase = true) } }
if (wittyconnectAar() == null && installable && findProperty("p2p") != "off") {
    logger.lifecycle("Peer to peer: app/libs/wittyconnect.aar is missing, so it is built first (android/scripts/build-wittyconnect.sh).")
    val run = ProcessBuilder("bash", rootProject.file("scripts/build-wittyconnect.sh").path, "--if-available")
        .directory(rootProject.projectDir).inheritIO().start()
    if (run.waitFor() != 0) logger.warn("Peer to peer: building the library failed (see above).")
}
val wittyconnect: File? = wittyconnectAar()

// Without the library the app builds, but can't reach a server from away and offers no way to: say so on every build,
// and stop when it is asked for (-Pp2p=required, as release builds should be). -Pp2p=off skips building it.
if (wittyconnect == null) {
    val how = "Build it with: gradle :app:wittyconnect (or bash android/scripts/build-wittyconnect.sh); it needs Go, the NDK and a WittyMediaServer checkout."
    if (findProperty("p2p") == "required") throw GradleException("Peer to peer is required (-Pp2p=required) but app/libs/wittyconnect.aar is missing. $how")
    logger.warn("\nWARNING: app/libs/wittyconnect.aar is missing: this build can't connect peer to peer (no Join with a link or code, no From away). $how\n")
}

// One command for the library: android/scripts/build-wittyconnect.sh, which finds WittyMediaServer's source beside this
// repository (or WITTYMEDIASERVER_SRC) and builds its connector with gomobile into app/libs.
tasks.register<Exec>("wittyconnect") {
    group = "build"
    description = "Builds the peer-to-peer library (app/libs/wittyconnect.aar) from WittyMediaServer's source."
    workingDir = rootProject.projectDir
    commandLine("bash", "scripts/build-wittyconnect.sh")
}

// Android installs an update over the app only when it is signed with the same key and has a higher versionCode, and
// releases up to 0.6.0 broke the first rule: each was signed with the debug key of the machine that built it, a new one
// every time (docs/ANDROID-SIGNING.md). So:
//
// The versionCode is worked out from the versionName, (major * 10000 + minor * 100 + patch) * 100, and so goes up with
// every version without anyone remembering to raise it: 0.6.1 is 60100. The last two digits are spare, for a rebuild of
// the same version. All five APKs of a release share it, so any one of them can replace another.
fun versionCodeOf(name: String): Int {
    val m = Regex("""(\d+)\.(\d+)\.(\d+)""").matchEntire(name)
        ?: throw GradleException("versionName \"$name\" isn't x.y.z: the Android versionCode is worked out from it")
    val (major, minor, patch) = m.destructured.toList().map { it.toInt() }
    if (minor > 99 || patch > 99 || major > 2099) throw GradleException("versionName \"$name\" is out of range for a versionCode")
    return (major * 10000 + minor * 100 + patch) * 100
}

// The release key is the one permanent key every published APK is signed with. It is never in this repository: the
// release workflow writes it from the android-release environment's secrets and names it with these variables. Without
// them a release build comes out unsigned, which is all build.yml wants; -PreleaseSigning=required (release.yml) makes
// a missing key a failure, so a release can never fall back to a debug key or a new one.
val releaseKeystore: File? = System.getenv("WMC_ANDROID_KEYSTORE")?.takeIf { it.isNotBlank() }?.let { file(it) }
if (findProperty("releaseSigning") == "required") {
    val missing = listOf("WMC_ANDROID_KEYSTORE", "WMC_ANDROID_KEYSTORE_PASSWORD", "WMC_ANDROID_KEY_ALIAS")
        .filter { System.getenv(it).isNullOrBlank() }
    if (missing.isNotEmpty() || releaseKeystore?.isFile != true) {
        throw GradleException("The release key is required (-PreleaseSigning=required) but isn't there: ${missing.ifEmpty { listOf("the keystore file") }.joinToString()}. See docs/ANDROID-SIGNING.md.")
    }
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
        versionName = "0.6.3"
        versionCode = versionCodeOf(versionName!!)
        // The screens' accessibility checks (src/androidTest), run by hand against a signed-in debug build.
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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

    // Peer to peer: the server's connector library, which android/scripts/build-wittyconnect.sh puts in app/libs.
    // With it, the bridge that calls it is compiled and its licences go into the app; without it, the bridge that
    // says it isn't there, and the app builds and runs the same without connecting from away.
    sourceSets.getByName("main").kotlin.directories.add(if (wittyconnect != null) "src/p2p/kotlin" else "src/nop2p/kotlin")
    if (wittyconnect != null) sourceSets.getByName("main").assets.directories.add("libs/wittyconnect-notices")

    signingConfigs {
        if (releaseKeystore != null) {
            create("release") {
                storeFile = releaseKeystore
                storePassword = System.getenv("WMC_ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("WMC_ANDROID_KEY_ALIAS")
                // A PKCS12 keystore, as docs/ANDROID-SIGNING.md makes, has one password for the store and the key.
                keyPassword = System.getenv("WMC_ANDROID_KEY_PASSWORD")?.takeIf { it.isNotBlank() } ?: storePassword
                // v1 for Android 6, v2 for 7 and later, and v3 so the key can be rotated one day without an uninstall.
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        getByName("release") {
            // The APKs that are published. Unsigned when the release key isn't given (see above).
            signingConfigs.findByName("release")?.let { signingConfig = it }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        // Release speed, signed with the throwaway debug key. For trying the app on a device without the release key,
        // and for pull requests' builds. Never published: each machine's debug key is different, so one of these can't
        // update another, or a release. Debug builds run far slower on a TV stick.
        create("sideload") {
            initWith(getByName("release"))
            signingConfig = signingConfigs.getByName("debug")
            matchingFallbacks += "release"
        }
    }

    lint {
        // androidx.compose.ui.lint.ConfigurationScreenWidthHeightDetector crashes the lint run on some files
        // ("No fir element was found for KtParameter", seen in player/PlayerScreen.kt) and only ever gives a
        // Warning that suggests LocalWindowInfo. Switched off until the Compose lint jar fixes it.
        disable += "ConfigurationScreenWidthHeight"
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
    // An Android TV's home screen: the app's own channel and the Watch Next row (data/TvHome.kt).
    implementation("androidx.tvprovider:tvprovider:1.0.0")

    wittyconnect?.let { implementation(files(it)) }

    testImplementation("junit:junit:4.13.2")

    // The screens' accessibility checks: the Accessibility Test Framework through Compose and Espresso.
    androidTestImplementation(platform("androidx.compose:compose-bom:2026.09.00"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4-accessibility")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.7.0")
    androidTestImplementation("androidx.test.espresso:espresso-accessibility:3.7.0")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.3.0")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}

// The server's SDUI conformance fixtures (its pkg/sdui/conformance/fixtures, 3 MB of JSON) are read where they are,
// not copied here: from -PsduiFixtures=<folder> or WMS_SDUI_FIXTURES, else from a server checkout beside this
// repository, else from .server in this one, as the build machines have it. Without them the conformance test is
// skipped, unless -PsduiFixturesRequired says that is a failure.
val sduiFixtures: File? = (
    listOfNotNull(providers.gradleProperty("sduiFixtures").orNull, providers.environmentVariable("WMS_SDUI_FIXTURES").orNull).map { rootDir.resolve(it) } +
        listOf("../../WittyMediaServer", "../../../WittyMediaServer", "../.server").map { rootDir.resolve("$it/pkg/sdui/conformance/fixtures") }
    ).firstOrNull { it.resolve("index.json").isFile }

tasks.withType<Test>().configureEach {
    sduiFixtures?.let {
        systemProperty("sdui.fixtures", it.canonicalPath)
        inputs.dir(it).withPropertyName("sduiFixtures").withPathSensitivity(PathSensitivity.RELATIVE)
    }
    if (providers.gradleProperty("sduiFixturesRequired").isPresent) systemProperty("sdui.fixtures.required", "1")
}
