import console from 'node:console';
import process from 'node:process';
import { URL } from 'node:url';
import vm from 'node:vm';
import { BotGuardClient, getChallenge } from 'bgutils-js/botguard';
import { buildURL, getHeaders, USER_AGENT } from 'bgutils-js/utils';
import { WebPoMinter } from 'bgutils-js/webpo';
import { JSDOM } from 'jsdom';
import { Innertube, Log, Platform } from 'youtubei.js';

/* global AbortSignal, fetch, Request */

const args = process.argv.slice(2).filter((arg) => arg !== '--');
const SOURCE_ID = args[0] ?? 'aqz-KE-bpKQ';
const REQUEST_KEY = 'O43z0dpjhgX20SCx4KAo';
const MAX_REDIRECTS = 4;
const RANGE_SIZE = 256 * 1024;
const CLIENTS = ['YTMUSIC', 'WEB', 'VISIONOS', 'TV_SIMPLY'];

Log.setLevel(Log.Level.NONE);

function isAllowedHost(hostname) {
  return (
    hostname === 'youtube.com' ||
    hostname.endsWith('.youtube.com') ||
    hostname === 'googleapis.com' ||
    hostname.endsWith('.googleapis.com') ||
    hostname.endsWith('.googlevideo.com')
  );
}

function checkedUrl(input) {
  const raw =
    typeof input === 'string' || input instanceof URL ? input : input.url;
  const url = new URL(raw);
  if (
    url.protocol !== 'https:' ||
    url.username ||
    url.password ||
    !isAllowedHost(url.hostname)
  ) {
    throw new Error('network-target-rejected');
  }
  return url;
}

function safeErrorMessage(error) {
  if (!(error instanceof Error)) return 'unknown-error';
  return error.message
    .replace(/https?:\/\/\S+/g, '[url]')
    .replace(/[A-Za-z0-9_-]{30,}/g, '[redacted]')
    .slice(0, 180);
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
  if (!location) throw new Error('redirect-without-location');
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

function installBrowserGlobals() {
  const dom = new JSDOM('<!doctype html><html><body></body></html>', {
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
  if (!Reflect.has(globalThis, 'navigator')) {
    Object.defineProperty(globalThis, 'navigator', {
      configurable: true,
      value: dom.window.navigator,
    });
  }
  return dom;
}

async function createMinter() {
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
  const botGuard = await BotGuardClient.create({
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
  if (!integrityResponse.ok) throw new Error('integrity-token-unavailable');
  const values = await integrityResponse.json();
  if (!Array.isArray(values) || typeof values[0] !== 'string') {
    throw new Error('invalid-integrity-response');
  }
  const [
    integrityToken,
    estimatedTtlSecs,
    mintRefreshThreshold,
    websafeFallbackToken,
  ] = values;
  const minter = await WebPoMinter.create(
    {
      integrityToken,
      estimatedTtlSecs,
      mintRefreshThreshold,
      websafeFallbackToken,
    },
    webPoSignalOutput,
  );
  return { botGuard, minter };
}

async function readRange(url, start, end, label) {
  const response = await restrictedFetch(url, {
    headers: { Range: `bytes=${start}-${end}`, 'User-Agent': USER_AGENT },
  });
  const bytes = new Uint8Array(await response.arrayBuffer());
  const expectedMaximum = end - start + 1;
  if (
    response.status !== 206 ||
    bytes.byteLength === 0 ||
    bytes.byteLength > expectedMaximum
  ) {
    throw new Error(`range-${label}-invalid`);
  }
  return {
    label,
    status: response.status,
    bytes: bytes.byteLength,
    contentRangePresent: Boolean(response.headers.get('content-range')),
  };
}

async function resolveFormat(yt, contentPoToken) {
  const attempts = [];
  for (const client of CLIENTS) {
    let clientStage = 'metadata';
    try {
      const info = await yt.getBasicInfo(SOURCE_ID, {
        client,
        po_token: contentPoToken,
      });
      if (info.playability_status?.status !== 'OK') {
        attempts.push({ client, result: 'not-playable' });
        continue;
      }
      clientStage = 'format';
      const format = info.chooseFormat({ quality: 'best', type: 'audio' });
      if (!format.content_length || !format.bitrate || format.has_video) {
        attempts.push({ client, result: 'no-bounded-audio' });
        continue;
      }
      clientStage = 'decipher';
      const rawUrl = await format.decipher(yt.session.player);
      clientStage = 'url-validation';
      const url = checkedUrl(rawUrl);
      url.searchParams.set('pot', contentPoToken);
      return { attempts, client, format, url };
    } catch (error) {
      attempts.push({
        client,
        result: `failed-${clientStage}`,
        errorType: error instanceof Error ? error.name : 'UnknownError',
        diagnostic: safeErrorMessage(error),
      });
    }
  }
  throw new Error(`no-client-format:${JSON.stringify(attempts)}`);
}

let stage = 'environment';
let botGuard;
let dom;
try {
  if (args.length > 1 || !/^[A-Za-z0-9_-]{11}$/.test(SOURCE_ID))
    throw new Error('invalid-source-id');
  dom = installBrowserGlobals();
  Platform.shim.eval = async (data) =>
    new vm.Script(`(function(){${data.output}\n})()`, {
      filename: 'player-interpreter.js',
    }).runInNewContext(Object.create(null), {
      timeout: 1_000,
      contextCodeGeneration: { strings: false, wasm: false },
    });

  stage = 'visitor-session';
  const visitorSession = await Innertube.create({
    retrieve_player: false,
    enable_session_cache: false,
    fail_fast: true,
    fetch: restrictedFetch,
  });
  const visitorData = visitorSession.session.context.client.visitorData;
  if (!visitorData) throw new Error('visitor-data-unavailable');

  stage = 'attestation';
  const created = await createMinter();
  botGuard = created.botGuard;
  const sessionPoToken = await created.minter.mintAsWebsafeString(visitorData);
  const contentPoToken = await created.minter.mintAsWebsafeString(SOURCE_ID);

  stage = 'player-session';
  const yt = await Innertube.create({
    visitor_data: visitorData,
    po_token: sessionPoToken,
    retrieve_player: true,
    enable_session_cache: false,
    fail_fast: true,
    fetch: restrictedFetch,
  });

  stage = 'format-resolution';
  const resolved = await resolveFormat(yt, contentPoToken);
  const contentLength = resolved.format.content_length;
  const bytesPerSecond = resolved.format.bitrate / 8;
  const afterMinuteStart = Math.min(
    Math.floor(bytesPerSecond * 90),
    contentLength - RANGE_SIZE - 1,
  );
  const tailStart = Math.max(0, contentLength - RANGE_SIZE);
  if (afterMinuteStart <= RANGE_SIZE || tailStart <= afterMinuteStart) {
    throw new Error('media-too-short-for-probe');
  }

  stage = 'range-validation';
  const ranges = [];
  ranges.push(await readRange(resolved.url, 0, RANGE_SIZE - 1, 'start'));
  ranges.push(
    await readRange(
      resolved.url,
      afterMinuteStart,
      afterMinuteStart + RANGE_SIZE - 1,
      'after-90-seconds',
    ),
  );
  ranges.push(
    await readRange(resolved.url, tailStart, contentLength - 1, 'tail'),
  );

  console.info(
    JSON.stringify({
      success: true,
      sourceId: SOURCE_ID,
      attribution: '(c) 2008 Blender Foundation / bigbuckbunny.org — CC BY 3.0',
      client: resolved.client,
      mimeType: resolved.format.mime_type,
      contentLength,
      durationMs: resolved.format.approx_duration_ms,
      ranges,
      failedClientsBeforeSelection: resolved.attempts,
      secretsPrinted: false,
    }),
  );
} catch (error) {
  console.error(
    JSON.stringify({
      success: false,
      stage,
      reason:
        error instanceof Error && error.message.startsWith('no-client-format:')
          ? error.message
          : error instanceof Error
            ? error.message
            : 'unknown-error',
      secretsPrinted: false,
    }),
  );
  process.exitCode = 1;
} finally {
  await botGuard?.shutdown().catch(() => {});
  dom?.window.close();
}
