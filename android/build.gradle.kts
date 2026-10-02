allprojects {
    repositories {
        google()
        mavenCentral()
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

// Some plugins (e.g. flutter_timezone) ship their own android/build.gradle
// with Java and Kotlin compile targets that disagree with each other (seen
// in CI as "Inconsistent JVM-target compatibility... compileDebugJavaWithJavac
// (11) and compileDebugKotlin (1.8)"), which newer AGP/Kotlin Gradle Plugin
// versions now fail the build on. Force every subproject (the app module
// already sets this itself, so this mainly targets plugin modules) to the
// same Java/Kotlin target instead of patching each plugin individually.
subprojects {
    // afterEvaluate is unsafe here: the evaluationDependsOn(":app") above
    // forces early evaluation of some subprojects, so by the time a plain
    // `subprojects { afterEvaluate {...} }` runs, those are already
    // evaluated ("Cannot run Project.afterEvaluate(Action) when the project
    // is already evaluated"). withPlugin fires on plugin application
    // instead, which is safe regardless of evaluation order.
    // Only the "library" branch matters: every plugin module is an Android
    // library module, never "application" — :app is the sole application
    // module, and it already configures its own compileOptions directly in
    // app/build.gradle.kts. Reapplying the same thing to :app from here
    // conflicts once AGP finalizes that property ("sourceCompatibility has
    // been finalized"), so :app is deliberately left alone.
    pluginManager.withPlugin("com.android.library") {
        extensions.configure(com.android.build.api.dsl.LibraryExtension::class.java) {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }
    tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
