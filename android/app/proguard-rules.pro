# Xray-core (gomobile): классы вызываются из Go через JNI — R8 не должен их удалять.
-keep class libv2ray.** { *; }
-keep class go.** { *; }
-dontwarn libv2ray.**
-dontwarn go.**
