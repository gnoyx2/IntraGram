import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 릴리즈 서명 키는 저장소에 없음. android/key.properties(gitignore됨)에
// storeFile / storePassword / keyAlias / keyPassword가 있을 때만 릴리즈 키로
// 서명함. 키 없이 release를 만들면 debug 서명 산출물이 release 이름으로 나와 배포본으로
// 착각되니 빌드를 멈춤. 시험용 debug 서명 release가 필요하면 allowDebugSigning 속성을 줌
// (ORG_GRADLE_PROJECT_allowDebugSigning=true). 절차와 검증은 RELEASING.md 참고.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.containsKey("storeFile")
val allowDebugSigning = project.findProperty("allowDebugSigning")?.toString() == "true"

gradle.taskGraph.whenReady {
    val releaseOutput = allTasks.any {
        it.project == project && (it.name == "assembleRelease" || it.name == "bundleRelease")
    }
    if (releaseOutput && !hasReleaseKey && !allowDebugSigning) {
        throw GradleException(
            "No release key (android/key.properties). Set it up as in RELEASING.md, " +
                "or set ORG_GRADLE_PROJECT_allowDebugSigning=true for a debug-signed test build.",
        )
    }
}

android {
    namespace = "com.yonghun0310.intragram"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications(18.x)가 java.time 등 최신 Java API를
        // 쓰는 AAR이라 core library desugaring이 꺼져 있으면
        // :app:checkDebugAarMetadata에서 빌드가 중단됨.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.yonghun0310.intragram"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // desugar_jdk_libs 1.2.2 — flutter_local_notifications 18.0.1 설정 안내와
    // 로컬 Gradle 캐시(1.2.2) 버전. 임의로 올리지 않음.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:1.2.2")
}

flutter {
    source = "../.."
}
