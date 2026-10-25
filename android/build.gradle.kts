// AGP 9 has built-in Kotlin (KGP 2.2.10): no kotlin-android plugin. The Compose Compiler plugin
// is still required when buildFeatures.compose = true, and must match the built-in Kotlin version.
plugins {
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.2.10" apply false
}
