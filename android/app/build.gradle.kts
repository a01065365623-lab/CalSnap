import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.kbraingames.calsnap"
    // targetSdk(36) 이상이어야 하며, compileSdk는 targetSdk보다 낮을 수 없다.
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.kbraingames.calsnap"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // flutter_tts는 minSdk 24 이상을 요구한다(Flutter 기본값 21보다 높음).
        minSdk = 24
        // Google Play는 신규/업데이트 앱에 targetSdk 36(Android 16) 이상을 요구한다.
        // flutter.targetSdkVersion에 암묵적으로 맡기면 Flutter SDK 업그레이드 시 검토
        // 없이 값이 바뀔 수 있어 명시적으로 고정한다.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // AdMob 앱 ID: 기본은 실제 ID, debug 빌드만 Google 테스트 앱 ID로 덮어쓴다
        // (lib/config/ad_config.dart의 kDebugMode 분기와 같은 기준, 값은 lib/config/ad_ids.dart와 동일).
        manifestPlaceholders["admobAppId"] = "ca-app-pub-9075706979713157~1512052827"
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        debug {
            manifestPlaceholders["admobAppId"] = "ca-app-pub-3940256099942544~3347511713"
        }
        release {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}
