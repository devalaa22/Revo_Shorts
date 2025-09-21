plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services") // ✅ مهم لتشغيل Firebase
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.Revo.Shorts"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
       
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

   defaultConfig {
    applicationId = "com.Revo.Shorts"
    minSdk = flutter.minSdkVersion

    targetSdk = flutter.targetSdkVersion
    versionCode = 4
    versionName = "2.3.2"
    multiDexEnabled = true
}


 signingConfigs {
    create("release") {
        storeFile = file("C:\\Users\\momf\\Desktop\\Revo_Shorts\\android\\app\\Revo_Shorts.jks")
        storePassword = "Revo_Shorts"  // كلمة مرور keystore
        keyAlias = "Revo_Shorts"  // اسم alias الخاص بالمفتاح
        keyPassword = "Revo_Shorts"  // كلمة مرور المفتاح
    }
}

buildTypes {
    getByName("release") {
        signingConfig = signingConfigs.getByName("release")
        isMinifyEnabled = true  // لتقليص الكود
        isShrinkResources = true  // لتقليص الموارد
        proguardFiles(
            getDefaultProguardFile("proguard-android-optimize.txt"),
            "proguard-rules.pro"
        )
    }
}


}
dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib:1.9.10")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")  // فقط هذه
}

flutter {
    source = "../.."
}
