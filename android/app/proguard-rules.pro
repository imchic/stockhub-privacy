# Flutter 관련 설정
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Gson 관련 설정 (JSON 처리용)
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class sun.misc.Unsafe { *; }
-keep class com.google.gson.stream.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# HTTP 관련 설정
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn retrofit2.**

# WebView 관련 설정
-keep class android.webkit.** { *; }
-keep class * extends android.webkit.** { *; }

# 모델 클래스 보존 (JSON 직렬화용)
-keep class com.imchic.stockhub.** { *; }

# 일반적인 설정
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Google Play Core Split Compat 관련 설정
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
-keep class com.google.android.play.core.splitcompat.** { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }

# Flutter PlayStore DeferredComponentManager 관련 설정
-keep class io.flutter.embedding.engine.deferredcomponents.PlayStoreDeferredComponentManager { *; }
-keep class io.flutter.embedding.android.FlutterPlayStoreSplitApplication { *; }

# R8 full mode 설정
-allowaccessmodification
-repackageclasses