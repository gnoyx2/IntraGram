import java.util.Properties

plugins {
    id("com.android.application")
    // Flutter Gradle 플러그인은 Android·Kotlin 플러그인 다음에 적용해야 함
    id("dev.flutter.flutter-gradle-plugin")
}

// 릴리즈 서명 키는 저장소에 없음. android/key.properties(gitignore됨)에 storeFile·storePassword·keyAlias·keyPassword가
// 있을 때만 릴리즈 키로 서명함. 키 없이 release를 만들면 debug 서명 산출물이 release 이름으로 나와 배포본으로 착각할 수 있어서
// 빌드를 멈춤. 시험용 debug 서명 release가 필요하면 allowDebugSigning 속성을 줌 (ORG_GRADLE_PROJECT_allowDebugSigning=true).
// 절차와 검증은 RELEASING.md에 있음
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
        // flutter_local_notifications(18.x) AAR이 java.time 같은 최신 Java API를 써서 core library desugaring이 꺼져 있으면
        // :app:checkDebugAarMetadata에서 빌드가 멈춤
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.yonghun0310.intragram"
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
    // flutter_local_notifications 18.0.1 설정 안내에 맞춰 1.2.2로 고정함 (임의로 올리지 않음)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:1.2.2")
}

flutter {
    source = "../.."
}
