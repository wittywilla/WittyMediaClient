package com.wittywilla.wittymediaclient.games

import android.app.Activity
import android.content.pm.PackageManager
import android.graphics.SurfaceTexture
import android.os.Build
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.TextureView
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.wittywilla.wittymediaclient.WittyApp
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

// A game on screen: the server's stream, full screen, with nothing in the way. Back, Start and Select together,
// Escape or the corner button open the game menu, as on the website's player; the picture owns the controls
// until it's open (the server's docs/GAMING-API.md, "What a TV app must build itself").

@Composable
fun GamePlayerScreen(app: WittyApp, gameId: Long, start: GameStart, direct: DirectStream? = null, onClose: () -> Unit) {
    val look = gameLook()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val play = remember { GamePlay(app, gameId, start, look.tv, scope, direct) }
    val touchScreen = remember { !look.tv && context.packageManager.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN) }
    var touchOn by remember { mutableStateOf(GamePlay.touchShown(context)) }

    LaunchedEffect(Unit) { play.begin() }
    DisposableEffect(Unit) { onDispose { play.close() } }
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { play.disappeared() }
    LifecycleEventEffect(Lifecycle.Event.ON_START) { play.appeared() }
    LaunchedEffect(play.finished) { if (play.finished) onClose() }
    FullScreen()

    // Back: up a level in the menu, the menu during play, and out while starting or after a problem.
    BackHandler {
        when {
            play.saving -> {}
            play.problem != null -> onClose()
            play.stage != GameStage.Playing -> play.quit()
            else -> play.menuBack()
        }
    }

    // A TV's remote can't play: say what can.
    LaunchedEffect(play.stage) {
        if (play.stage == GameStage.Playing && look.tv) {
            delay(800)
            if (!play.input.controllerInUse) play.say("Connect a controller to play. Back opens the menu.")
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize().background(Color.Black)) {
        val density = LocalDensity.current
        val wPx = constraints.maxWidth.toFloat()
        val hPx = constraints.maxHeight.toFloat()
        val portrait = hPx > wPx
        val controls = play.controls
        val withTouch = touchScreen && touchOn && controls != null && controls.controls.isNotEmpty() && !play.input.controllerInUse
        // Upright with the touch controls, the picture sits in the top half and the controls below, as on the website.
        val areaH = if (portrait && withTouch) hPx * 0.52f else hPx
        val fit = PictureFit.fit(play.settings, play.aspect, play.frameSize.first.toDouble(), play.frameSize.second.toDouble(), play.turns, wPx, areaH)
        val pictureLeft = (wPx - fit.width) / 2
        val pictureTop = if (portrait && withTouch) 0f else (areaH - fit.height) / 2
        val picture = Rect(pictureLeft, pictureTop, pictureLeft + fit.width, pictureTop + fit.height)

        if (play.session != null) {
            key(play.videoKind, fit.turns != 0) {
                PictureSurface(
                    play, play.videoKind, fit.turns, if (look.tv) play.fps else 0.0,
                    Modifier
                        .offset { IntOffset(pictureLeft.roundToInt(), pictureTop.roundToInt()) }
                        .size(with(density) { fit.width.toDp() }, with(density) { fit.height.toDp() }),
                )
            }
        }

        if (withTouch && play.stage == GameStage.Playing && play.menu == null && controls != null) {
            TouchControls(
                controls, if (portrait) "portrait" else "landscape", picture,
                onButtons = { mask, x, y -> play.input.setTouch(mask, x, y) },
                onPointer = { pressed, fx, fy -> play.input.setPointer(pressed, fx, fy) },
            )
        }

        // The game menu's button, for a finger.
        if (touchScreen && play.stage == GameStage.Playing && play.menu == null && play.problem == null) {
            Pressable(
                { play.openMenu() },
                Modifier.align(Alignment.TopEnd).windowInsetsPadding(WindowInsets.safeDrawing).padding(8.dp).size(40.dp),
                radius = 10.dp, label = "Game menu", fill = Color(0x8C14161E),
            ) {
                Icon(GameIcons.More, null, Modifier.align(Alignment.Center).size(24.dp), tint = Color.White)
            }
        }

        if (play.problem == null && play.stage != GameStage.Playing) Loading(play, touchScreen) { play.quit() }
        play.problem?.let { Problem(play, it, onClose) }
        if (play.saving) Saving()
        play.menu?.let { page ->
            GameMenuSheet(play, page, touchScreen, touchOn) {
                touchOn = !touchOn
                GamePlay.setTouchShown(context, touchOn)
            }
        }
        if (play.toast.isNotEmpty()) {
            Text(
                play.toast,
                Modifier
                    .align(Alignment.BottomCenter)
                    .windowInsetsPadding(WindowInsets.safeDrawing)
                    .padding(bottom = if (look.tv) 40.dp else 24.dp, start = 24.dp, end = 24.dp)
                    .clip(RoundedCornerShape(999.dp))
                    .background(Color(0xE614161E))
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                color = Color.White, fontSize = look.body, textAlign = TextAlign.Center,
            )
        }
    }
}

// The whole screen, the system's bars away, kept on, and on a TV its game mode.
@Composable
private fun FullScreen() {
    val view = LocalView.current
    DisposableEffect(view) {
        val window = (view.context as? Activity)?.window
        val bars = window?.let { WindowCompat.getInsetsController(it, view) }
        bars?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        bars?.hide(WindowInsetsCompat.Type.systemBars())
        view.keepScreenOn = true
        if (Build.VERSION.SDK_INT >= 30) window?.setPreferMinimalPostProcessing(true)
        onDispose {
            bars?.show(WindowInsetsCompat.Type.systemBars())
            view.keepScreenOn = false
            if (Build.VERSION.SDK_INT >= 30) window?.setPreferMinimalPostProcessing(false)
        }
    }
}

// Where the picture is drawn. A SurfaceView, which the system shows with the least delay; a picture that has to
// be turned goes on a TextureView, which can be.
@Composable
private fun PictureSurface(play: GamePlay, kind: String, turns: Int, displayFps: Double, modifier: Modifier) {
    if (turns == 0) {
        AndroidView(
            factory = { context ->
                SurfaceView(context).apply {
                    holder.addCallback(object : SurfaceHolder.Callback {
                        override fun surfaceCreated(holder: SurfaceHolder) {
                            matchFrameRate(holder.surface, displayFps)
                            play.surfaceFor(kind, holder.surface)
                        }
                        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}
                        override fun surfaceDestroyed(holder: SurfaceHolder) = play.surfaceFor(kind, null)
                    })
                }
            },
            update = { view -> view.holder.surface?.takeIf { it.isValid }?.let { matchFrameRate(it, displayFps) } },
            modifier = modifier,
        )
    } else {
        BoxWithConstraints(modifier) {
            val w = maxWidth
            val h = maxHeight
            val sideways = turns % 2 == 1
            AndroidView(
                factory = { context ->
                    TextureView(context).apply {
                        surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                            private var surface: Surface? = null
                            override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) {
                                surface = Surface(texture).also { play.surfaceFor(kind, it) }
                            }
                            override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) {}
                            override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean {
                                play.surfaceFor(kind, null)
                                surface?.release()
                                return true
                            }
                            override fun onSurfaceTextureUpdated(texture: SurfaceTexture) {}
                        }
                        rotation = turns * 90f
                    }
                },
                modifier = Modifier
                    .align(Alignment.Center)
                    .size(if (sideways) h else w, if (sideways) w else h),
            )
        }
    }
}

// A TV shows the game at its own rate where it can: 50 Hz for a PAL game, 60 for the rest (docs/GAMING-STREAM.md,
// "Frame pacing"). The display listener in GamePlay then tells the server the new rate.
private fun matchFrameRate(surface: Surface, fps: Double) {
    if (fps <= 0 || Build.VERSION.SDK_INT < 30) return
    runCatching { surface.setFrameRate(fps.toFloat(), Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE) }
}

// The website's loading screen: the game, and each step on the way to its first picture.
@Composable
private fun Loading(play: GamePlay, touchScreen: Boolean, onCancel: () -> Unit) {
    val look = gameLook()
    var seconds by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(1_000)
            seconds++
        }
    }
    val cancel = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { cancel.requestFocus() } }
    val game = play.item
    val portrait = windowDp().let { it.second > it.first }
    Box(Modifier.fillMaxSize().background(GameColours.background).windowInsetsPadding(WindowInsets.safeDrawing).padding(look.gutter)) {
        val cover = @Composable { m: Modifier ->
            if (game != null && game.hasPoster) GamePicture(play.api.posterUrl(game, 480), game.title, m.clip(RoundedCornerShape(look.radius)))
        }
        val body = @Composable { m: Modifier ->
            Column(m, verticalArrangement = Arrangement.spacedBy(look.gap)) {
                Text(play.consoleName, color = GameColours.secondary, fontSize = look.small)
                Text(game?.title.orEmpty(), color = GameColours.text, fontSize = look.title, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                val now = GameStage.entries.indexOf(play.stage)
                for ((i, stage) in GameStage.entries.withIndex()) {
                    if (stage == GameStage.Playing) continue
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Box(Modifier.size(if (look.tv) 14.dp else 20.dp), contentAlignment = Alignment.Center) {
                            when {
                                i < now -> Icon(GameIcons.Check, null, tint = GameColours.ok)
                                i == now -> CircularProgressIndicator(Modifier.fillMaxSize(), color = GameColours.accent, strokeWidth = 2.dp)
                            }
                        }
                        Text(stage.words, color = if (i <= now) GameColours.text else GameColours.hint, fontSize = look.body)
                    }
                }
                play.unpacked?.let { LinearProgressIndicator({ it }, Modifier.fillMaxWidth(), color = GameColours.accent, trackColor = GameColours.card) }
                val slow = when {
                    seconds > 45 -> "This is taking longer than usual. A big game on a busy server can take a few minutes the first time."
                    seconds > 12 -> "Big games take longer the first time. They're quicker after that."
                    else -> ""
                }
                if (slow.isNotEmpty()) Text(slow, color = GameColours.secondary, fontSize = look.small)
                Row(Modifier.padding(top = look.gap), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    GameButton("Cancel", onCancel, focusRequester = cancel)
                    Text(
                        when {
                            look.tv -> "For the game menu, press Back, or Start and Select together"
                            touchScreen -> "For the game menu, use the button in the corner"
                            else -> "For the game menu, press Start and Select together"
                        },
                        Modifier.weight(1f, fill = false), color = GameColours.secondary, fontSize = look.small,
                    )
                }
            }
        }
        if (portrait) {
            Column(Modifier.align(Alignment.Center).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(24.dp)) {
                cover(Modifier.widthIn(max = 200.dp).heightIn(max = 260.dp))
                body(Modifier.fillMaxWidth())
            }
        } else {
            Row(Modifier.align(Alignment.Center).widthIn(max = 900.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(look.gutter)) {
                cover(Modifier.fillMaxHeight(0.6f).aspectRatio(0.75f))
                body(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun Problem(play: GamePlay, problem: GameProblem, onClose: () -> Unit) {
    val look = gameLook()
    val first = remember { FocusRequester() }
    LaunchedEffect(problem) { runCatching { first.requestFocus() } }
    Box(Modifier.fillMaxSize().background(GameColours.background).windowInsetsPadding(WindowInsets.safeDrawing).padding(look.gutter), contentAlignment = Alignment.Center) {
        Column(Modifier.widthIn(max = 640.dp), verticalArrangement = Arrangement.spacedBy(look.gap)) {
            Text(play.item?.title.orEmpty(), color = GameColours.secondary, fontSize = look.small)
            Text(problem.title, color = GameColours.text, fontSize = look.title, fontWeight = FontWeight.SemiBold)
            Text(problem.body, color = GameColours.secondary, fontSize = look.body)
            Row(Modifier.padding(top = look.gap), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (problem.retry) GameButton(if (play.session != null) "Resume" else "Try again", { play.retry() }, kind = ButtonKind.Primary, focusRequester = first)
                if (problem.defaults) GameButton("Start with default settings", { play.retry(safeMode = true) })
                GameButton("Back", onClose, kind = if (problem.retry) ButtonKind.Secondary else ButtonKind.Primary, focusRequester = if (problem.retry) null else first)
            }
        }
    }
}

@Composable
private fun Saving() {
    val look = gameLook()
    Box(Modifier.fillMaxSize().background(Color(0xCC000000)), contentAlignment = Alignment.Center) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            CircularProgressIndicator(Modifier.size(24.dp), color = Color.White, strokeWidth = 2.dp)
            Text("Saving…", color = Color.White, fontSize = look.title)
        }
    }
}

// MARK: the game menu

// One of the menu's tiles: an icon, its name, and a line under it.
@Composable
private fun Tile(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    sub: String = "",
    primary: Boolean = false,
    danger: Boolean = false,
    on: Boolean = false,
    focus: FocusRequester? = null,
) {
    val look = gameLook()
    val fill = when {
        primary -> GameColours.accent
        on -> GameColours.text.copy(alpha = 0.18f)
        else -> Color.White.copy(alpha = 0.08f)
    }
    val ink = if (primary) GameColours.onAccent else if (danger) Color(0xFFFF8A80) else Color(0xFFF2F4F8)
    Pressable(onClick, modifier.heightIn(min = if (look.tv) 48.dp else 60.dp), label = if (sub.isEmpty()) label else "$label, $sub", fill = fill, focusRequester = focus) {
        Row(
            Modifier.align(Alignment.CenterStart).padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(icon, null, Modifier.size(if (look.tv) 18.dp else 24.dp), tint = ink)
            Column {
                Text(label, color = ink, fontSize = look.body, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (sub.isNotEmpty()) Text(sub, color = ink.copy(alpha = 0.7f), fontSize = look.small, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun GameMenuSheet(play: GamePlay, page: GameMenu, touchScreen: Boolean, touchOn: Boolean, toggleTouch: () -> Unit) {
    val look = gameLook()
    val first = remember(page) { FocusRequester() }
    LaunchedEffect(page) { runCatching { first.requestFocus() } }
    val columns = when {
        look.tv -> 3
        windowDp().first >= 600 -> 3
        else -> 2
    }
    Box(
        Modifier.fillMaxSize().background(Color(0xD9000000)).windowInsetsPadding(WindowInsets.safeDrawing),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier
                .widthIn(max = if (look.tv) 720.dp else 760.dp)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = look.gutter.coerceAtMost(48.dp), vertical = 20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            val game = play.item
            val (title, sub) = when (page) {
                GameMenu.Main -> (game?.title.orEmpty()) to listOf(play.consoleName, play.session?.core.orEmpty()).filter { it.isNotEmpty() }.joinToString(" · ")
                GameMenu.Save -> "Save" to "Choose a slot"
                GameMenu.Load -> "Load" to "Choose a save"
                GameMenu.Controllers -> "Controllers" to (game?.title.orEmpty())
                GameMenu.More -> "More" to (game?.title.orEmpty())
                GameMenu.Discs -> "Change disc" to (game?.title.orEmpty())
                GameMenu.Connection -> "Connection" to "How the game reaches this device"
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                if (page == GameMenu.Main && game != null && game.hasPoster) {
                    GamePicture(play.api.posterUrl(game, 240), game.title, Modifier.height(if (look.tv) 48.dp else 72.dp).aspectRatio(0.75f).clip(RoundedCornerShape(6.dp)))
                }
                Column(Modifier.weight(1f)) {
                    Text(title, color = Color(0xFFF2F4F8), fontSize = look.title, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    if (sub.isNotEmpty()) Text(sub, color = Color(0xFFAAB1C0), fontSize = look.small, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            val gap = if (look.tv) 8.dp else 8.dp
            when (page) {
                GameMenu.Main -> {
                    Tile(GameIcons.Play, "Resume", { play.closeMenu() }, Modifier.fillMaxWidth(), primary = true, focus = first)
                    FlowRow(maxItemsInEachRow = columns, horizontalArrangement = Arrangement.spacedBy(gap), verticalArrangement = Arrangement.spacedBy(gap)) {
                        val cell = Modifier.weight(1f)
                        Tile(GameIcons.Save, "Save", { play.showMenu(GameMenu.Save) }, cell, sub = "Choose a slot")
                        Tile(GameIcons.Load, "Load", { play.showMenu(GameMenu.Load) }, cell, sub = "Choose a save")
                        Tile(GameIcons.QuickSave, "Quick save", { play.save(play.quickSlot) }, cell, sub = "Slot ${play.quickSlot}")
                        Tile(GameIcons.QuickLoad, "Quick load", { play.load(play.quickSlot) }, cell, sub = "Slot ${play.quickSlot}")
                        Tile(GameIcons.FastForward, if (play.fastForward) "Normal speed" else "Fast forward", { play.toggleFastForward() }, cell, on = play.fastForward)
                        Tile(GameIcons.Pad, "Controllers", { play.showMenu(GameMenu.Controllers) }, cell, sub = if (play.input.players.isNotEmpty()) "Connected" else "Players")
                        if (touchScreen) Tile(GameIcons.Touch, if (touchOn) "Hide touch" else "Show touch", toggleTouch, cell, sub = "Controls on screen", on = touchOn)
                        Tile(GameIcons.More, "More", { play.showMenu(GameMenu.More) }, cell)
                        Tile(GameIcons.Quit, "Save and quit", { play.quit() }, cell, danger = true)
                    }
                }
                GameMenu.More -> FlowRow(maxItemsInEachRow = columns, horizontalArrangement = Arrangement.spacedBy(gap), verticalArrangement = Arrangement.spacedBy(gap)) {
                    val cell = Modifier.weight(1f)
                    val discs = play.discs > 1
                    if (discs) Tile(GameIcons.Disc, "Change disc", { play.showMenu(GameMenu.Discs) }, cell, sub = "Disc ${play.disc + 1} of ${play.discs}", focus = first)
                    Tile(GameIcons.Play, "Press Start", { play.press(RetroPad.START) }, cell, focus = if (discs) null else first)
                    Tile(GameIcons.More, "Press Select", { play.press(RetroPad.SELECT) }, cell)
                    Tile(GameIcons.Pause, if (play.paused) "Unpause" else "Pause", { play.pause(!play.paused) }, cell, on = play.paused)
                    Tile(GameIcons.Slow, if (play.slowMotion) "Normal speed" else "Slow motion", { play.toggleSlowMotion() }, cell, on = play.slowMotion)
                    Tile(GameIcons.Reset, "Undo load", { play.undoLoad() }, cell)
                    Tile(GameIcons.Reset, "Reset the game", { play.reset() }, cell)
                    Tile(GameIcons.Connection, "Connection", { play.showMenu(GameMenu.Connection) }, cell, sub = GameModes.names[play.chosenMode].orEmpty().substringBefore(" ("))
                    Tile(GameIcons.Settings, if (play.session?.safeMode == true) "Restart with my settings" else "Restart with default settings", { play.retry(safeMode = play.session?.safeMode != true) }, cell)
                    Tile(GameIcons.Back, "Back", { play.menuBack() }, cell)
                }
                GameMenu.Discs -> Column(verticalArrangement = Arrangement.spacedBy(gap)) {
                    for (n in 0 until play.discs) {
                        Tile(GameIcons.Disc, "Disc ${n + 1}", { play.changeDisc(n) }, Modifier.fillMaxWidth(), on = n == play.disc, sub = if (n == play.disc) "In the drive" else "", focus = if (n == 0) first else null)
                    }
                }
                GameMenu.Connection -> Column(verticalArrangement = Arrangement.spacedBy(gap)) {
                    for ((i, mode) in (listOf("auto") + play.connectionChoices).withIndex()) {
                        Tile(GameIcons.Connection, GameModes.names.getValue(mode), { play.useMode(mode) }, Modifier.fillMaxWidth(), on = play.chosenMode == mode, focus = if (i == 0) first else null)
                    }
                    Text("Now using: ${GameModes.names[play.modeInUse] ?: "nothing yet"}", color = Color(0xFFAAB1C0), fontSize = look.small)
                    Tile(GameIcons.Back, "Back", { play.showMenu(GameMenu.More) }, Modifier.fillMaxWidth())
                }
                GameMenu.Save -> SlotGrid(play, saving = true, columns = columns, first = first)
                GameMenu.Load -> SlotGrid(play, saving = false, columns = columns, first = first)
                GameMenu.Controllers -> Players(play, touchScreen, first)
            }
        }
    }
}

// Save states with their pictures. Saving goes to slots 1 to 99; loading also takes the server's own 0, 100 and 101.
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SlotGrid(play: GamePlay, saving: Boolean, columns: Int, first: FocusRequester) {
    val look = gameLook()
    val saves = play.saves
    val bySlot = saves.associateBy { it.slot }
    val slots = if (saving) {
        val shown = (1..9).toMutableList()
        for (s in saves) if (GameWords.canSaveTo(s.slot) && s.slot !in shown) shown += s.slot
        shown.sorted()
    } else {
        saves.map { it.slot }.sortedWith(compareBy({ it != 0 }, { it }))
    }
    var replacing by remember { mutableStateOf<Int?>(null) }
    if (!saving && slots.isEmpty()) {
        Text("No saves yet. Save from this menu while you play.", color = Color(0xFFAAB1C0), fontSize = look.body)
        Tile(GameIcons.Back, "Back", { play.menuBack() }, Modifier.fillMaxWidth(), focus = first)
        return
    }
    FlowRow(maxItemsInEachRow = columns, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for ((i, slot) in slots.withIndex()) {
            val save = bySlot[slot]
            val asking = replacing == slot
            Pressable(
                {
                    when {
                        !saving -> play.load(slot)
                        save != null && play.confirms && !asking -> replacing = slot
                        else -> play.save(slot)
                    }
                },
                Modifier.weight(1f),
                label = GameWords.slotName(slot) + (save?.let { ", saved ${GameWords.ago(it.updatedAt)}" } ?: ", empty"),
                fill = Color.White.copy(alpha = 0.08f),
                focusRequester = if (i == 0) first else null,
            ) {
                Column(Modifier.padding(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Box(Modifier.fillMaxWidth().aspectRatio(16f / 10f).clip(RoundedCornerShape(6.dp)).background(Color(0xFF2A2E38))) {
                        if (save != null && save.hasThumb) {
                            GamePicture(play.api.saveThumbUrl(play.gameId, slot, save.updatedAt), "", Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                        }
                    }
                    Text(
                        if (asking) "Replace ${GameWords.slotName(slot).lowercase()}?" else GameWords.slotName(slot),
                        color = if (asking) Color(0xFFFFD27F) else Color(0xFFF2F4F8), fontSize = look.small, fontWeight = FontWeight.SemiBold, maxLines = 1,
                    )
                    Text(
                        if (asking) "Press again to replace it" else save?.let { GameWords.ago(it.updatedAt) } ?: "Empty",
                        color = Color(0xFFAAB1C0), fontSize = look.small, maxLines = 1,
                    )
                }
            }
        }
        // The last row keeps the others' widths.
        repeat((columns - slots.size % columns) % columns) { Spacer(Modifier.weight(1f)) }
    }
    Tile(GameIcons.Back, "Back", { play.menuBack() }, Modifier.fillMaxWidth())
}

// Who's on which player, the profile each plays by, and what the console's emulator lets each player plug in.
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Players(play: GamePlay, touchScreen: Boolean, first: FocusRequester) {
    val look = gameLook()
    val players = play.input.players
    val words = Color(0xFFAAB1C0)
    if (players.isEmpty()) {
        Text(
            if (touchScreen) "No controller is connected. The touch controls play as player 1; connect a controller to play with it."
            else "No controller is connected. Connect one to play: it becomes player 1.",
            color = words, fontSize = look.body,
        )
    }
    for (p in players) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Player ${p.port + 1}: ${p.name}", color = Color(0xFFF2F4F8), fontSize = look.body, fontWeight = FontWeight.SemiBold)
            Text(if (p.profile.isNotEmpty()) "Plays by your profile “${p.profile}”" else "Plays by this console's usual layout", color = words, fontSize = look.small)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                for (port in 0..3) GameChip("Player ${port + 1}", port == p.port, { play.input.movePlayer(p.deviceId, port) })
            }
        }
    }
    val devices = play.session?.devices.orEmpty().filter { it.types.size > 1 }
    for (d in devices) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("What player ${d.port + 1} plugs in", color = Color(0xFFF2F4F8), fontSize = look.body, fontWeight = FontWeight.SemiBold)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                val chosen = currentDevice(d)
                for (t in d.types) GameChip(t.name, t.id == chosen, { play.setDevice(d.port, t.id) })
            }
        }
    }
    Text("A keyboard plays as player 1. Profiles and layouts are set up on the website's Controllers page.", color = words, fontSize = look.small)
    Tile(GameIcons.Back, "Back", { play.menuBack() }, Modifier.fillMaxWidth(), focus = first)
}
