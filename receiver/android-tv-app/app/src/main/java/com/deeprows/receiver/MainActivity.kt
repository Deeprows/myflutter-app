package com.deeprows.receiver

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.inputmethod.EditorInfo
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

class MainActivity : Activity() {
    companion object {
        private const val RECEIVER_PAGE = "https://deeprows.github.io/myflutter-app/"
    }

    private var webView: WebView? = null
    private lateinit var root: LinearLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showConnectScreen()
    }

    private fun showConnectScreen() {
        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(64, 40, 64, 40)
            setBackgroundColor(Color.rgb(8, 11, 16))
        }
        val title = TextView(this).apply {
            text = "DEEProWSS TV RECEIVER"
            textSize = 30f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }
        val help = TextView(this).apply {
            text = "Enter the receiver address displayed in the Deeprowss Android app. Keep both devices on the same Wi-Fi."
            textSize = 17f
            setTextColor(Color.LTGRAY)
            gravity = Gravity.CENTER
            setPadding(0, 18, 0, 28)
        }
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
        val open = Button(this).apply {
            text = "CONNECT TO DEEPROWSS"
            textSize = 16f
            setOnClickListener { openReceiver(address.text.toString(), pin.text.toString()) }
        }
        pin.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_GO) {
                openReceiver(address.text.toString(), pin.text.toString())
                true
            } else false
        }
        root.addView(title, LinearLayout.LayoutParams(-1, -2))
        root.addView(help, LinearLayout.LayoutParams(-1, -2))
        root.addView(address, LinearLayout.LayoutParams(820, -2))
        root.addView(pin, LinearLayout.LayoutParams(820, -2).apply { topMargin = 14 })
        root.addView(open, LinearLayout.LayoutParams(-2, -2).apply { topMargin = 22 })
        setContentView(root)
        address.requestFocus()
    }

    private fun openReceiver(raw: String, rawPin: String) {
        val host = raw.trim().removePrefix("http://").removePrefix("https://").trimEnd('/')
        val pin = rawPin.trim()
        if (host.isBlank() || !pin.matches(Regex("[0-9]{6}"))) return
        val receiverUrl = android.net.Uri.parse(RECEIVER_PAGE).buildUpon()
            .appendQueryParameter("host", host)
            .appendQueryParameter("pin", pin)
            .build().toString()
        val allowedHost = android.net.Uri.parse(RECEIVER_PAGE).host
        val view = WebView(this).apply {
            setBackgroundColor(Color.BLACK)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            settings.loadsImagesAutomatically = true
            settings.javaScriptCanOpenWindowsAutomatically = false
            webChromeClient = WebChromeClient()
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                    val target = request?.url ?: return true
                    return target.host != allowedHost
                }
            }
        }
        webView?.destroy()
        webView = view
        setContentView(view)
        view.loadUrl(receiverUrl)
    }

    override fun onBackPressed() {
        val view = webView
        if (view != null) {
            view.destroy()
            webView = null
            showConnectScreen()
        } else {
            super.onBackPressed()
        }
    }

    override fun onDestroy() {
        webView?.destroy()
        webView = null
        super.onDestroy()
    }
}
