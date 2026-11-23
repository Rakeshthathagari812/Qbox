# Razorpay's payment screen (from Razorpay's Android setup guide).
# Without these, the release build can break the payment screen.
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keepattributes JavascriptInterface
-keepattributes *Annotation*
-dontwarn com.razorpay.**
-keep class com.razorpay.** {*;}
-optimizations !method/inlining/*
-keepclasseswithmembers class * {
    public void onPayment*(...);
}
# Razorpay's optional Google Pay support refers to classes that are not in this app.
-dontwarn com.google.android.apps.nbu.paisa.inapp.client.api.**
-dontwarn proguard.annotation.Keep
-dontwarn proguard.annotation.KeepClassMembers
