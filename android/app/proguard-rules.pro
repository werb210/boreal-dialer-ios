# BOREAL_ANDROID_DIALER_v1
# Twilio Voice uses JNI and reflection: keep its classes (Twilio's own recommended rules).
-keep class com.twilio.** { *; }
-keep class tvo.webrtc.** { *; }
-dontwarn tvo.webrtc.**
-keep class com.twilio.voice.** { *; }
-keepattributes InnerClasses
# Tink (used by androidx.security) references annotations that are not on the classpath.
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
