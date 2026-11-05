package com.wittywilla.wittymediaclient.ui

import android.annotation.SuppressLint
import android.app.Activity
import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.SystemClock
import android.view.InputDevice
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.RenderProcessGoneDetail
import android.webkit.URLUtil
import android.webkit.ValueCallback
import android.webkit.WebStorage
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.RequiresApi
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.net.toUri
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.wittywilla.wittymediaclient.WittyApp
import com.wittywilla.wittymediaclient.diag.ClientLog
import com.wittywilla.wittymediaclient.net.APP_BACK_PATH
import com.wittywilla.wittymediaclient.net.APP_UP_PATH
import com.wittywilla.wittymediaclient.net.ASK_OWN_BACK
import com.wittywilla.wittymediaclient.net.ASK_SEES_PAD
import com.wittywilla.wittymediaclient.net.OFFER_APP_BACK
import com.wittywilla.wittymediaclient.net.OFFER_APP_UP
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.TV_VIEWPORT
import com.wittywilla.wittymediaclient.net.isWebLink
import com.wittywilla.wittymediaclient.net.pageAddress
import com.wittywilla.wittymediaclient.net.pageFillsScreen
import com.wittywilla.wittymediaclient.net.sameServer
import com.wittywilla.wittymediaclient.net.webViewTooOld
import com.wittywilla.wittymediaclient.net.sessionCookie
import com.wittywilla.wittymediaclient.net.themeSyncScript
import com.wittywilla.wittymediaclient.net.staysInWebPlayer
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

private const val CANT_OPEN = "This page couldn't open. Check the server is on, then try again."
private const val NO_WEB_VIEW = "This device has no working web view, which this page needs."
private const val OLD_WEB_VIEW = "This page needs a newer Android System WebView than this device has. Update it from the Play Store if you can. Films and shows still play in this app, and this page opens in any up-to-date browser on another device."
private const val NEEDS_BROWSER = "This download only works in a web browser. Open your server's address on a computer."
private const val NO_DOWNLOADS = "This device can't save downloads."
private const val NO_FILE_PICKER = "This device has no way to choose a file."

// The server's own page in a web view, kept to that server. Only web links leave, for the
// browser. There's no script bridge, so the page can reach nothing of this app or this device.
private class PageClient(
    private val base: String,
    private val onPath: (String) -> Unit,
    private val onFail: () -> Unit,
    private val onShowing: () -> Unit,
    private val onLoaded: () -> Unit,
    private val onAppBack: () -> Unit,
    private val isTv: Boolean,
    // A page inside a TV's tab: Up from its top goes to the bar.
    private val onAppUp: (() -> Unit)? = null,
) : WebViewClient() {
    override fun onPageCommitVisible(view: WebView, url: String) {
        // A TV counts its pixels in twos, which would give the page half the room a big screen has.
        if (isTv) view.evaluateJavascript(TV_VIEWPORT, null)
        view.evaluateJavascript(OFFER_APP_BACK, null)
        if (onAppUp != null) view.evaluateJavascript(OFFER_APP_UP, null)
        onShowing()
    }

    override fun onPageFinished(view: WebView, url: String) = onLoaded()

    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
        val url = request.url.toString()
        if (sameServer(url, base)) {
            when (request.url.path) {
                APP_BACK_PATH -> onAppBack()
                APP_UP_PATH -> onAppUp?.invoke()
                else -> return false
            }
            return true
        }
        if (request.isForMainFrame && isWebLink(url)) {
            try {
                view.context.startActivity(Intent(Intent.ACTION_VIEW, url.toUri()))
            } catch (_: ActivityNotFoundException) {
                // Nowhere to send it. The page stays as it is.
            }
        }
        return true
    }

    // Also runs for the page changing its own address, which is how it closes its player.
    override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) {
        url.toHttpUrlOrNull()?.encodedPath?.let(onPath)
    }

    override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
        if (request.isForMainFrame) onFail()
    }

    // Without this, the page's process dying takes the whole app with it. Android 8 is the first to ask.
    @RequiresApi(26)
    override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
        ClientLog.warn("player", "The server's page stopped: ${if (detail.didCrash()) "it crashed" else "the system ended it"}")
        onFail()
        return true
    }
}

// WebRTC needs a client like this to exist. Its default refuses every permission a page asks for,
// and nothing here needs one. A page going full screen, and choosing a file to upload, are what it adds.
private class PageChrome(
    private val onFullScreen: (View?, WebChromeClient.CustomViewCallback?) -> Unit,
    private val onChooseFile: (ValueCallback<Array<Uri>>, FileChooserParams) -> Boolean,
) : WebChromeClient() {
    override fun onShowCustomView(view: View, callback: CustomViewCallback) = onFullScreen(view, callback)
    override fun onHideCustomView() = onFullScreen(null, null)
    override fun onShowFileChooser(webView: WebView, filePathCallback: ValueCallback<Array<Uri>>, fileChooserParams: FileChooserParams) =
        onChooseFile(filePathCallback, fileChooserParams)
}

// JavaScript is what the page is. It only ever runs the signed-in server's own page.
@SuppressLint("SetJavaScriptEnabled")
private fun pageWebView(context: Context, background: Int, isTv: Boolean): WebView = WebView(context).apply {
    // Left at its default, wrapping its content, a web view counts 100vh as nothing, and whatever
    // is sized by the window's height collapses.
    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
    setBackgroundColor(background)
    with(settings) {
        useWideViewPort = isTv
        loadWithOverviewMode = isTv
        javaScriptEnabled = true
        domStorageEnabled = true
        mediaPlaybackRequiresUserGesture = false
        allowFileAccess = false
        allowContentAccess = false
        mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        @Suppress("DEPRECATION") // still honoured before Android 8, which this app runs on
        saveFormData = false
        setGeolocationEnabled(false)
        setSupportMultipleWindows(false)
    }
}

// The controller a page should know about from the start: the one that opened it. A TV's page already
// draws itself for across the room, so any controller plugged in to one counts. On a phone, a controller
// that's only plugged in stays out of it: the page would change its size for someone holding the phone.
private fun padForPage(app: WittyApp): Int? {
    if (app.lastPad >= 0 && InputDevice.getDevice(app.lastPad) != null) return app.lastPad
    if (!app.isTv) return null
    return InputDevice.getDeviceIds().firstOrNull { id -> InputDevice.getDevice(id)?.let { it.supportsSource(InputDevice.SOURCE_GAMEPAD) && !it.isVirtual } == true }
}

// A web view hides a controller from a new page until a button is pressed with that page up, and the first
// press after opening it doesn't count even for that. So someone who opened this page with A would press A on
// its first button and see nothing happen. This presses the left stick for them, which the page has no use for,
// until the page can see the controller. The next press is theirs.
private fun showPadToPage(web: WebView, pad: Int, tries: Int = 4) {
    if (tries == 0 || !web.isAttachedToWindow) return
    web.evaluateJavascript(ASK_SEES_PAD) { answer ->
        if (answer == "true" || !web.isAttachedToWindow) return@evaluateJavascript
        val at = SystemClock.uptimeMillis()
        fun stick(action: Int) = web.dispatchKeyEvent(KeyEvent(at, SystemClock.uptimeMillis(), action, KeyEvent.KEYCODE_BUTTON_THUMBL, 0, 0, pad, 0, 0, InputDevice.SOURCE_GAMEPAD))
        stick(KeyEvent.ACTION_DOWN)
        web.postDelayed({ if (web.isAttachedToWindow) stick(KeyEvent.ACTION_UP) }, 150)
        web.postDelayed({ showPadToPage(web, pad, tries - 1) }, 1000)
    }
}

// A link the page offers for saving, handed to the system's downloads with the sign-in, for the signed-in
// server's own addresses alone. A file the page made itself can't leave a web view without a script bridge.
private fun saveDownload(context: Context, api: Api, url: String, userAgent: String, disposition: String?, mime: String?) {
    if (!sameServer(url, api.base)) {
        Toast.makeText(context, NEEDS_BROWSER, Toast.LENGTH_LONG).show()
        return
    }
    try {
        val name = URLUtil.guessFileName(url, disposition, mime)
        val request = DownloadManager.Request(url.toUri())
            .addRequestHeader("Authorization", "Bearer ${api.token}")
            .addRequestHeader("User-Agent", userAgent)
            .setMimeType(mime)
            .setTitle(name)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
        // Before Android 10, the shared folder takes a permission this app doesn't ask for.
        if (Build.VERSION.SDK_INT >= 29) request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, name)
        else request.setDestinationInExternalFilesDir(context, Environment.DIRECTORY_DOWNLOADS, name)
        context.getSystemService(DownloadManager::class.java).enqueue(request)
    } catch (_: RuntimeException) {
        Toast.makeText(context, NO_DOWNLOADS, Toast.LENGTH_LONG).show()
    }
}

// The sign-in reaches the page as the server's own cookie, set only for that server's address,
// and is gone from the web view's storage when this screen closes. On plain http a browser hides
// game controllers from a page, and the Gamepad API here has never been tried on a real device.
//
// A game player (keptToGames) closes when the page goes anywhere else. A page of the server's stays
// open wherever it's taken, until Back has nothing left to go back through.
@Composable
// public: a page anyone may read, opened before signing in. It goes without a sign-in cookie.
// title: a native bar with Back and the page's name above it, as You's rows open pages.
// `out` is where Back goes once the page has nothing of its own to close or go back to: by default the screen
// before, and up to the bar for a TV's tab.
fun ServerPageScreen(
    nav: Nav,
    route: Route,
    path: String,
    keptToGames: Boolean,
    public: Boolean = false,
    title: String = "",
    out: (() -> Unit)? = null,
    backEnabled: Boolean = true,
    // A page inside a TV's tab: where Up goes from the top of the page.
    upOut: (() -> Unit)? = null,
) {
    val context = LocalContext.current
    val api = nav.app.api
    val background = MaterialTheme.colorScheme.background.toArgb()
    var failed by remember { mutableStateOf("") }
    // A web view takes seconds to start the first time, and until then it's only black.
    var showing by remember { mutableStateOf(false) }
    var fills by remember { mutableStateOf(keptToGames || pageFillsScreen(path)) }
    var fullScreen by remember { mutableStateOf<View?>(null) }
    var endFullScreen by remember { mutableStateOf<WebChromeClient.CustomViewCallback?>(null) }
    var waitingForFile by remember { mutableStateOf<ValueCallback<Array<Uri>>?>(null) }
    val chooser = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        waitingForFile?.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(result.resultCode, result.data))
        waitingForFile = null
    }
    // Some devices have a missing or broken web view, and creating one is where that shows.
    val tooOld = remember { runCatching { webViewTooOld(WebSettings.getDefaultUserAgent(context)) }.getOrDefault(false) }
    val web = remember { if (tooOld) null else runCatching { pageWebView(context, if (keptToGames) Color.BLACK else background, nav.app.isTv && !keptToGames) }.getOrNull() }

    // A film, a channel or a game in the page. Music in a page can't be told apart from a quiet one, so that isn't here.
    LaunchedEffect(fills) { if (fills) nav.app.listening.pauseForVideo() }

    DisposableEffect(web) {
        nav.app.showingPage = true
        if (web == null) {
            failed = if (tooOld) OLD_WEB_VIEW else NO_WEB_VIEW
            return@DisposableEffect onDispose { nav.app.showingPage = false }
        }
        var gone = false
        web.webViewClient = PageClient(
            api.base,
            onPath = { now ->
                if (keptToGames) {
                    if (!staysInWebPlayer(now) && nav.current == route) nav.pop()
                } else {
                    fills = pageFillsScreen(now)
                }
            },
            onFail = { failed = CANT_OPEN },
            onShowing = { showing = true },
            onLoaded = {
                padForPage(nav.app)?.let { showPadToPage(web, it) }
                // The page follows the theme chosen on this device, as the app does.
                if (!keptToGames) themeSyncScript(nav.themeChoice)?.let { web.evaluateJavascript(it, null) }
            },
            onAppBack = { if (nav.current == route) out?.invoke() ?: nav.pop() },
            isTv = nav.app.isTv && !keptToGames,
            onAppUp = upOut?.let { up -> { if (nav.current == route) up() } },
        )
        web.webChromeClient = PageChrome(
            onFullScreen = { view, callback -> fullScreen = view; endFullScreen = callback },
            onChooseFile = { callback, params ->
                waitingForFile?.onReceiveValue(null)
                waitingForFile = callback
                try {
                    chooser.launch(params.createIntent())
                    true
                } catch (_: ActivityNotFoundException) {
                    waitingForFile = null
                    Toast.makeText(context, NO_FILE_PICKER, Toast.LENGTH_LONG).show()
                    false
                }
            },
        )
        web.setDownloadListener { url, userAgent, disposition, mime, _ -> saveDownload(context, api, url, userAgent, disposition, mime) }

        val cookies = CookieManager.getInstance()
        val cookie = sessionCookie(api.token, api.base.startsWith("https:", ignoreCase = true))
        if (public && api.token.isEmpty()) {
            cookies.removeAllCookies { if (!gone) web.loadUrl(api.mediaUrl(pageAddress(path, nav.app.isTv))) }
        } else if (cookie == null) {
            failed = CANT_OPEN
        } else {
            // One left by a run that crashed could be for another server, so that goes first.
            cookies.removeAllCookies {
                cookies.setCookie(api.base, cookie) {
                    if (!gone) web.loadUrl(api.mediaUrl(if (keptToGames) path else pageAddress(path, nav.app.isTv)))
                }
            }
        }
        web.requestFocus()

        onDispose {
            nav.app.showingPage = false
            gone = true
            web.stopLoading()
            (web.parent as? ViewGroup)?.removeView(web)
            web.destroy() // this closes the stream's connection too, which ends it on the server
            cookies.removeAllCookies(null)
            cookies.flush()
            // What the page kept for itself goes with the sign-in.
            WebStorage.getInstance().deleteAllData()
        }
    }

    // A game on a controller, a film or a book never touches the screen, and has all of it.
    DisposableEffect(web, fills, fullScreen) {
        val window = (context as? Activity)?.window
        val view = fullScreen ?: web
        val bars = if (window != null && view != null) WindowCompat.getInsetsController(window, view) else null
        val whole = fills || fullScreen != null
        view?.keepScreenOn = whole
        if (whole) {
            bars?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            bars?.hide(WindowInsetsCompat.Type.systemBars())
        }
        onDispose { if (whole) bars?.show(WindowInsetsCompat.Type.systemBars()) }
    }

    BackHandler(enabled = backEnabled) {
        when {
            fullScreen != null -> endFullScreen?.onCustomViewHidden()
            failed.isNotEmpty() || web == null -> nav.pop()
            // Whatever is open on the page closes first, as Back does everywhere else.
            else -> web.evaluateJavascript(ASK_OWN_BACK) { answer ->
                when {
                    answer == "true" -> {
                        web.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ESCAPE))
                        web.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ESCAPE))
                    }
                    web.canGoBack() -> web.goBack()
                    else -> out?.invoke() ?: nav.pop()
                }
            }
        }
    }

    Screen {
        if (failed.isNotEmpty() || web == null) {
            Column(Modifier.safeDrawingPadding().padding(32.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                ErrorText(failed)
                ActionButton("Back", nav::pop, requestFocus = true)
            }
        } else if (title.isNotEmpty() && !fills) {
            Column(Modifier.fillMaxSize().safeDrawingPadding()) {
                Row(
                    Modifier.fillMaxWidth().padding(end = Space.S4),
                    verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                ) {
                    BackArrow(nav::pop, Modifier.padding(Space.S1))
                    Text(title, color = MaterialTheme.colorScheme.onBackground, style = MaterialTheme.typography.section, maxLines = 1)
                }
                Box(Modifier.weight(1f).fillMaxWidth()) {
                    AndroidView(factory = { web }, modifier = Modifier.fillMaxSize())
                    if (!showing) Loading()
                }
            }
            fullScreen?.let { view ->
                AndroidView(factory = { view.also { it.requestFocus() } }, modifier = Modifier.fillMaxSize())
            }
        } else {
            val room = if (fills) Modifier.imePadding() else Modifier.safeDrawingPadding()
            AndroidView(factory = { web }, modifier = Modifier.fillMaxSize().then(room))
            if (!showing) Loading()
            fullScreen?.let { view ->
                AndroidView(factory = { view.also { it.requestFocus() } }, modifier = Modifier.fillMaxSize())
            }
        }
    }
}
