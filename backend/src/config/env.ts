export function readPort(value = process.env.PORT): number {
  const port = value === undefined ? 3000 : Number(value);
  if (!value?.trim() && value !== undefined) {
    throw new Error('PORT debe ser un entero entre 1 y 65535');
  }
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT debe ser un entero entre 1 y 65535');
  }
  return port;
}
