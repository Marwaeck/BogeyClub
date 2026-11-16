package club.bogey.android

import org.json.JSONObject
import java.io.File
import java.security.SecureRandom
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Datenablage der Android-App – gleiches Format wie Mac und Windows (windows/store.js):
 * alle Collections in daten.json, Bilder einzeln im Unterordner „Bilder“, einmal pro Tag vor der ersten
 * Änderung eine Kopie unter „Sicherungen“ (die letzten 30). Ordner: interner Speicher der App.
 */
class Store(private val folder: File) {
    class StoreException(val code: String) : Exception(code)

    private val dataFile = File(folder, "daten.json")
    private val photos = File(folder, "Bilder")
    private val backups = File(folder, "Sicherungen")
    private var backedUpToday = false
    private val data = sortedMapOf<String, java.util.SortedMap<String, JSONObject>>()

    init {
        photos.mkdirs()
        if (dataFile.exists()) {
            val obj = JSONObject(dataFile.readText())   // wirft bei beschädigter Datei
            for (coll in obj.keys()) {
                val docs = obj.optJSONObject(coll) ?: continue
                val map = sortedMapOf<String, JSONObject>()
                for (id in docs.keys()) docs.optJSONObject(id)?.let { map[id] = it }
                data[coll] = map
            }
        }
    }

    @Synchronized
    fun allJSON(): String = toJSON().toString()

    @Synchronized
    fun set(coll: String, id: String, json: String) {
        if (!validId(coll) || !validId(id)) throw StoreException("error")
        val doc = try { JSONObject(json) } catch (e: Exception) { throw StoreException("error") }
        data.getOrPut(coll) { sortedMapOf() }[id] = doc
        persist()
    }

    @Synchronized
    fun delete(coll: String, id: String) {
        val docs = data[coll] ?: return
        if (docs.remove(id) != null) persist()
    }

    private fun toJSON(): JSONObject {
        val root = JSONObject()
        for ((coll, docs) in data) {
            val o = JSONObject()
            for ((id, doc) in docs) o.put(id, doc)
            root.put(coll, o)
        }
        return root
    }

    private fun persist() {
        backupOncePerDay()
        val tmp = File(folder, "daten.json.tmp")
        tmp.writeText(toJSON().toString(2))
        if (!tmp.renameTo(dataFile)) { dataFile.delete(); if (!tmp.renameTo(dataFile)) throw StoreException("error") }
    }

    private fun backupOncePerDay() {
        if (backedUpToday || !dataFile.exists()) return
        backedUpToday = true
        try {
            backups.mkdirs()
            val day = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(Date())
            val target = File(backups, "daten-$day.json")
            if (!target.exists()) dataFile.copyTo(target)
            val files = backups.listFiles { f -> f.name.startsWith("daten-") }?.sortedBy { it.name } ?: emptyList()
            files.dropLast(30).forEach { it.delete() }
        } catch (e: Exception) { /* Sicherung ist ein Extra – Speichern geht trotzdem weiter */ }
    }

    fun addPhoto(bytes: ByteArray, type: String): String {
        val ext = EXT[type] ?: throw StoreException("unsupported_type")
        val id = ByteArray(16).also { SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it) }
        File(photos, "$id.$ext").writeBytes(bytes)
        return id
    }

    fun photo(id: String): Pair<File, String>? {
        if (!validId(id)) return null
        for ((type, ext) in EXT) {
            val f = File(photos, "$id.$ext")
            if (f.isFile) return f to type
        }
        return null
    }

    fun deletePhoto(id: String) { photo(id)?.first?.delete() }

    companion object {
        val EXT = linkedMapOf("image/jpeg" to "jpg", "image/png" to "png", "image/webp" to "webp", "image/gif" to "gif")
        private val ID = Regex("^[A-Za-z0-9_\\-.~:@+]+$")
        fun validId(id: String) = id.length in 1..200 && id != "." && id != ".." && ID.matches(id)
    }
}
