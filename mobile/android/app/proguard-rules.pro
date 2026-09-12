# Flutter and FFmpegKit ProGuard / R8 Rules
-keep class io.flutter.** { *; }
-keep class com.shiva.matchtool.** { *; }
-keep class com.antonkarpenko.ffmpegkit.** { *; }
-dontwarn com.antonkarpenko.ffmpegkit.**
-keep class com.arthenica.ffmpegkit.** { *; }
-dontwarn com.arthenica.ffmpegkit.**
