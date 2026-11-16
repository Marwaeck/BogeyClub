// Bogey Club für Android – Gradle-Projekt. Bauen: npm run android (im Projektordner) oder GitHub Actions.
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "BogeyClub"
include(":app")
