import process from 'node:process';
import console from 'node:console';
import { setTimeout, clearTimeout } from 'node:timers';
import { Buffer } from 'node:buffer';
/* global AbortController, AbortSignal, fetch */
import vm from 'node:vm';
import { writeFile, mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
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
// Diagnóstico CLI solamente: VM no es una frontera de seguridad de producción.
// Fuente fija autorizada; no acepta cookies, tokens, URLs ni IDs arbitrarios.
// Transformación normal de URL del SDK, sin módulos, red ni objetos del host en el contexto.
Platform.shim.eval = async (data) =>
  new vm.Script(`(function(){${data.output}\n})()`).runInNewContext(
    Object.create(null),
    { timeout: 500, contextCodeGeneration: { strings: false, wasm: false } },
  );
let stage = 'session';
let stream;
let reason;
const protectionStates = [];
const abort = new AbortController();
const timer = setTimeout(() => abort.abort(), 25000);
try {
  const fetcher = (input, init) =>
    fetch(input, {
      ...init,
      signal: AbortSignal.any([
        abort.signal,
        AbortSignal.timeout(10000),
        ...(init?.signal ? [init.signal] : []),
      ]),
    });
  const yt = await Innertube.create({
    retrieve_player: true,
    enable_session_cache: false,
    fail_fast: true,
    fetch: fetcher,
  });
  stage = 'metadata';
  const info = await yt.getBasicInfo('aqz-KE-bpKQ');
  if (info.playability_status?.status !== 'OK')
    throw new Error('metadata-unavailable');
  const url = await yt.session.player.decipher(
    info.streaming_data?.server_abr_streaming_url,
  );
  const config =
    info.player_config?.media_common_config?.media_ustreamer_request_config
      ?.video_playback_ustreamer_config;
  if (!url || !config) throw new Error('no-sabr-config');
  stage = 'sabr';
  stream = new SabrStream({
    videoId: 'aqz-KE-bpKQ',
    formats: info.streaming_data.adaptive_formats.map(buildSabrFormat),
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
    reason ??= 'stream-error';
    rejectStream(new Error());
  });
  stream.on('streamProtectionStatusUpdate', (status) => {
    protectionStates.push(status.status);
    if (status.status === 3) {
      reason = 'provider-verification-rejected';
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
  const chunks = [];
  let bytes = 0;
  let hasMoof = false;
  let hasMdat = false;
  while (bytes < 128000) {
    const chunk = await Promise.race([reader.read(), failed, cancelled]);
    if (chunk.done) break;
    const buffer = Buffer.from(
      chunk.value.buffer,
      chunk.value.byteOffset,
      chunk.value.byteLength,
    );
    if (bytes + buffer.length > 2_000_000) throw new Error('sample-limit');
    chunks.push(buffer);
    bytes += buffer.length;
    hasMoof ||= buffer.includes(Buffer.from('moof'));
    hasMdat ||= buffer.includes(Buffer.from('mdat'));
    if (hasMdat && bytes > 24000) break;
  }
  if (!hasMdat) throw new Error('no-media');
  const directory = await mkdtemp(join(tmpdir(), 'mysic-native-'));
  const samplePath = join(directory, 'big-buck-bunny.m4a');
  await writeFile(samplePath, Buffer.concat(chunks), {
    flag: 'wx',
    mode: 0o600,
  });
  console.log(
    JSON.stringify({
      stage: 'media-bytes',
      samplePath,
      attribution: '(c) 2008 Blender Foundation / bigbuckbunny.org — CC BY 3.0',
      sourceId: 'aqz-KE-bpKQ',
      mime: result.selectedFormats.audioFormat.mimeType,
      bytes,
      hasMoof,
      hasMdat,
      protectionStates,
      audioPlaybackVerified: false,
    }),
  );

  abort.abort();
  void reader.cancel().catch(() => {});
} catch (error) {
  console.log(
    JSON.stringify({
      stage,
      success: false,
      protectionStates,
      reason:
        reason ??
        (protectionStates.includes(2)
          ? 'verification-pending-no-audio'
          : abort.signal.aborted
            ? 'timeout'
            : error?.message === 'metadata-unavailable'
              ? 'metadata-unavailable'
              : 'integration-failed'),
    }),
  );
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
