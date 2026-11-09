import java.util.Properties
plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "org.dnet.dnet"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "org.dnet.dnet"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Android 10. The project supports Android 10 and later.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // A release is signed with the keystore named in android/key.properties
    // (storeFile, storePassword, keyAlias, keyPassword), which is never
    // committed: .gitignore blocks it. Without that file the release is
    // signed with the debug key, and the build says so loudly, so a debug-
    // signed APK is never shipped by mistake.
    val keyProperties = Properties()
    val keyFile = rootProject.file("key.properties")
    if (keyFile.exists()) {
        keyFile.inputStream().use { keyProperties.load(it) }
    }
    signingConfigs {
        if (keyFile.exists()) {
            create("release") {
                storeFile = rootProject.file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (keyFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "WARNING: android/key.properties not found; the release " +
                        "APK is signed with the DEBUG key. Do not publish it.",
                )
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

// A release build also puts the finished APK at dist/DNet-Android.apk at the
// top of the repository, the one place finished builds go. It replaces the
// one from the build before, so there is only ever one.
val distApk = rootProject.projectDir.resolve("../../dist/DNet-Android.apk").canonicalFile
val releaseApk = layout.buildDirectory.file("outputs/apk/release/app-release.apk")
tasks.matching { it.name == "assembleRelease" }.configureEach {
    doLast {
        val apk = releaseApk.get().asFile
        check(apk.exists()) { "No release APK at $apk" }
        distApk.parentFile.mkdirs()
        apk.copyTo(distApk, overwrite = true)
        logger.lifecycle("DNet: the app is at $distApk")
    }
}

flutter {
    source = "../.."
}

// The Rust core: identity, encryption and storage. Cargo builds it for each
// kind of Android processor and the results are packed into the app. Cargo
// and the Rust Android targets must be installed; see the top-level README.
val coreDir = rootProject.projectDir.resolve("../../core").canonicalFile
// Gradle packs native libraries from here. The folder is generated, and is
// listed in .gitignore.
val coreLibs = projectDir.resolve("src/main/jniLibs")
val rustTargets = mapOf(
    "arm64-v8a" to "aarch64-linux-android",
    "armeabi-v7a" to "armv7-linux-androideabi",
    "x86_64" to "x86_64-linux-android",
)
val onWindows = System.getProperty("os.name").lowercase().contains("windows")
val ndkHost = when {
    onWindows -> "windows-x86_64"
    System.getProperty("os.name").lowercase().contains("mac") -> "darwin-x86_64"
    else -> "linux-x86_64"
}

val packCore = rustTargets.map { (abi, triple) ->
    val taskSuffix = abi.replace("-", "").replace("_", "")
    // The NDK names its ARM 32-bit compiler differently from Rust's target.
    val clangTarget = if (triple.startsWith("armv7")) "armv7a-linux-androideabi" else triple
    val library = coreDir.resolve("target/$triple/release/libdnet_core.so")

    val cargo = tasks.register<Exec>("cargoBuildCore$taskSuffix") {
        val ndk = androidComponents.sdkComponents.ndkDirectory
        workingDir = coreDir
        commandLine("cargo", "build", "--release", "--lib", "--target", triple)
        inputs.dir(coreDir.resolve("src"))
        inputs.file(coreDir.resolve("Cargo.toml"))
        inputs.file(coreDir.resolve("Cargo.lock"))
        outputs.file(library)
        doFirst {
            // minSdk 29, to match the app.
            val linker = ndk.get().asFile.resolve(
                "toolchains/llvm/prebuilt/$ndkHost/bin/${clangTarget}29-clang" +
                    if (onWindows) ".cmd" else "",
            )
            environment(
                "CARGO_TARGET_${triple.uppercase().replace('-', '_')}_LINKER",
                linker.absolutePath,
            )
        }
    }
    tasks.register<Copy>("packCore$taskSuffix") {
        dependsOn(cargo)
        from(library)
        into(coreLibs.resolve(abi))
    }
}

tasks.named("preBuild") { dependsOn(packCore) }
