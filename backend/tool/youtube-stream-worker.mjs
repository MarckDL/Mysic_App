import process from 'node:process';
import { setTimeout, clearTimeout } from 'node:timers';
import { Buffer } from 'node:buffer';
/* global AbortController, AbortSignal, fetch */
import vm from 'node:vm';
import { URL } from 'node:url';
import { once } from 'node:events';
import { Innertube, Log, Platform, Constants } from 'youtubei.js';
import { SabrStream } from 'googlevideo/sabr-stream';
import {
  buildSabrFormat,
  EnabledTrackTypes,
  Logger,
  LogLevel,
} from 'googlevideo/utils';
Log.setLevel(Log.Level.NONE);
Logger.getInstance().setLogLevels(LogLevel.NONE);
// Proceso sin secretos, con permisos Node restringidos. VM no es frontera de seguridad.
Platform.shim.eval = async (data) =>
  new vm.Script(`(function(){${data.output}\n})()`).runInNewContext(
    Object.create(null),
    { timeout: 500, contextCodeGeneration: { strings: false, wasm: false } },
  );
const sourceId = process.argv[2];
let stream;
const protectionStates = [];
const abort = new AbortController();
process.once('disconnect', () => abort.abort());
process.stdout.on('error', () => abort.abort());
let timer = setTimeout(() => abort.abort(), 25000);
try {
  if (!/^[A-Za-z0-9_-]{11}$/.test(sourceId ?? '')) throw new Error();
  const fetcher = (input, init) => {
    const destination = new URL(
      typeof input === 'string' || input instanceof URL ? input : input.url,
    );
    const host = destination.hostname;
    if (
      destination.protocol !== 'https:' ||
      destination.username ||
      destination.password ||
      (destination.port && destination.port !== '443') ||
      !(
        host === 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host.endsWith('.googlevideo.com') ||
        host === 'youtubei.googleapis.com' ||
        host === 'www.gstatic.com'
      )
    ) {
      throw new Error('Unsupported provider destination');
    }
    return fetch(input, {
      ...init,
      redirect: 'error',
      signal: AbortSignal.any([
        abort.signal,
        AbortSignal.timeout(10_000),
        ...(init?.signal ? [init.signal] : []),
      ]),
    });
  };
  const yt = await Innertube.create({
    retrieve_player: true,
    enable_session_cache: false,
    fail_fast: true,
    fetch: fetcher,
  });
  const info = await yt.getBasicInfo(sourceId);
  if (
    info.basic_info.id !== sourceId ||
    info.basic_info.is_live ||
    info.playability_status?.status !== 'OK'
  )
    throw new Error('metadata-unavailable');
  const url = await yt.session.player.decipher(
    info.streaming_data?.server_abr_streaming_url,
  );
  const config =
    info.player_config?.media_common_config?.media_ustreamer_request_config
      ?.video_playback_ustreamer_config;
  if (
    !url ||
    !config ||
    new URL(url).protocol !== 'https:' ||
    !new URL(url).hostname.endsWith('.googlevideo.com')
  )
    throw new Error('no-sabr-config');
  stream = new SabrStream({
    videoId: sourceId,
    formats: info.streaming_data.adaptive_formats
      .filter((f) => f.has_audio && !f.has_video && !f.drm_families?.length)
      .map(buildSabrFormat),
    serverAbrStreamingUrl: url,
    videoPlaybackUstreamerConfig: config,
    clientInfo: {
      clientName: Number(
        Constants.CLIENT_NAME_IDS[yt.session.context.client.clientName],
      ),
      clientVersion: yt.session.context.client.clientVersion,
    },
    fetchFunction: fetcher,
  });
  let rejectStream;
  const failed = new Promise((_, reject) => (rejectStream = reject));
  stream.on('error', () => {
    rejectStream(new Error());
  });
  stream.on('streamProtectionStatusUpdate', (status) => {
    protectionStates.push(status.status);
    if (status.status === 3) {
      abort.abort();
      rejectStream(new Error());
      void stream.abort();
    }
  });
  const result = stream.start({
    enabledTrackTypes: EnabledTrackTypes.AUDIO_ONLY,
    audioPreferences: { container: 'mp4', preferredAudioCodec: 'aac' },
    isPostLiveDvr: false,
    maxRetries: 0,
    stallDetectionMs: 10000,
  });
  const reader = result.audioStream.getReader();
  const cancelled = new Promise((_, reject) =>
    abort.signal.addEventListener('abort', () => reject(new Error()), {
      once: true,
    }),
  );
  void failed.catch(() => {});
  void cancelled.catch(() => {});
  let started = false;
  let bytes = 0;
  while (!abort.signal.aborted) {
    const chunk = await Promise.race([reader.read(), failed, cancelled]);
    if (chunk.done) break;
    if (!started) {
      if (
        !result.selectedFormats.audioFormat?.mimeType?.startsWith('audio/mp4')
      )
        throw new Error();
      started = true;
      clearTimeout(timer);
      timer = setTimeout(() => abort.abort(), 20 * 60_000);
      process.send?.({ type: 'ready' });
    }
    const buffer = Buffer.from(
      chunk.value.buffer,
      chunk.value.byteOffset,
      chunk.value.byteLength,
    );
    bytes += buffer.length;
    if (bytes > 100_000_000) throw new Error();
    if (!process.stdout.write(buffer))
      await Promise.race([once(process.stdout, 'drain'), cancelled]);
  }
  if (!started || abort.signal.aborted) throw new Error();
  await new Promise((resolve) => process.stdout.end(resolve));

  abort.abort();
  void reader.cancel().catch(() => {});
} catch {
  process.send?.({ type: 'error' });
  process.exitCode = 1;
} finally {
  clearTimeout(timer);
  abort.abort();
  await Promise.race([
    stream?.abort().catch(() => {}),
    new Promise((resolve) => setTimeout(resolve, 500)),
  ]);
}

process.exit(process.exitCode ?? 0);
