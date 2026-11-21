package com.deeprows.receiver

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

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
        private const val RECEIVER_PAGE = "https://deeprows.github.io/myflutter-app/"
    }

    private var webView: WebView? = null
    private var customView: View? = null
    private var customViewCallback: WebChromeClient.CustomViewCallback? = null
    private lateinit var container: FrameLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        container = FrameLayout(this).apply { setBackgroundColor(Color.rgb(7, 8, 10)) }
        setContentView(container)
        openSite(null, null)
    }

    // ------------------------------------------------------------------ website

    private fun openSite(host: String?, pin: String?) {
        val base = Uri.parse(RECEIVER_PAGE).buildUpon().appendQueryParameter("tv", "1")
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
                    return req.isForMainFrame && req.url.host != allowedHost
                }

                override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
                    if (request?.isForMainFrame == true) showOfflineScreen()
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
        view.loadUrl(url)
        view.requestFocus()
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

    // ------------------------------------------------------------------ remote control

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
