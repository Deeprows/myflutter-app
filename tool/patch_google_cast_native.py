#!/usr/bin/env python3
"""Inject the native Google Cast method channel into generated MainActivity."""
from pathlib import Path
import glob, re, sys
matches = glob.glob('android/app/src/main/kotlin/**/MainActivity.kt', recursive=True)
if not matches: sys.exit('MainActivity.kt missing; run flutter create first')
p = Path(matches[0]); s = p.read_text()
if 'footbolive/google_cast' in s:
    print('Google Cast channel already installed'); raise SystemExit(0)
# Imports
for imp in [
 'com.google.android.gms.cast.CastMediaControlIntent',
 'com.google.android.gms.cast.MediaInfo',
 'com.google.android.gms.cast.MediaMetadata',
 'com.google.android.gms.cast.MediaLoadRequestData',
 'com.google.android.gms.cast.framework.CastContext',
 'androidx.mediarouter.app.MediaRouteChooserDialog',
 'androidx.mediarouter.media.MediaRouteSelector',
]:
    if imp not in s:
        s = s.replace('import android.os.Bundle', 'import android.os.Bundle\nimport ' + imp, 1)
# Put channel setup at end of configureFlutterEngine, before its closing brace.
marker = '    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {'
start = s.find(marker)
if start < 0: sys.exit('configureFlutterEngine not found')
next_method = s.find('\n    }', start)
# Find the method's matching brace by counting braces from its opening.
brace = s.find('{', start); depth = 0; end = None
for i in range(brace, len(s)):
    if s[i] == '{': depth += 1
    elif s[i] == '}':
        depth -= 1
        if depth == 0: end = i; break
if end is None: sys.exit('Could not parse configureFlutterEngine')
method = '''
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "footbolive/google_cast")
            .setMethodCallHandler { call, result ->
                try {
                    val context = CastContext.getSharedInstance(this)
                    val session = context.sessionManager.currentCastSession
                    when (call.method) {
                        "isAvailable" -> result.success(true)
                        "showPicker" -> {
                            val id = resources.getIdentifier("deeprowss_cast_receiver_app_id", "string", packageName)
                            val appId = if (id != 0) getString(id) else "CC1AD845"
                            val selector = MediaRouteSelector.Builder()
                                .addControlCategory(CastMediaControlIntent.categoryForCast(appId)).build()
                            MediaRouteChooserDialog(this).apply {
                                routeSelector = selector
                                setTitle("Choose a TV for Deeprowss")
                                show()
                            }
                            result.success(true)
                        }
                        "loadMedia" -> {
                            val remote = session?.remoteMediaClient
                            if (remote == null) { result.success(false); return@setMethodCallHandler }
                            val args = call.arguments as Map<*, *>
                            val url = args["url"] as? String ?: ""
                            if (url.isBlank() || !url.startsWith("http")) { result.success(false); return@setMethodCallHandler }
                            val title = args["title"] as? String ?: "Deeprowss"
                            val mime = args["contentType"] as? String ?: "video/mp4"
                            val live = args["live"] as? Boolean ?: false
                            val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_MOVIE).apply {
                                putString(MediaMetadata.KEY_TITLE, title)
                                putString(MediaMetadata.KEY_SUBTITLE, "Deeprowss")
                            }
                            val info = MediaInfo.Builder(url)
                                .setContentType(mime)
                                .setStreamType(if (live) MediaInfo.STREAM_TYPE_LIVE else MediaInfo.STREAM_TYPE_BUFFERED)
                                .setMetadata(metadata).build()
                            remote.load(MediaLoadRequestData.Builder().setMediaInfo(info).setAutoplay(true).build())
                            result.success(true)
                        }
                        "play" -> { session?.remoteMediaClient?.play(); result.success(session != null) }
                        "pause" -> { session?.remoteMediaClient?.pause(); result.success(session != null) }
                        "stop" -> { session?.remoteMediaClient?.stop(); result.success(session != null) }
                        "seek" -> {
                            val ms = (call.argument<Number>("position")?.toLong() ?: 0L).coerceAtLeast(0L)
                            session?.remoteMediaClient?.seek(ms); result.success(session != null)
                        }
                        "setVolume" -> {
                            val v = (call.argument<Number>("volume")?.toDouble() ?: 1.0).coerceIn(0.0, 1.0)
                            session?.volume = v; result.success(session != null)
                        }
                        "status" -> {
                            val remote = session?.remoteMediaClient
                            val status = remote?.mediaStatus
                            result.success(mapOf(
                                "connected" to (session != null),
                                "playing" to (status?.playerState == com.google.android.gms.cast.MediaStatus.PLAYER_STATE_PLAYING),
                                "position" to (remote?.approximateStreamPosition ?: 0L),
                                "duration" to (status?.mediaInfo?.streamDuration ?: 0L),
                                "volume" to (session?.volume ?: 0.0)
                            ))
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("CAST_ERROR", e.message ?: "Google Cast error", null)
                }
            }
'''
s = s[:end] + method + s[end:]
p.write_text(s)
# Install the OptionsProvider in the generated package directory.
package = re.search(r'^package\s+([\w.]+)', s, re.M).group(1)
provider_dir = p.parent
provider = Path('android_template/CastOptionsProvider.kt').read_text()
provider = re.sub(r'^package\s+[\w.]+', 'package ' + package, provider, count=1, flags=re.M)
(provider_dir / 'CastOptionsProvider.kt').write_text(provider)
print('Patched native Google Cast channel and OptionsProvider:', p)
