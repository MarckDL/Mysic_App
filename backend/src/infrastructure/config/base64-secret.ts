export function readBase64Secret(name: string): string | undefined {
  const encoded = process.env[name]?.trim();
  if (!encoded) return undefined;
  if (!/^[A-Za-z0-9+/]+={0,2}$/u.test(encoded) || encoded.length % 4 !== 0) {
    throw new Error(`${name} no contiene Base64 válido`);
  }
  const decoded = Buffer.from(encoded, 'base64');
  const normalizedInput = encoded.replace(/=+$/u, '');
  const normalizedOutput = decoded.toString('base64').replace(/=+$/u, '');
  if (!decoded.length || normalizedInput !== normalizedOutput) {
    throw new Error(`${name} no contiene Base64 válido`);
  }
  return decoded.toString('utf8');
}
