package com.deeprows.receiver

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.Activity
import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.os.Environment
import android.os.SystemClock
import android.provider.Settings
import android.view.MotionEvent
import android.view.InputDevice
import androidx.core.content.FileProvider
import java.io.File
import android.webkit.JavascriptInterface
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceResponse
import java.io.ByteArrayInputStream
import java.io.FilterInputStream
import java.io.InputStream
import java.net.HttpURLConnection
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONObject
import java.net.URL

/**
 * Deeprowss TV: opens the hosted Deeprowss site full screen.
 *
 * The site's front page has two buttons:
 *  - Watch Movies      -> trending, Top 10, series, search, watch later / history
 *  - Connect with App  -> shows the QR code; scan it with the phone app to cast
 *
 * If the TV is offline a native screen offers Retry and the old manual address + PIN pairing.
 */
class MainActivity : Activity() {
    companion object {
        private const val RECEIVER_BASE = "https://deeprows.github.io/myflutter-app/receiver/"
        private const val RECEIVER_PAGE = RECEIVER_BASE + "#landing"
        private const val RECEIVER_LAYOUT = "desktop"

        // Ad / pop-under networks that embedded players must not reach (extended from receiver/adblock.json).
        @Volatile private var adHosts: Set<String> = setOf(
            "doubleclick.net", "googlesyndication.com", "googleadservices.com", "adservice.google.com", "popads.net",
            "popcash.net", "propellerads.com", "exoclick.com", "exosrv.com", "juicyads.com", "adsterra.com", "adcash.com",
            "clickadu.com", "hilltopads.net", "trafficjunky.com", "admaven.com", "monetag.com", "a-ads.com", "adnxs.com",
            "taboola.com", "outbrain.com"
        )
        @Volatile private var adBlockOn = true

        // ---- live TV headers (set by the receiver page through the DeeprowssTv bridge) ----
        // Web channel (iframe): the embed page is downloaded here with the Referer / User-Agent the phone app uses.
        @Volatile private var frameUrl = ""
        @Volatile private var frameReferer = ""
        @Volatile private var frameUa = ""
        // Direct stream (m3u8 / mpd / mp4): requests get the channel's Referer + User-Agent and a CORS allowance.
        @Volatile private var streamOn = false
        @Volatile private var streamReferer = ""
        @Volatile private var streamUa = ""

        private val SERVICE_HOSTS = Regex(
            "(^|\\.)(themoviedb\\.org|tmdb\\.org|githubusercontent\\.com|github\\.io|workers\\.dev|youtube\\.com|ytimg\\.com|googleapis\\.com|gstatic\\.com|jsdelivr\\.net|cdnjs\\.cloudflare\\.com)$",
            RegexOption.IGNORE_CASE
        )
        private val DROP_RESPONSE_HEADERS = setOf(
            "content-encoding", "content-length", "transfer-encoding", "connection", "keep-alive", "x-frame-options",
            "content-security-policy", "content-security-policy-report-only", "set-cookie", "strict-transport-security",
            "access-control-allow-origin", "access-control-allow-headers", "access-control-allow-methods",
            "access-control-expose-headers", "access-control-allow-credentials"
        )

        private fun cleanHttp(value: String?): String {
            val v = (value ?: "").trim().take(2000)
            return if (v.startsWith("http://", true) || v.startsWith("https://", true)) v else ""
        }

        private fun sameDoc(a: String, b: String) =
            a.substringBefore('#').trimEnd('/').equals(b.substringBefore('#').trimEnd('/'), ignoreCase = true)

        private fun originOf(url: String): String? = try {
            val u = Uri.parse(url)
            if (u.scheme.isNullOrEmpty() || u.host.isNullOrEmpty()) null
            else u.scheme + "://" + u.host + (if (u.port > 0) ":" + u.port else "")
        } catch (_: Exception) {
            null
        }

        private fun guessType(url: String): String {
            val path = (Uri.parse(url).path ?: "").lowercase()
            return when {
                path.endsWith(".m3u8") -> "application/vnd.apple.mpegurl"
                path.endsWith(".ts") -> "video/mp2t"
                path.endsWith(".mpd") -> "application/dash+xml"
                path.endsWith(".mp4") || path.endsWith(".m4s") -> "video/mp4"
                path.endsWith(".key") -> "application/octet-stream"
                else -> "application/octet-stream"
            }
        }

        private fun isAdHost(host: String?): Boolean {
            var h = host?.lowercase() ?: return false
            while (adBlockOn && h.isNotEmpty()) {
                if (adHosts.contains(h)) return true
                val i = h.indexOf('.')
                if (i < 0) break
                h = h.substring(i + 1)
            }
            return false
        }
    }

    private val receiverHost: String = Uri.parse(RECEIVER_PAGE).host.orEmpty()

    private var webView: WebView? = null
    private var customView: View? = null
    private var customViewCallback: WebChromeClient.CustomViewCallback? = null
    private lateinit var container: FrameLayout
    private var splashView: View? = null
    private var splashSpin: ObjectAnimator? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        refreshAdBlockList()
        container = FrameLayout(this).apply { setBackgroundColor(Color.rgb(7, 8, 10)) }
        setContentView(container)
        openSite(null, null)
    }

    // ------------------------------------------------------------------ website

    private fun openSite(host: String?, pin: String?) {
        val base = Uri.parse(RECEIVER_PAGE).buildUpon().appendQueryParameter("layout", RECEIVER_LAYOUT)
        if (!host.isNullOrBlank() && !pin.isNullOrBlank()) {
            base.appendQueryParameter("host", host).appendQueryParameter("pin", pin)
        }
        val url = base.build().toString()
        val allowedHost = Uri.parse(RECEIVER_PAGE).host

        val view = WebView(this).apply {
            setBackgroundColor(Color.rgb(7, 8, 10))
            isFocusable = true
            isFocusableInTouchMode = true
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            settings.loadsImagesAutomatically = true
            settings.javaScriptCanOpenWindowsAutomatically = false
            settings.setSupportMultipleWindows(false)
            // Phone remote: lets the receiver page tap the embedded player (cross-origin frames cannot be clicked from JS).
            addJavascriptInterface(TapBridge(), "DeeprowssTv")
            try { CookieManager.getInstance().setAcceptThirdPartyCookies(this, true) } catch (_: Exception) {}
            webChromeClient = object : WebChromeClient() {
                // Lets embedded players (iframes) go full screen.
                override fun onShowCustomView(view: View?, callback: CustomViewCallback?) {
                    if (view == null) {
                        callback?.onCustomViewHidden()
                        return
                    }
                    if (customView != null) hideCustomView()
                    customView = view
                    customViewCallback = callback
                    view.setBackgroundColor(Color.BLACK)
                    container.addView(
                        view,
                        FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    )
                    webView?.visibility = View.GONE
                }

                override fun onHideCustomView() {
                    hideCustomView()
                }
            }
            webViewClient = object : WebViewClient() {
                // Only the Deeprowss site may take over the page; embedded players load inside their frames.
                override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                    val req = request ?: return true
                    // Refuse known ad-network navigations in both the top page and embedded
                    // channel frames. Allow legitimate third-party stream/player frames.
                    if (isAdHost(req.url.host)) return true
                    return req.isForMainFrame && req.url.host != allowedHost
                }

                override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
                    if (isAdHost(request?.url?.host)) {
                        return WebResourceResponse("text/plain", "utf-8", 204, "No Content", emptyMap(), ByteArrayInputStream(ByteArray(0)))
                    }
                    if (request != null) {
                        val proxied = try { proxyTvRequest(request) } catch (_: Exception) { null }
                        if (proxied != null) return proxied
                    }
                    return super.shouldInterceptRequest(view, request)
                }

                override fun onPageCommitVisible(view: WebView?, url: String?) {
                    removeNativeSplash(true)
                }

                override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
                    if (request?.isForMainFrame == true) showOfflineScreen()
                }

                // Android 8+ can kill a WebView renderer independently of the app process.
                // Recover with a native screen rather than leaving a dead WebView on screen.
                override fun onRenderProcessGone(view: WebView?, detail: RenderProcessGoneDetail?): Boolean {
                    if (view === webView) runOnUiThread { showRendererCrashScreen() }
                    return true
                }
            }
        }
        webView?.destroy()
        webView = view
        container.removeAllViews()
        customView = null
        container.addView(
            view,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        )
        showNativeSplash()
        view.loadUrl(url)
        view.requestFocus()
    }

    // ------------------------------------------------------------------ splash

    /** Kodi-style splash: the app logo spins until the receiver page paints its first frame. */
    private fun showNativeSplash() {
        removeNativeSplash(false)
        val dm = resources.displayMetrics
        val size = (minOf(dm.widthPixels, dm.heightPixels) * 0.24f).toInt().coerceAtLeast((120 * dm.density).toInt())
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.rgb(8, 10, 16))
            isClickable = true
        }
        val logo = ImageView(this).apply {
            setImageResource(R.drawable.deeprowss_icon)
            scaleType = ImageView.ScaleType.FIT_CENTER
            cameraDistance = 9000f * dm.density
        }
        box.addView(logo, LinearLayout.LayoutParams(size, size))
        box.addView(
            label("DEEPROWSS", 26f, Color.WHITE, true).apply { letterSpacing = 0.34f },
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = (size * 0.22f).toInt() }
        )
        box.addView(
            label("CINEMA & LIVE TV", 13f, Color.rgb(111, 214, 251), true).apply { letterSpacing = 0.32f },
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = 10 }
        )
        splashSpin = ObjectAnimator.ofFloat(logo, View.ROTATION_Y, 0f, 360f).apply {
            duration = 2400
            interpolator = AccelerateDecelerateInterpolator()
            repeatCount = ValueAnimator.INFINITE
            start()
        }
        splashView = box
        container.addView(box, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        // Safety net: never leave the splash up if the page is slow or fails.
        box.postDelayed({ if (splashView === box) removeNativeSplash(true) }, 9000)
    }

    private fun removeNativeSplash(animate: Boolean) {
        val v = splashView ?: return
        splashView = null
        val spin = splashSpin
        splashSpin = null
        if (animate && v.isAttachedToWindow) {
            v.animate().alpha(0f).setDuration(350).setInterpolator(LinearInterpolator()).withEndAction {
                spin?.cancel()
                try { container.removeView(v) } catch (_: Exception) {}
            }.start()
        } else {
            spin?.cancel()
            try { container.removeView(v) } catch (_: Exception) {}
        }
    }

    /** Updates the ad-host list from the hosted receiver/adblock.json without needing a new APK. */
    private fun refreshAdBlockList() {
        Thread {
            try {
                val json = JSONObject(URL(RECEIVER_BASE + "adblock.json").readText())
                adBlockOn = json.optBoolean("enabled", true)
                val list = json.optJSONArray("hosts") ?: return@Thread
                val merged = adHosts.toMutableSet()
                for (i in 0 until list.length()) {
                    val h = list.optString(i).lowercase().trim()
                    if (Regex("[a-z0-9.-]{3,100}").matches(h)) merged.add(h)
                }
                adHosts = merged
            } catch (_: Exception) {
            }
        }.start()
    }

    // ------------------------------------------------------------------ live TV: same headers as the phone app

    /**
     * Web channels and direct streams only play on some hosts when the request carries the Referer / User-Agent
     * the Deeprowss phone app sends (the app loads them as if they came from its own site). A WebView cannot set
     * those headers on an iframe, so the request is made here and the answer handed back to the page.
     * Returns null (normal loading) for everything else or on any error.
     */
    private fun proxyTvRequest(req: WebResourceRequest): WebResourceResponse? {
        if (req.isForMainFrame) return null
        val scheme = req.url.scheme?.lowercase()
        if (scheme != "http" && scheme != "https") return null
        val host = req.url.host?.lowercase() ?: return null
        if (host == receiverHost || SERVICE_HOSTS.containsMatchIn(host)) return null
        val method = (req.method ?: "GET").uppercase()
        val target = req.url.toString()

        val fUrl = frameUrl
        val isFrame = fUrl.isNotEmpty() && method == "GET" && sameDoc(target, fUrl)
        val isStream = !isFrame && streamOn && (method == "GET" || method == "HEAD" || method == "OPTIONS") &&
            req.requestHeaders["Accept"]?.startsWith("image/") != true
        if (!isFrame && !isStream) return null

        val pageOrigin = "https://$receiverHost"
        if (isStream && method == "OPTIONS") {
            return WebResourceResponse("text/plain", "utf-8", 204, "No Content", corsHeaders(), ByteArrayInputStream(ByteArray(0)))
        }
        return fetchWithHeaders(
            req, target,
            if (isFrame) frameReferer else streamReferer,
            if (isFrame) frameUa else streamUa,
            isFrame, pageOrigin
        )
    }

    private fun corsHeaders(): MutableMap<String, String> = hashMapOf(
        "Access-Control-Allow-Origin" to "*",
        "Access-Control-Allow-Headers" to "*",
        "Access-Control-Allow-Methods" to "GET, HEAD, OPTIONS",
        "Access-Control-Expose-Headers" to "*"
    )

    private fun fetchWithHeaders(
        req: WebResourceRequest, firstUrl: String, referer: String, ua: String, forFrame: Boolean, pageOrigin: String
    ): WebResourceResponse? {
        var current = firstUrl
        var hops = 0
        val cookies = CookieManager.getInstance()
        while (true) {
            val c = URL(current).openConnection() as HttpURLConnection
            try {
                c.instanceFollowRedirects = false
                c.connectTimeout = 10000
                c.readTimeout = 25000
                c.requestMethod = (req.method ?: "GET").uppercase()
                for ((k, v) in req.requestHeaders) {
                    val lk = k.lowercase()
                    if (lk == "referer" || lk == "origin" || lk == "host" || lk == "accept-encoding" ||
                        lk == "cookie" || lk == "connection" || lk == "user-agent"
                    ) continue
                    c.setRequestProperty(k, v)
                }
                val agent = if (ua.isNotEmpty()) ua else req.requestHeaders["User-Agent"] ?: ""
                if (agent.isNotEmpty()) c.setRequestProperty("User-Agent", agent)
                if (referer.isNotEmpty()) {
                    c.setRequestProperty("Referer", referer)
                    if (!forFrame) originOf(referer)?.let { c.setRequestProperty("Origin", it) }
                }
                cookies.getCookie(current)?.let { if (it.isNotEmpty()) c.setRequestProperty("Cookie", it) }

                val code = c.responseCode
                for ((k, vals) in c.headerFields) {
                    if (k != null && k.equals("set-cookie", ignoreCase = true)) vals.forEach { cookies.setCookie(current, it) }
                }
                if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
                    val loc = c.getHeaderField("Location")
                    c.disconnect()
                    if (loc.isNullOrEmpty() || ++hops > 6) return null
                    current = URL(URL(current), loc).toString()
                    if (forFrame) {
                        // The page must end up on the real address so its own files load from there; keep adding the headers.
                        frameUrl = current
                        val safe = current.replace("\\", "\\\\").replace("\"", "%22").replace("<", "%3C")
                        val html = "<!doctype html><meta charset=utf-8><body style=\"background:#000\"><script>location.replace(\"$safe\")</script>"
                        return WebResourceResponse("text/html", "utf-8", 200, "OK", hashMapOf<String, String>(), ByteArrayInputStream(html.toByteArray()))
                    }
                    continue
                }
                if (code < 100 || code > 599 || code in 300..399) { c.disconnect(); return null }

                val body: InputStream = (if (code >= 400) c.errorStream else c.inputStream) ?: run { c.disconnect(); return null }
                val out: MutableMap<String, String> = if (forFrame) hashMapOf<String, String>() else corsHeaders()
                for ((k, vals) in c.headerFields) {
                    if (k == null || vals.isNullOrEmpty()) continue
                    val lk = k.lowercase()
                    if (lk == "content-security-policy" && forFrame) {
                        // Allow the embed to open inside the receiver page (the same relaxation the Windows app makes).
                        val v = vals.joinToString("; ").replace(Regex("frame-ancestors[^;]*;?", RegexOption.IGNORE_CASE), "").trim()
                        if (v.isNotEmpty()) out[k] = v
                        continue
                    }
                    if (lk in DROP_RESPONSE_HEADERS) continue
                    out[k] = vals.joinToString(", ")
                }
                val ct = c.contentType ?: guessType(current)
                val mime = ct.substringBefore(';').trim().ifEmpty { "application/octet-stream" }
                val charset = Regex("charset=([^;\\s]+)", RegexOption.IGNORE_CASE).find(ct)?.groupValues?.get(1)?.trim('"')
                val encoding = charset ?: if (mime.startsWith("text/") || mime.contains("json") || mime.contains("xml") || mime.contains("mpegurl")) "utf-8" else null
                val reason = (c.responseMessage ?: "").ifBlank { if (code < 400) "OK" else "Error" }
                return WebResourceResponse(mime, encoding, code, reason, out, DisconnectingStream(body, c))
            } catch (e: Exception) {
                try { c.disconnect() } catch (_: Exception) {}
                return null
            }
        }
    }

    private class DisconnectingStream(source: InputStream, private val conn: HttpURLConnection) : FilterInputStream(source) {
        override fun close() {
            try {
                super.close()
            } finally {
                try { conn.disconnect() } catch (_: Exception) {}
            }
        }
    }

    /** JavaScript bridge used by the receiver page: tap at a fraction of the screen. */
    inner class TapBridge {
        private var last = 0L

        /** A web channel is about to open in the TV iframe: its page is fetched with this Referer / User-Agent. Empty = normal loading. */
        @JavascriptInterface
        fun setFrame(url: String?, referer: String?, ua: String?) {
            val r = cleanHttp(referer)
            val agent = (ua ?: "").trim().take(500)
            val u = cleanHttp(url)
            frameUrl = if (u.isNotEmpty() && (r.isNotEmpty() || agent.isNotEmpty())) u else ""
            frameReferer = r
            frameUa = agent
            streamOn = false
        }

        /** A direct stream (m3u8 / mpd / mp4) is playing: its requests get the channel's Referer / User-Agent and CORS is allowed. */
        @JavascriptInterface
        fun setStream(referer: String?, ua: String?, on: Boolean) {
            streamReferer = cleanHttp(referer)
            streamUa = (ua ?: "").trim().take(500)
            streamOn = on
            if (on) frameUrl = ""
        }

        /** Download a new APK and hand it to Android's package installer. */
        @JavascriptInterface
        fun installUpdate(raw: String?) {
            val safe = cleanHttp(raw)
            if (safe.isEmpty() || !safe.substringBefore('?').lowercase().endsWith(".apk")) return
            runOnUiThread {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                    try { startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))) } catch (_: Exception) {}
                    return@runOnUiThread
                }
                try {
                    val request = DownloadManager.Request(Uri.parse(safe))
                        .setTitle("Deeprowss TV update")
                        .setDescription("Downloading the latest Deeprowss TV version")
                        .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                        .setDestinationInExternalFilesDir(this@MainActivity, Environment.DIRECTORY_DOWNLOADS, "deeprowss-tv-update.apk")
                    val manager = getSystemService(DOWNLOAD_SERVICE) as DownloadManager
                    val downloadId = manager.enqueue(request)
                    webView?.evaluateJavascript("window.deeprowssUpdateStarted && window.deeprowssUpdateStarted()", null)
                    val receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            if (intent?.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L) != downloadId) return
                            try { unregisterReceiver(this) } catch (_: Exception) {}
                            try {
                                val apk = File(getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "deeprowss-tv-update.apk")
                                if (!apk.exists() || apk.length() == 0L) return
                                val contentUri = FileProvider.getUriForFile(this@MainActivity, "$packageName.fileprovider", apk)
                                val install = Intent(Intent.ACTION_VIEW)
                                    .setDataAndType(contentUri, "application/vnd.android.package-archive")
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                startActivity(install)
                            } catch (_: Exception) {}
                        }
                    }
                    val filter = IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE)
                    if (Build.VERSION.SDK_INT >= 33) registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    else registerReceiver(receiver, filter)
                } catch (_: Exception) {}
            }
        }

        /** Fetch an M3U playlist through Android networking, bypassing WebView CORS restrictions. */
        @JavascriptInterface
        fun fetchPlaylist(raw: String?): String {
            val safe = cleanHttp(raw)
            if (safe.isEmpty()) return JSONObject().put("ok", false).put("error", "Invalid playlist URL").toString()
            var connection: HttpURLConnection? = null
            return try {
                connection = URL(safe).openConnection() as HttpURLConnection
                connection.instanceFollowRedirects = true
                connection.connectTimeout = 12000
                connection.readTimeout = 20000
                connection.setRequestProperty("Accept", "audio/x-mpegurl, application/vnd.apple.mpegurl, text/plain, */*")
                val status = connection.responseCode
                val stream = if (status in 200..299) connection.inputStream else connection.errorStream
                val body = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""
                if (body.length > 5_000_000) {
                    JSONObject().put("ok", false).put("error", "Playlist file is too large").toString()
                } else {
                    JSONObject().put("ok", status in 200..299).put("status", status)
                        .put("body", body).put("error", if (status in 200..299) "" else "HTTP $status").toString()
                }
            } catch (e: Exception) {
                JSONObject().put("ok", false).put("error", e.message ?: "Could not fetch playlist").toString()
            } finally {
                try { connection?.disconnect() } catch (_: Exception) {}
            }
        }

        /** The TV's system languages (best first), e.g. "fr-FR,en-US", so the page opens in the TV's language. */
        @JavascriptInterface
        fun getLocales(): String {
            return try {
                val cfg = android.content.res.Resources.getSystem().configuration
                val tags = ArrayList<String>()
                if (Build.VERSION.SDK_INT >= 24) {
                    val list = cfg.locales
                    for (i in 0 until list.size()) tags.add(list.get(i).toLanguageTag())
                } else {
                    @Suppress("DEPRECATION")
                    tags.add(cfg.locale.toLanguageTag())
                }
                tags.filter { it.isNotBlank() && it != "und" }.joinToString(",")
            } catch (_: Exception) { "" }
        }

        /** Power button next to the settings icon: close the TV app completely. */
        @JavascriptInterface
        fun exitApp() {
            runOnUiThread {
                try { finishAndRemoveTask() } catch (_: Exception) { finish() }
            }
        }

        /** Advert banner under the clock: open the advertiser's link (https/http/mailto) outside the WebView. */
        @JavascriptInterface
        fun openAd(raw: String?) {
            val v = (raw ?: "").trim().take(2000)
            if (!(v.startsWith("https://", true) || v.startsWith("http://", true) || v.startsWith("mailto:", true))) return
            val uri = try { Uri.parse(v) } catch (_: Exception) { return }
            runOnUiThread {
                try { startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (_: Exception) {}
            }
        }

        /** Open the approved payment / WhatsApp links outside the TV WebView. */
        @JavascriptInterface
        fun openExternal(raw: String?) {
            val safe = cleanHttp(raw)
            if (safe.isEmpty()) return
            val uri = try { Uri.parse(safe) } catch (_: Exception) { return }
            val host = (uri.host ?: "").lowercase()
            val allowed = host == "paystack.com" || host.endsWith(".paystack.com") ||
                host == "paystack.co" || host.endsWith(".paystack.co") ||
                host == "wa.me" || host == "api.whatsapp.com"
            if (!allowed) return
            runOnUiThread {
                try { startActivity(Intent(Intent.ACTION_VIEW, uri)) } catch (_: Exception) {}
            }
        }

        @JavascriptInterface
        fun tap(fx: Double, fy: Double) {
            val now = SystemClock.uptimeMillis()
            if (now - last < 250 || fx.isNaN() || fy.isNaN()) return
            last = now
            runOnUiThread {
                val view = webView ?: return@runOnUiThread
                val x = (fx.coerceIn(0.0, 1.0) * view.width).toFloat()
                val y = (fy.coerceIn(0.0, 1.0) * view.height).toFloat()
                val down = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, x, y, 0)
                view.dispatchTouchEvent(down)
                down.recycle()
                view.postDelayed({
                    val t = SystemClock.uptimeMillis()
                    val up = MotionEvent.obtain(now, t, MotionEvent.ACTION_UP, x, y, 0)
                    view.dispatchTouchEvent(up)
                    up.recycle()
                }, 60)
            }
        }
    }

    private fun hideCustomView() {
        val shown = customView ?: return
        container.removeView(shown)
        customView = null
        customViewCallback?.onCustomViewHidden()
        customViewCallback = null
        webView?.visibility = View.VISIBLE
        webView?.requestFocus()
    }

    // ------------------------------------------------------------------ native fallback screens

    private fun newScreen(): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER
        setPadding(64, 40, 64, 40)
        setBackgroundColor(Color.rgb(7, 8, 10))
    }

    private fun label(text: String, size: Float, color: Int, bold: Boolean = false) = TextView(this).apply {
        this.text = text
        textSize = size
        setTextColor(color)
        gravity = Gravity.CENTER
        if (bold) setTypeface(typeface, Typeface.BOLD)
    }

    private fun showScreen(screen: View) {
        webView?.destroy()
        webView = null
        customView = null
        container.removeAllViews()
        container.addView(
            screen,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        )
    }

    private fun showRendererCrashScreen() {
        val retry = Button(this).apply {
            text = "RELOAD DEEPROWSS"
            textSize = 18f
            isFocusable = true
            isFocusableInTouchMode = true
            setOnClickListener { openSite(null, null) }
        }
        val exit = Button(this).apply {
            text = "EXIT APP"
            textSize = 16f
            isFocusable = true
            isFocusableInTouchMode = true
            setOnClickListener { finish() }
        }
        val screen = newScreen()
        screen.addView(label("DEEPROWSS", 30f, Color.rgb(255, 196, 46), true), LinearLayout.LayoutParams(-1, -2))
        screen.addView(
            label("The receiver player stopped unexpectedly. Reload the page to continue.", 18f, Color.LTGRAY),
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = 18; bottomMargin = 28 }
        )
        screen.addView(retry, LinearLayout.LayoutParams(520, -2))
        screen.addView(exit, LinearLayout.LayoutParams(520, -2).apply { topMargin = 14 })
        showScreen(screen)
        retry.requestFocus()
    }

    private fun showOfflineScreen() {
        val screen = newScreen()
        val retry = Button(this).apply {
            text = "TRY AGAIN"
            textSize = 17f
            setOnClickListener { openSite(null, null) }
        }
        val manual = Button(this).apply {
            text = "MANUAL CONNECT (ADDRESS + PIN)"
            textSize = 15f
            setOnClickListener { showManualScreen() }
        }
        screen.addView(label("DEEPROWSS", 30f, Color.rgb(255, 196, 46), true), LinearLayout.LayoutParams(-1, -2))
        screen.addView(
            label("Can't reach Deeprowss. Check this TV's internet connection, then try again.", 18f, Color.LTGRAY),
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = 18; bottomMargin = 28 }
        )
        screen.addView(retry, LinearLayout.LayoutParams(520, -2))
        screen.addView(manual, LinearLayout.LayoutParams(520, -2).apply { topMargin = 14 })
        showScreen(screen)
        retry.requestFocus()
    }

    private fun showManualScreen() {
        val screen = newScreen()
        val address = EditText(this).apply {
            hint = "Phone address e.g. 192.168.1.20:12345"
            setSingleLine(true)
            textSize = 19f
            setTextColor(Color.WHITE)
            setHintTextColor(Color.GRAY)
            setPadding(20, 16, 20, 16)
            imeOptions = EditorInfo.IME_ACTION_NEXT
            isFocusable = true
            isFocusableInTouchMode = true
        }
        val pin = EditText(this).apply {
            hint = "Six-digit pairing code"
            setSingleLine(true)
            inputType = android.text.InputType.TYPE_CLASS_NUMBER
            textSize = 22f
            setTextColor(Color.WHITE)
            setHintTextColor(Color.GRAY)
            setPadding(20, 16, 20, 16)
            imeOptions = EditorInfo.IME_ACTION_GO
            isFocusable = true
            isFocusableInTouchMode = true
        }
        val connect = Button(this).apply {
            text = "CONNECT TO DEEPROWSS"
            textSize = 16f
            setOnClickListener { submitManual(address.text.toString(), pin.text.toString()) }
        }
        val back = Button(this).apply {
            text = "BACK"
            textSize = 14f
            setOnClickListener { showOfflineScreen() }
        }
        pin.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_GO) {
                submitManual(address.text.toString(), pin.text.toString())
                true
            } else false
        }
        screen.addView(label("MANUAL CONNECT", 28f, Color.WHITE, true), LinearLayout.LayoutParams(-1, -2))
        screen.addView(
            label("Enter the receiver address shown in the Deeprowss Android app. Keep both devices on the same Wi-Fi.", 17f, Color.LTGRAY),
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = 18; bottomMargin = 28 }
        )
        screen.addView(address, LinearLayout.LayoutParams(820, -2))
        screen.addView(pin, LinearLayout.LayoutParams(820, -2).apply { topMargin = 14 })
        screen.addView(connect, LinearLayout.LayoutParams(-2, -2).apply { topMargin = 22 })
        screen.addView(back, LinearLayout.LayoutParams(-2, -2).apply { topMargin = 10 })
        showScreen(screen)
        address.requestFocus()
    }

    private fun submitManual(rawAddress: String, rawPin: String) {
        val host = rawAddress.trim().removePrefix("http://").removePrefix("https://").trimEnd('/')
        val pin = rawPin.trim()
        if (host.isBlank() || !pin.matches(Regex("[0-9]{6}"))) return
        openSite(host, pin)
    }

    // ------------------------------------------------------------------ remote control and pointer input

    /**
     * Some Android TV launchers/emulators report a mouse as generic pointer motion.
     * Route pointer events to the full-screen WebView first; do not consume events
     * that Chromium does not handle.
     */
    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        // BlueStacks and some TV emulators deliver a physical mouse click as a
        // generic button-release event rather than a touch ACTION_UP. Native
        // fallback buttons (including the renderer recovery screen) otherwise
        // receive hover but never activate.
        if (event.action == MotionEvent.ACTION_BUTTON_RELEASE &&
            event.isFromSource(InputDevice.SOURCE_MOUSE)
        ) {
            val focused = container.findFocus()
            if (focused != null && focused !== container && focused.isEnabled && focused.isClickable) {
                if (focused.performClick()) return true
            }
        }

        val target = webView
        if (target != null && target.visibility == View.VISIBLE &&
            (event.source and InputDevice.SOURCE_CLASS_POINTER) == InputDevice.SOURCE_CLASS_POINTER
        ) {
            if (target.dispatchGenericMotionEvent(event)) return true
        }
        return super.dispatchGenericMotionEvent(event)
    }

    /**
     * Keep the WebView eligible for TV remote navigation. OK/Enter and directional
     * events are not consumed here, so Chromium and embedded player controls can handle them.
     */
    override fun dispatchKeyEvent(event: android.view.KeyEvent): Boolean {
        if (event.action == android.view.KeyEvent.ACTION_DOWN) {
            when (event.keyCode) {
                android.view.KeyEvent.KEYCODE_DPAD_UP,
                android.view.KeyEvent.KEYCODE_DPAD_DOWN,
                android.view.KeyEvent.KEYCODE_DPAD_LEFT,
                android.view.KeyEvent.KEYCODE_DPAD_RIGHT -> {
                    if (webView?.hasFocus() != true) webView?.requestFocus()
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (customView != null) {
            hideCustomView()
            return
        }
        val view = webView
        if (view == null) {
            // Native fallback screens: leave the app.
            @Suppress("DEPRECATION")
            super.onBackPressed()
            return
        }
        // The site decides what Back does: close the player or details, step back through
        // Movies, return to the front page. On the front page it reports "not handled" and we exit.
        view.evaluateJavascript(
            "(function(){return window.deeprowssHandleBack?window.deeprowssHandleBack():false})()"
        ) { result ->
            if (result != "true") finish()
        }
    }

    override fun onResume() {
        super.onResume()
        webView?.onResume()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && packageManager.canRequestPackageInstalls()) {
            webView?.evaluateJavascript("window.deeprowssRetryPendingUpdate && window.deeprowssRetryPendingUpdate()", null)
        }
    }

    override fun onPause() {
        webView?.onPause()
        super.onPause()
    }

    override fun onDestroy() {
        webView?.destroy()
        webView = null
        super.onDestroy()
    }
}
