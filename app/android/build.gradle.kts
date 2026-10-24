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

// lintVital (scan « fatal only » des builds release) : désactivé sur tous
// les modules — app et plugins compris. Deux raisons :
// 1. Bug AGP 9 / KGP : le lint charge le frontend Kotlin FIR dans le daemon
//    Gradle et crashe (OutOfMemoryError: Metaspace) sur des plugins tiers
//    qui appliquent encore KGP (firebase_core, flutter_contacts) — ex.
//    :image_picker_android:lintVitalAnalyzeRelease ;
// 2. Aucune valeur pour une app Flutter : le code métier est en Dart, et le
//    Play Store applique ses propres contrôles au téléversement de l'AAB.
// API Gradle pure (pas d'import AGP) : la tâche est simplement « skipped ».
subprojects {
    tasks.matching { it.name.startsWith("lintVital") }.configureEach {
        enabled = false
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
