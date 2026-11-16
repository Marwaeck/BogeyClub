package club.bogey.android

import android.annotation.SuppressLint
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import android.util.Base64
import android.webkit.JavascriptInterface
import android.webkit.MimeTypeMap
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.webkit.WebViewAssetLoader
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Bogey Club für Android: die Bogey-Club-Oberfläche (web/index.html) in einer WebView, ohne Claude.
 * Daten und Bilder liegen auf dem Handy, Scorekarten liest die mitgelieferte Texterkennung (Tesseract)
 * offline. Aufbau wie die Windows-App: Seiten unter https://appassets.androidplatform.net/…, Bilder unter
 * /_blob/<id>, Befehle der Oberfläche über window.BogeyAndroid (siehe mac/runtime.js).
 */
class MainActivity : ComponentActivity() {
    private lateinit var web: WebView
    private lateinit var store: Store
    private val worker = Executors.newSingleThreadExecutor()

    private var fileCallback: ValueCallback<Array<Uri>>? = null
    private var cameraUri: Uri? = null
    private var pendingSave: Pair<Int, ByteArray>? = null

    private val pickFile = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        val uris = WebChromeClient.FileChooserParams.parseResult(r.resultCode, r.data)
        fileCallback?.onReceiveValue(uris ?: arrayOf())
        fileCallback = null
    }

    private val takePhoto = registerForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val uri = cameraUri
        fileCallback?.onReceiveValue(if (ok && uri != null) arrayOf(uri) else arrayOf())
        fileCallback = null
    }

    private val saveFile = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        val (id, bytes) = pendingSave ?: return@registerForActivityResult
        pendingSave = null
        val uri = r.data?.data
        if (r.resultCode != RESULT_OK || uri == null) { reply(id, JSONObject().put("error", "declined")); return@registerForActivityResult }
        worker.execute {
            try {
                contentResolver.openOutputStream(uri)?.use { it.write(bytes) } ?: throw IllegalStateException("kein Ziel")
                reply(id, JSONObject())
            } catch (e: Exception) { reply(id, JSONObject().put("error", "error")) }
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            store = Store(File(filesDir, "Bogey Club"))
        } catch (e: Exception) {
            AlertDialog.Builder(this).setTitle("Bogey Club")
                .setMessage("Die Bogey-Club-Daten konnten nicht geöffnet werden (daten.json ist beschädigt). Im Ordner „Sicherungen“ liegen tägliche Kopien.")
                .setPositiveButton("Beenden") { _, _ -> finish() }.setCancelable(false).show()
            return
        }

        WindowCompat.setDecorFitsSystemWindows(window, false)
        val root = FrameLayout(this).apply { setBackgroundColor(Color.parseColor("#EEF3EF")) }
        web = WebView(this)
        root.addView(web, FrameLayout.LayoutParams(-1, -1))
        setContentView(root)
        WindowCompat.getInsetsController(window, root).isAppearanceLightStatusBars = true
        ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.ime() or WindowInsetsCompat.Type.displayCutout())
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            WindowInsetsCompat.CONSUMED
        }

        val loader = WebViewAssetLoader.Builder()
            .addPathHandler("/_blob/") { path ->
                store.photo(path)?.let { (file, type) -> WebResourceResponse(type, null, FileInputStream(file)) }
            }
            .addPathHandler("/", WebViewAssetLoader.AssetsPathHandler(this))
            .build()

        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = true
            mediaPlaybackRequiresUserGesture = true
            setSupportMultipleWindows(false)
        }
        web.addJavascriptInterface(Bridge(), "BogeyAndroid")
        web.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                val res = loader.shouldInterceptRequest(request.url) ?: return null
                if (request.url.path?.endsWith(".wasm") == true) res.mimeType = "application/wasm"
                return res
            }
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val url = request.url
                if (url.host == APP_HOST) return false
                openExternal(url)   // Apple Karten, Google Maps … im Browser bzw. in der passenden App
                return true
            }
            override fun onRenderProcessGone(view: WebView, detail: android.webkit.RenderProcessGoneDetail): Boolean {
                recreate(); return true
            }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onShowFileChooser(view: WebView, callback: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean {
                fileCallback?.onReceiveValue(null)
                fileCallback = callback
                val images = params.acceptTypes.any { it.startsWith("image/") }
                return try {
                    if (params.isCaptureEnabled && images) {
                        val dir = File(cacheDir, "camera").apply { mkdirs() }
                        dir.listFiles()?.forEach { it.delete() }
                        val uri = FileProvider.getUriForFile(this@MainActivity, "$packageName.files", File(dir, "foto-${System.currentTimeMillis()}.jpg"))
                        cameraUri = uri
                        takePhoto.launch(uri)
                    } else {
                        pickFile.launch(params.createIntent())
                    }
                    true
                } catch (e: ActivityNotFoundException) {
                    fileCallback = null
                    if (params.isCaptureEnabled) toast("Keine Kamera-App gefunden.") else toast("Keine Dateiauswahl gefunden.")
                    false
                }
            }
        }

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (web.canGoBack()) web.goBack() else { isEnabled = false; onBackPressedDispatcher.onBackPressed() }
            }
        })

        if (savedInstanceState != null) web.restoreState(savedInstanceState)
        else web.loadUrl("https://$APP_HOST/index.html")

        checkForUpdates()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        if (::web.isInitialized) web.saveState(outState)
    }

    override fun onDestroy() {
        if (::web.isInitialized) web.destroy()
        worker.shutdown()
        super.onDestroy()
    }

    // ---------- Befehle der Oberfläche (dieselben wie Mac und Windows) ----------
    inner class Bridge {
        @JavascriptInterface
        fun post(id: Int, message: String) {
            worker.execute {
                val msg = try { JSONObject(message) } catch (e: Exception) { JSONObject() }
                try {
                    handle(id, msg)?.let { reply(id, it) }
                } catch (e: Store.StoreException) {
                    reply(id, JSONObject().put("error", e.code))
                } catch (e: Exception) {
                    reply(id, JSONObject().put("error", "error"))
                }
            }
        }
    }

    /** Liefert die Antwort – oder null, wenn sie später kommt (Sichern-Dialog). */
    private fun handle(id: Int, msg: JSONObject): Any? {
        fun s(k: String) = msg.optString(k, "")
        return when (msg.optString("cmd")) {
            "db.load" -> store.allJSON()
            "db.set" -> { store.set(s("coll"), s("id"), s("data")); JSONObject() }
            "db.delete" -> { store.delete(s("coll"), s("id")); JSONObject() }
            "assets.upload" -> {
                val photo = store.addPhoto(Base64.decode(s("base64"), Base64.DEFAULT), s("type"))
                JSONObject().put("id", photo).put("url", "/_blob/$photo")
            }
            "assets.delete" -> { store.deletePhoto(s("id")); JSONObject() }
            "download.save" -> {
                val name = s("filename").ifBlank { "download" }
                val bytes = Base64.decode(s("base64"), Base64.DEFAULT)
                val ext = name.substringAfterLast('.', "").lowercase()
                val type = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
                runOnUiThread {
                    pendingSave?.let { (old, _) -> reply(old, JSONObject().put("error", "declined")) }
                    pendingSave = id to bytes
                    try {
                        saveFile.launch(Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType(type).putExtra(Intent.EXTRA_TITLE, name))
                    } catch (e: ActivityNotFoundException) {
                        pendingSave = null
                        reply(id, JSONObject().put("error", "error"))
                    }
                }
                null
            }
            else -> JSONObject().put("error", "unknown_command")
        }
    }

    /** Antwort an mac/runtime.js: window.__bogeyReply(id, <JSON-Wert>). */
    private fun reply(id: Int, value: Any) {
        val json = if (value is String) JSONObject.quote(value) else value.toString()
        runOnUiThread { if (::web.isInitialized) web.evaluateJavascript("window.__bogeyReply && window.__bogeyReply($id, $json)", null) }
    }

    private fun openExternal(uri: Uri) {
        if (uri.scheme !in setOf("http", "https", "mailto", "geo", "tel")) return
        try { startActivity(Intent(Intent.ACTION_VIEW, uri)) } catch (e: ActivityNotFoundException) { toast("Keine App zum Öffnen gefunden.") }
    }

    private fun toast(text: String) = runOnUiThread { Toast.makeText(this, text, Toast.LENGTH_LONG).show() }

    // ---------- Updater: GitHub-Releases, höchstens einmal am Tag ----------
    private fun checkForUpdates() {
        val prefs = getSharedPreferences("einstellungen", Context.MODE_PRIVATE)
        if (System.currentTimeMillis() - prefs.getLong("updateLastCheck", 0) < 24 * 3600 * 1000L) return
        prefs.edit().putLong("updateLastCheck", System.currentTimeMillis()).apply()
        val current = BuildConfig.VERSION_NAME
        Thread {
            val release = try {
                val c = URL(Updater.LATEST_URL).openConnection() as HttpURLConnection
                c.connectTimeout = 10000; c.readTimeout = 15000
                c.setRequestProperty("Accept", "application/vnd.github+json")
                c.setRequestProperty("User-Agent", "BogeyClub-Android/$current")
                if (c.responseCode != 200) return@Thread
                Updater.parseRelease(c.inputStream.bufferedReader().use { it.readText() })
            } catch (e: Exception) { return@Thread }
            if (!Updater.isNewer(release.version, current) || prefs.getString("updateSkip", null) == release.version) return@Thread
            runOnUiThread {
                if (isFinishing) return@runOnUiThread
                AlertDialog.Builder(this)
                    .setTitle("Bogey Club ${release.version} ist verfügbar")
                    .setMessage("Installiert ist $current. Deine Spieler, Plätze und Runden bleiben erhalten." +
                        (if (release.notes.isNotEmpty()) "\n\nNeu:\n${release.notes.take(700)}" else ""))
                    .setPositiveButton("Herunterladen") { _, _ -> openExternal(Uri.parse(release.assetURL ?: release.pageURL)) }
                    .setNegativeButton("Später", null)
                    .setNeutralButton("Überspringen") { _, _ -> prefs.edit().putString("updateSkip", release.version).apply() }
                    .show()
            }
        }.start()
    }

    companion object {
        const val APP_HOST = "appassets.androidplatform.net"
    }
}
