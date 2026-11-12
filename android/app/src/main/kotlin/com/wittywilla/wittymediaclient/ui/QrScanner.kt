// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.RectF
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.util.Size
import android.view.Surface
import android.view.TextureView
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.NotFoundException
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.ReaderException
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader
import com.wittywilla.wittymediaclient.diag.ClientLog
import kotlin.math.abs
import kotlin.math.max

// Reading a QR code with the camera, on the device, with nothing but the platform's camera and ZXing's decoder
// (both open; no Google Play Services). The picture is only looked at for a code: nothing is kept or sent. A phone
// or a tablet with a camera has this; a TV never does, and typing the device's letters always works instead.

fun hasCamera(context: Context): Boolean = context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)

fun cameraAllowed(context: Context): Boolean =
    ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

// The camera's picture, with every code it sees handed to `onCode` (the same one again and again while it's in
// view: the caller decides what to do with it, and takes this off the screen when it has what it wants).
@Composable
fun QrScanner(label: String, onCode: (String) -> Unit, onFailed: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val found = rememberUpdatedState(onCode)
    val failed = rememberUpdatedState(onFailed)
    val camera = remember { QrCamera(context.applicationContext, { found.value(it) }, { failed.value() }) }
    // The camera is let go of whenever the app isn't in front, and when this leaves the screen.
    LifecycleEventEffect(Lifecycle.Event.ON_START) { camera.resume() }
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { camera.pause() }
    DisposableEffect(Unit) { onDispose { camera.close() } }
    AndroidView(
        factory = { TextureView(it).also(camera::attach) },
        modifier = modifier.fillMaxWidth().aspectRatio(1f).clip(LocalMetrics.current.corner(14)).semantics { contentDescription = label },
    )
}

// Which part of a picture is searched: the middle square, where people hold a code, at most this many pixels a side.
internal data class ScanCrop(val left: Int, val top: Int, val side: Int)

internal fun scanCrop(width: Int, height: Int): ScanCrop {
    val side = minOf(width, height)
    return ScanCrop((width - side) / 2, (height - side) / 2, side)
}

// The picture size to ask a camera for: the one closest to 1280 by 720 that isn't larger than 1920 by 1080, which is
// plenty for a code on a TV across a room and light enough to look at several times a second on an old phone.
internal fun pickSize(sizes: List<Pair<Int, Int>>): Pair<Int, Int>? =
    sizes.filter { max(it.first, it.second) <= 1920 }.ifEmpty { sizes }.minByOrNull { abs(it.first * it.second - 1280 * 720) }

// The luminance rows of a camera picture, packed: a plane's rows may be longer than the picture is wide.
internal fun packRows(plane: ByteArray, rowStride: Int, width: Int, height: Int): ByteArray {
    if (rowStride == width) return if (plane.size == width * height) plane else plane.copyOf(width * height)
    val out = ByteArray(width * height)
    for (y in 0 until height) {
        val from = y * rowStride
        if (from + width > plane.size) break
        System.arraycopy(plane, from, out, y * width, width)
    }
    return out
}

// A code in a picture's luminance, or null. On its own, so the decoder can be tested with a drawn code.
internal fun decodeQr(luminance: ByteArray, width: Int, height: Int): String? {
    val crop = scanCrop(width, height)
    val source = PlanarYUVLuminanceSource(luminance, width, height, crop.left, crop.top, crop.side, crop.side, false)
    return try {
        QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source)), mapOf(DecodeHintType.TRY_HARDER to true)).text
    } catch (_: NotFoundException) {
        null
    } catch (_: ReaderException) {
        null
    }
}

private class QrCamera(private val context: Context, private val onCode: (String) -> Unit, private val onFailed: () -> Unit) {
    private val main = Handler(Looper.getMainLooper())
    private var thread: HandlerThread? = null
    private var worker: Handler? = null
    private var view: TextureView? = null
    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var reader: ImageReader? = null
    private var wanted = false
    private var closed = false
    private var lastLook = 0L

    fun attach(texture: TextureView) {
        view = texture
        texture.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) = open()
            override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) = fit()
            override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean { release(); return true }
            override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit
        }
    }

    fun resume() {
        wanted = true
        if (view?.isAvailable == true) open()
    }

    fun pause() {
        wanted = false
        release()
    }

    fun close() {
        closed = true
        wanted = false
        release()
    }

    private fun fail(why: String) {
        ClientLog.warn("app", "The camera couldn't be used to scan a code: $why")
        release()
        main.post { if (!closed) onFailed() }
    }

    private var size = Size(1280, 720)
    private var sensorDegrees = 90

    // The permission is asked for by the screen before this is ever shown; a refusal in between ends in onFailed.
    @SuppressLint("MissingPermission")
    private fun open() {
        if (!wanted || closed || device != null || !cameraAllowed(context)) return
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        try {
            val ids = manager.cameraIdList
            val id = ids.firstOrNull { manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK } ?: ids.firstOrNull()
            if (id == null) { fail("no camera"); return }
            val traits = manager.getCameraCharacteristics(id)
            val map = traits.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val sizes = map?.getOutputSizes(ImageFormat.YUV_420_888)?.map { it.width to it.height }.orEmpty()
            pickSize(sizes)?.let { size = Size(it.first, it.second) }
            sensorDegrees = traits.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
            val autofocus = traits.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)?.contains(CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE) == true
            val looper = HandlerThread("qr-scan").also { it.start(); thread = it }
            val work = Handler(looper.looper).also { worker = it }
            manager.openCamera(
                id,
                object : CameraDevice.StateCallback() {
                    override fun onOpened(camera: CameraDevice) {
                        if (!wanted || closed) { camera.close(); return }
                        device = camera
                        start(camera, work, autofocus)
                    }
                    override fun onDisconnected(camera: CameraDevice) { camera.close(); if (device === camera) device = null }
                    override fun onError(camera: CameraDevice, error: Int) { camera.close(); if (device === camera) device = null; fail("error $error") }
                },
                work,
            )
        } catch (e: CameraAccessException) {
            fail(e.javaClass.simpleName)
        } catch (e: SecurityException) {
            fail(e.javaClass.simpleName)
        } catch (e: IllegalArgumentException) {
            fail(e.javaClass.simpleName)
        }
    }

    private fun start(camera: CameraDevice, work: Handler, autofocus: Boolean) {
        val texture = view?.surfaceTexture ?: return
        try {
            texture.setDefaultBufferSize(size.width, size.height)
            val preview = Surface(texture)
            val images = ImageReader.newInstance(size.width, size.height, ImageFormat.YUV_420_888, 2).also { reader = it }
            images.setOnImageAvailableListener({ look(it) }, work)
            val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                addTarget(preview)
                addTarget(images.surface)
                if (autofocus) set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
            }
            // The list form works from Android 6, the oldest this app runs on; its replacement needs Android 9.
            @Suppress("DEPRECATION")
            camera.createCaptureSession(
                listOf(preview, images.surface),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(made: CameraCaptureSession) {
                        if (device !== camera) { made.close(); return }
                        session = made
                        try {
                            made.setRepeatingRequest(request.build(), null, work)
                        } catch (e: CameraAccessException) {
                            fail(e.javaClass.simpleName)
                        } catch (e: IllegalStateException) {
                            // Closed in the meantime: nothing to show.
                        }
                    }
                    override fun onConfigureFailed(made: CameraCaptureSession) = fail("the camera refused the picture sizes")
                },
                work,
            )
            main.post { fit() }
        } catch (e: CameraAccessException) {
            fail(e.javaClass.simpleName)
        } catch (e: IllegalStateException) {
            fail(e.javaClass.simpleName)
        } catch (e: IllegalArgumentException) {
            fail(e.javaClass.simpleName)
        }
    }

    // A few looks a second are plenty, and leave an old phone cool.
    private fun look(from: ImageReader) {
        val image = try { from.acquireLatestImage() } catch (_: IllegalStateException) { null } ?: return
        try {
            val now = SystemClock.elapsedRealtime()
            if (now - lastLook < LOOK_EVERY_MS) return
            lastLook = now
            val plane = image.planes[0]
            val bytes = ByteArray(plane.buffer.remaining()).also { plane.buffer.get(it) }
            val text = decodeQr(packRows(bytes, plane.rowStride, image.width, image.height), image.width, image.height) ?: return
            main.post { if (!closed && wanted) onCode(text) }
        } catch (_: IllegalStateException) {
            // The picture went away with the camera.
        } finally {
            image.close()
        }
    }

    // The camera's picture lies on its side in a phone held upright, and is rarely the view's shape: turned to the
    // way the screen is, and scaled to fill the square, cropping what's over.
    private fun fit() {
        val texture = view ?: return
        val w = texture.width.toFloat()
        val h = texture.height.toFloat()
        if (w <= 0 || h <= 0) return
        @Suppress("DEPRECATION") // The view's own display, on every version this app runs on.
        val rotation = (context.getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager).defaultDisplay.rotation
        val matrix = Matrix()
        val viewRect = RectF(0f, 0f, w, h)
        val cx = viewRect.centerX()
        val cy = viewRect.centerY()
        if (rotation == Surface.ROTATION_90 || rotation == Surface.ROTATION_270) {
            val buffer = RectF(0f, 0f, size.height.toFloat(), size.width.toFloat())
            buffer.offset(cx - buffer.centerX(), cy - buffer.centerY())
            matrix.setRectToRect(viewRect, buffer, Matrix.ScaleToFit.FILL)
            val scale = max(h / size.height, w / size.width)
            matrix.postScale(scale, scale, cx, cy)
            matrix.postRotate(90f * (rotation - 2), cx, cy)
        } else {
            // Upright: the picture arrives turned already, as tall as the sensor is wide.
            val pictureW = if (sensorDegrees % 180 == 90) size.height.toFloat() else size.width.toFloat()
            val pictureH = if (sensorDegrees % 180 == 90) size.width.toFloat() else size.height.toFloat()
            val fill = max(w / pictureW, h / pictureH)
            matrix.setScale(pictureW * fill / w, pictureH * fill / h, cx, cy)
            if (rotation == Surface.ROTATION_180) matrix.postRotate(180f, cx, cy)
        }
        texture.setTransform(matrix)
    }

    private fun release() {
        runCatching { session?.close() }
        session = null
        runCatching { device?.close() }
        device = null
        runCatching { reader?.close() }
        reader = null
        thread?.quitSafely()
        thread = null
        worker = null
    }

    private companion object {
        const val LOOK_EVERY_MS = 150L
    }
}
