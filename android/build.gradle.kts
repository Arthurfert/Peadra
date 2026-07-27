allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Flutter 3.44.4 uses AGP 9.0.1, but the jni 1.0.1 Gradle build expects
// kotlin-android to be applied manually when AGP >= 9 (its built-in Kotlin
// extension is not available in this version). Apply it to any subproject
// that has the Android plugin so the kotlin {} extension is registered.
subprojects {
    pluginManager.withPlugin("com.android.application") {
        apply(plugin = "org.jetbrains.kotlin.android")
    }
    pluginManager.withPlugin("com.android.library") {
        apply(plugin = "org.jetbrains.kotlin.android")
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
