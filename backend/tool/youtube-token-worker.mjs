import process from 'node:process';
import { URL } from 'node:url';
import vm from 'node:vm';
import { BotGuardClient, getChallenge } from 'bgutils-js/botguard';
import { buildURL, getHeaders, USER_AGENT } from 'bgutils-js/utils';
import { WebPoMinter } from 'bgutils-js/webpo';
import { JSDOM } from 'jsdom';
import { Innertube, Log, Platform } from 'youtubei.js';

/* global AbortSignal, fetch, Request */

const REQUEST_KEY = 'O43z0dpjhgX20SCx4KAo';
const SOURCE_ID = /^[A-Za-z0-9_-]{11}$/;
const MAX_REDIRECTS = 4;
const MIN_TTL_MS = 60_000;
const DEFAULT_TTL_MS = 10 * 60_000;
const MAX_TTL_MS = 60 * 60_000;
const FAILURE_TTL_MS = 2 * 60_000;
const CLIENTS = ['YTMUSIC', 'WEB', 'VISIONOS', 'TV_SIMPLY'];
const contentTokens = new Map();
const contentRequests = new Map();
const resolutions = new Map();
const resolutionRequests = new Map();
const failedCandidates = new Map();
let bootstrapRequest;
let botGuard;
let dom;
let closing = false;

Log.setLevel(Log.Level.NONE);
Platform.shim.eval = async (data) =>
  new vm.Script(`(function(){${data.output}\n})()`, {
    filename: 'player-interpreter.js',
  }).runInNewContext(Object.create(null), {
    timeout: 1_000,
    contextCodeGeneration: { strings: false, wasm: false },
  });

function checkedUrl(input) {
  const raw =
    typeof input === 'string' || input instanceof URL ? input : input.url;
  const url = new URL(raw);
  const host = url.hostname;
  if (
    url.protocol !== 'https:' ||
    url.username ||
    url.password ||
    (url.port && url.port !== '443') ||
    !(
      host === 'youtube.com' ||
      host.endsWith('.youtube.com') ||
      host === 'googleapis.com' ||
      host.endsWith('.googleapis.com') ||
      host.endsWith('.googlevideo.com')
    )
  )
    throw new Error('destination-rejected');
  return url;
}

async function restrictedFetch(input, init = {}, redirectCount = 0) {
  const url = checkedUrl(input);
  const requestInput = input instanceof Request ? input : url;
  const method =
    init.method ?? (input instanceof Request ? input.method : undefined);
  const response = await fetch(requestInput, {
    ...init,
    redirect: 'manual',
    signal: AbortSignal.any([
      AbortSignal.timeout(12_000),
      ...(init.signal ? [init.signal] : []),
    ]),
  });
  if (![301, 302, 303, 307, 308].includes(response.status)) return response;
  if (redirectCount >= MAX_REDIRECTS) throw new Error('redirect-limit');
  const location = response.headers.get('location');
  if (!location) throw new Error('redirect-invalid');
  const next = checkedUrl(new URL(location, url));
  const switchToGet =
    response.status === 303 ||
    ((response.status === 301 || response.status === 302) &&
      method?.toUpperCase() === 'POST');
  return restrictedFetch(
    next,
    switchToGet ? { ...init, method: 'GET', body: undefined } : init,
    redirectCount + 1,
  );
}

function installDom() {
  dom = new JSDOM('<!doctype html><html><body></body></html>', {
    url: 'https://www.youtube.com/',
    referrer: 'https://www.youtube.com/',
    userAgent: USER_AGENT,
  });
  Object.assign(globalThis, {
    window: dom.window,
    document: dom.window.document,
    location: dom.window.location,
    origin: dom.window.origin,
  });
  if (!Reflect.has(globalThis, 'navigator'))
    Object.defineProperty(globalThis, 'navigator', {
      configurable: true,
      value: dom.window.navigator,
    });
}

async function bootstrap() {
  installDom();
  const visitorSession = await Innertube.create({
    retrieve_player: false,
    enable_session_cache: false,
    fail_fast: true,
    fetch: restrictedFetch,
  });
  const visitorData = visitorSession.session.context.client.visitorData;
  if (!visitorData) throw new Error('visitor-unavailable');
  const challenge = await getChallenge({
    fetchFunction: restrictedFetch,
    requestKey: REQUEST_KEY,
  });
  const javascript =
    challenge.interpreterJavascript
      ?.privateDoNotAccessOrElseSafeScriptWrappedValue;
  if (!javascript) throw new Error('interpreter-unavailable');
  new vm.Script(javascript, {
    filename: 'provider-interpreter.js',
  }).runInThisContext({ timeout: 2_000 });
  botGuard = await BotGuardClient.create({
    program: challenge.program,
    globalName: challenge.globalName,
    globalObject: globalThis,
  });
  const webPoSignalOutput = [];
  const botguardResponse = await botGuard.snapshot({ webPoSignalOutput });
  const integrityResponse = await restrictedFetch(
    buildURL('GenerateIT', true),
    {
      method: 'POST',
      headers: getHeaders(),
      body: JSON.stringify([REQUEST_KEY, botguardResponse]),
    },
  );
  if (!integrityResponse.ok) throw new Error('integrity-unavailable');
  const values = await integrityResponse.json();
  if (!Array.isArray(values) || typeof values[0] !== 'string')
    throw new Error('integrity-invalid');
  const [integrityToken, ttlSeconds, mintRefreshThreshold, fallbackToken] =
    values;
  const minter = await WebPoMinter.create(
    {
      integrityToken,
      estimatedTtlSecs: ttlSeconds,
      mintRefreshThreshold,
      websafeFallbackToken: fallbackToken,
    },
    webPoSignalOutput,
  );
  const sessionPoToken = await minter.mintAsWebsafeString(visitorData);
  const yt = await Innertube.create({
    visitor_data: visitorData,
    po_token: sessionPoToken,
    retrieve_player: true,
    enable_session_cache: false,
    fail_fast: true,
    fetch: restrictedFetch,
  });
  if (!yt.session.player) throw new Error('player-unavailable');
  const providerTtl =
    typeof ttlSeconds === 'number' && Number.isFinite(ttlSeconds)
      ? ttlSeconds * 1_000 - 60_000
      : DEFAULT_TTL_MS;
  const ttlMs = Math.floor(
    Math.max(MIN_TTL_MS, Math.min(MAX_TTL_MS, providerTtl)),
  );
  return { minter, yt, expiresAtMs: Date.now() + ttlMs };
}

function getContext() {
  bootstrapRequest ??= bootstrap().catch(async (error) => {
    bootstrapRequest = undefined;
    await reset();
    throw error;
  });
  return bootstrapRequest;
}

async function prepare(sourceId) {
  const cached = contentTokens.get(sourceId);
  if (cached && cached.expiresAtMs > Date.now() + 30_000) return cached;
  const current = contentRequests.get(sourceId);
  if (current) return current;
  const request = (async () => {
    const context = await getContext();
    if (context.expiresAtMs <= Date.now() + 30_000) {
      bootstrapRequest = undefined;
      await reset();
      return prepare(sourceId);
    }
    const token = await context.minter.mintAsWebsafeString(sourceId);
    const value = { token, expiresAtMs: context.expiresAtMs };
    contentTokens.set(sourceId, value);
    return value;
  })().finally(() => contentRequests.delete(sourceId));
  contentRequests.set(sourceId, request);
  return request;
}

function candidateFormats(info) {
  return (info.streaming_data?.adaptive_formats ?? [])
    .filter(
      (format) =>
        format.has_audio &&
        !format.has_video &&
        !format.drm_families?.length &&
        Number.isSafeInteger(format.content_length) &&
        format.content_length > 0 &&
        Number.isFinite(format.approx_duration_ms) &&
        format.approx_duration_ms > 0 &&
        /^audio\/(?:mp4|webm)(?:; codecs="[A-Za-z0-9., _-]+")?$/.test(
          format.mime_type,
        ),
    )
    .sort((left, right) => {
      const leftMp4 = left.mime_type.startsWith('audio/mp4') ? 1 : 0;
      const rightMp4 = right.mime_type.startsWith('audio/mp4') ? 1 : 0;
      return rightMp4 - leftMp4 || right.bitrate - left.bitrate;
    });
}

async function validateTail(url, contentLength) {
  const start = Math.max(0, contentLength - 256);
  const response = await restrictedFetch(url, {
    headers: {
      Range: `bytes=${start}-${contentLength - 1}`,
      'User-Agent': USER_AGENT,
    },
  });
  if (response.status === 403) {
    const error = new Error('provider-rejected');
    error.status = 403;
    throw error;
  }
  if (response.status !== 206 || !response.headers.get('content-range'))
    throw new Error('tail-invalid');
  const declaredLength = Number(response.headers.get('content-length'));
  if (Number.isFinite(declaredLength) && declaredLength > 256)
    throw new Error('tail-too-large');
  const reader = response.body?.getReader();
  if (!reader) throw new Error('tail-empty');
  let received = 0;
  while (true) {
    const chunk = await reader.read();
    if (chunk.done) break;
    received += chunk.value.byteLength;
    if (received > 256) {
      await reader.cancel();
      throw new Error('tail-too-large');
    }
  }
  if (received === 0) throw new Error('tail-empty');
}

async function resolveClient(context, sourceId, client, token) {
  const info = await context.yt.getBasicInfo(sourceId, {
    client,
    po_token: token,
  });
  if (
    info.basic_info.id !== sourceId ||
    info.basic_info.is_live ||
    info.playability_status?.status !== 'OK'
  )
    throw new Error('not-playable');
  const formats = candidateFormats(info);
  if (!formats.length) throw new Error('format-unavailable');
  for (const format of formats) {
    try {
      const rawUrl = await format.decipher(context.yt.session.player);
      const url = checkedUrl(rawUrl);
      if (!url.hostname.endsWith('.googlevideo.com'))
        throw new Error('media-host-invalid');
      url.searchParams.set('pot', token);
      await validateTail(url, format.content_length);
      const urlExpiry = Number(url.searchParams.get('expire')) * 1_000 - 60_000;
      const expiresAtMs = Math.min(
        context.expiresAtMs,
        Number.isSafeInteger(urlExpiry) && urlExpiry > Date.now()
          ? urlExpiry
          : context.expiresAtMs,
      );
      return {
        sourceId,
        client,
        itag: format.itag,
        privateUrl: url.href,
        mimeType: format.mime_type,
        contentLength: format.content_length,
        durationMs: format.approx_duration_ms,
        expiresAtMs,
      };
    } catch (error) {
      if (error?.status === 403) throw error;
    }
  }
  throw new Error('format-validation-failed');
}

async function resolveSource(sourceId) {
  const cached = resolutions.get(sourceId);
  if (cached && cached.expiresAtMs > Date.now() + 30_000) return cached;
  const active = resolutionRequests.get(sourceId);
  if (active) return active;
  const request = (async () => {
    let content = await prepare(sourceId);
    const context = await getContext();
    for (const client of CLIENTS) {
      const failureKey = `${sourceId}:${client}`;
      const failedUntil = failedCandidates.get(failureKey) ?? 0;
      if (failedUntil > Date.now()) continue;
      try {
        const resolved = await resolveClient(
          context,
          sourceId,
          client,
          content.token,
        );
        resolutions.set(sourceId, resolved);
        return resolved;
      } catch (error) {
        if (error?.status === 403) {
          contentTokens.delete(sourceId);
          content = await prepare(sourceId);
          try {
            const resolved = await resolveClient(
              context,
              sourceId,
              client,
              content.token,
            );
            resolutions.set(sourceId, resolved);
            return resolved;
          } catch {
            // El rechazo se registra y el siguiente cliente continúa.
          }
        }
        failedCandidates.set(failureKey, Date.now() + FAILURE_TTL_MS);
      }
    }
    throw new Error('no-client-available');
  })().finally(() => resolutionRequests.delete(sourceId));
  resolutionRequests.set(sourceId, request);
  return request;
}

async function reset() {
  contentTokens.clear();
  resolutions.clear();
  failedCandidates.clear();
  await botGuard?.shutdown().catch(() => {});
  botGuard = undefined;
  dom?.window.close();
  dom = undefined;
}

async function shutdown() {
  if (closing) return;
  closing = true;
  await reset();
  process.disconnect?.();
}

process.on('message', (message) => {
  if (!message || typeof message !== 'object' || closing) return;
  if (message.type === 'shutdown') {
    void shutdown();
    return;
  }
  if (message.type === 'invalidate' && SOURCE_ID.test(message.sourceId ?? '')) {
    contentTokens.delete(message.sourceId);
    resolutions.delete(message.sourceId);
    for (const client of CLIENTS)
      failedCandidates.delete(`${message.sourceId}:${client}`);
    return;
  }
  if (
    !['prepare', 'resolve'].includes(message.type) ||
    !Number.isSafeInteger(message.requestId) ||
    !SOURCE_ID.test(message.sourceId ?? '')
  )
    return;
  const operation =
    message.type === 'resolve'
      ? resolveSource(message.sourceId)
      : prepare(message.sourceId);
  void operation
    .then((result) =>
      process.send?.(
        message.type === 'resolve'
          ? { type: 'resolved', requestId: message.requestId, ...result }
          : {
              type: 'ready',
              requestId: message.requestId,
              sourceId: message.sourceId,
              expiresAtMs: result.expiresAtMs,
            },
      ),
    )
    .catch(() =>
      process.send?.({ type: 'error', requestId: message.requestId }),
    );
});
process.once('disconnect', () => void shutdown());
process.once('SIGTERM', () => void shutdown());
