// Clasifica errores locales sin devolver mensajes SDK que puedan incluir secretos.
export function databaseDiagnostic(error: unknown): string {
  const texts: string[] = [];
  const seen = new Set<object>();
  function visit(value: unknown, depth = 0): void {
    if (depth > 8) return;
    if (typeof value === 'string') {
      texts.push(value);
      return;
    }
    if (!value || typeof value !== 'object' || seen.has(value)) return;
    seen.add(value);
    const object = value as Record<string, unknown>;
    for (const key of [
      'message',
      'code',
      'originalCode',
      'originalMessage',
      'kind',
      'cause',
      'meta',
      'driverAdapterError',
      'error',
      'errors',
    ]) {
      visit(object[key], depth + 1);
    }
    if (Array.isArray(value)) for (const item of value) visit(item, depth + 1);
  }
  visit(error);
  const text = texts.join(' ');
  if (
    /certificate|self.signed|unable.to.verify|P1011|CERT_HAS_EXPIRED/i.test(
      text,
    )
  ) {
    return 'TLS: no se pudo validar el certificado del servidor.';
  }
  if (/password authentication|28P01|P1000|SASL|SCRAM/i.test(text)) {
    return 'Autenticación: el servidor rechazó las credenciales.';
  }
  if (/ENOTFOUND|EAI_AGAIN|getaddrinfo|resolve|translate host/i.test(text)) {
    return 'DNS: no se pudo resolver el servidor.';
  }
  if (/ECONNREFUSED|ETIMEDOUT|ENETUNREACH|timeout|P1001|P1002/i.test(text)) {
    return 'Red: servidor inaccesible o tiempo de conexión agotado.';
  }
  if (/permission denied|42501|P1010/i.test(text)) {
    return 'Permisos: el rol de PostgreSQL no permite esta operación.';
  }
  return 'Fallo no clasificado; no compartir mensajes completos ni credenciales.';
}
