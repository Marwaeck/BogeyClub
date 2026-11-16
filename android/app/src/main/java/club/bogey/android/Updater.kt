package club.bogey.android

import org.json.JSONObject

/**
 * Update-Suche der Android-App – gleiche Regeln wie Mac und Windows (windows/updater.js):
 * neueste Version aus den GitHub-Releases, Tag „v1.2.3“, Datei „Bogey-Club-android-<Version>.apk“.
 */
object Updater {
    const val REPOSITORY = "Marwaeck/BogeyClub"
    const val LATEST_URL = "https://api.github.com/repos/$REPOSITORY/releases/latest"
    const val ASSET_PREFIX = "Bogey-Club-android-"

    data class Release(val version: String, val notes: String, val pageURL: String, val assetURL: String?)

    fun parseRelease(json: String): Release {
        val o = JSONObject(json)
        val assets = o.optJSONArray("assets")
        var asset: String? = null
        if (assets != null) for (i in 0 until assets.length()) {
            val a = assets.optJSONObject(i) ?: continue
            val name = a.optString("name")
            if (name.startsWith(ASSET_PREFIX) && name.lowercase().endsWith(".apk")) { asset = a.optString("browser_download_url"); break }
        }
        return Release(
            version = o.getString("tag_name").removePrefix("v").removePrefix("V"),
            notes = o.optString("body").trim(),
            pageURL = o.getString("html_url"),
            assetURL = asset?.takeIf { it.isNotBlank() }
        )
    }

    /** Versionen zahlenweise vergleichen (fehlende Stellen = 0, Zusätze nach „-“ ignoriert). */
    fun isNewer(candidate: String, current: String): Boolean {
        fun parts(v: String) = v.split("-")[0].split(".").map { it.toIntOrNull() ?: 0 }
        val a = parts(candidate); val b = parts(current)
        for (i in 0 until maxOf(a.size, b.size)) {
            val x = a.getOrElse(i) { 0 }; val y = b.getOrElse(i) { 0 }
            if (x != y) return x > y
        }
        return false
    }
}
