import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
} from 'node:crypto';
import { root } from '../../modules/integrations/youtube/domain.js';

export const randomRef = () => randomBytes(32).toString('base64url');
export const digest = (value: string) =>
  createHash('sha256').update(value).digest('base64url');

export class SecretBox {
  constructor(
    private readonly active: string,
    private readonly keys: ReadonlyMap<string, Buffer>,
  ) {
    if (
      !keys.has(active) ||
      [...keys].some(
        ([id, key]) => !/^[A-Za-z0-9_-]{1,32}$/.test(id) || key.length !== 32,
      )
    )
      throw new Error('Invalid YouTube encryption keyring');
  }
  seal(value: string, context: string) {
    const iv = randomBytes(12);
    const cipher = createCipheriv(
      'aes-256-gcm',
      this.keys.get(this.active)!,
      iv,
    );
    cipher.setAAD(Buffer.from(context));
    const data = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
    return [
      this.active,
      iv.toString('base64url'),
      cipher.getAuthTag().toString('base64url'),
      data.toString('base64url'),
    ].join('.');
  }
  open(box: string, context: string) {
    const parts = box.split('.');
    const [id, iv, tag, data] = parts;
    const key = id && this.keys.get(id);
    if (
      parts.length !== 4 ||
      !key ||
      !iv ||
      !tag ||
      !data ||
      Buffer.from(tag, 'base64url').length !== 16
    )
      throw new Error('Invalid YouTube envelope');
    const cipher = createDecipheriv(
      'aes-256-gcm',
      key,
      Buffer.from(iv, 'base64url'),
      { authTagLength: 16 },
    );
    cipher.setAAD(Buffer.from(context));
    cipher.setAuthTag(Buffer.from(tag, 'base64url'));
    return Buffer.concat([
      cipher.update(Buffer.from(data, 'base64url')),
      cipher.final(),
    ]).toString('utf8');
  }
}
function endpoint(value: string | undefined) {
  let url: URL;
  try {
    url = new URL(value ?? '');
  } catch {
    throw new Error('Invalid YouTube HTTPS endpoint');
  }
  if (
    url.protocol !== 'https:' ||
    url.username ||
    url.password ||
    url.search ||
    url.hash
  )
    throw new Error('Invalid YouTube HTTPS endpoint');
  return url;
}
export function youtubeConfig(env: NodeJS.ProcessEnv = process.env) {
  const enabled = env.YOUTUBE_LINK_ENABLED === 'true';
  if (!enabled && !env.YOUTUBE_OAUTH_CLIENT_ID && !env.YOUTUBE_TOKEN_KEYS)
    return null;
  const callback = endpoint(env.YOUTUBE_OAUTH_CALLBACK);
  const appReturn = endpoint(env.YOUTUBE_APP_RETURN);
  const id = env.YOUTUBE_OAUTH_CLIENT_ID,
    secret = env.YOUTUBE_OAUTH_CLIENT_SECRET;
  if (
    !id ||
    !secret ||
    callback.pathname !== root + '/oauth/callback' ||
    appReturn.href === callback.href
  )
    throw new Error('Invalid YouTube OAuth configuration');
  let keys: unknown;
  try {
    keys = JSON.parse(env.YOUTUBE_TOKEN_KEYS ?? '{}');
  } catch {
    throw new Error('Invalid YouTube encryption keyring');
  }
  if (!keys || typeof keys !== 'object' || Array.isArray(keys))
    throw new Error('Invalid YouTube encryption keyring');
  const decoded = new Map<string, Buffer>();
  for (const [version, raw] of Object.entries(keys)) {
    if (typeof raw !== 'string' || !/^[A-Za-z0-9+/]{43}=$/.test(raw))
      throw new Error('Invalid YouTube encryption key');
    decoded.set(version, Buffer.from(raw, 'base64'));
  }
  return {
    enabled,
    callback,
    appReturn,
    id,
    secret,
    box: new SecretBox(env.YOUTUBE_TOKEN_KEY_ID ?? '', decoded),
  };
}
