import * as crypto from 'crypto';

/**
 * TOTP RFC 6238 (2FA D01.3 §6.3 — « authentification à deux facteurs
 * configurable dès la V1 »). Implémentation autonome : HMAC-SHA1, 6 chiffres,
 * période 30 s, fenêtre de tolérance ±1 pas (codes acceptés t-1, t, t+1).
 */

const BASE32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/** Génère un secret base32 de 160 bits (20 octets) — standard des apps TOTP. */
export function generateTotpSecret(): string {
  const bytes = crypto.randomBytes(20);
  return base32Encode(bytes);
}

export function base32Encode(buffer: Buffer): string {
  let bits = 0;
  let value = 0;
  let output = '';
  for (const byte of buffer) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      output += BASE32_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) {
    output += BASE32_ALPHABET[(value << (5 - bits)) & 31];
  }
  return output;
}

export function base32Decode(input: string): Buffer {
  const clean = input.toUpperCase().replace(/[^A-Z2-7]/g, '');
  let bits = 0;
  let value = 0;
  const bytes: number[] = [];
  for (const char of clean) {
    const idx = BASE32_ALPHABET.indexOf(char);
    if (idx === -1) continue;
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      bytes.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Buffer.from(bytes);
}

/** Code TOTP pour un compteur temporel donné (t = epoch / 30). */
function totpAt(secret: Buffer, counter: number): string {
  const buf = Buffer.alloc(8);
  buf.writeUInt32BE(Math.floor(counter / 0x100000000), 0);
  buf.writeUInt32BE(counter % 0x100000000, 4);
  const hmac = crypto.createHmac('sha1', secret).update(buf).digest();
  const offset = hmac[hmac.length - 1] & 0x0f;
  const code =
    ((hmac[offset] & 0x7f) << 24) |
    ((hmac[offset + 1] & 0xff) << 16) |
    ((hmac[offset + 2] & 0xff) << 8) |
    (hmac[offset + 3] & 0xff);
  return (code % 1_000_000).toString().padStart(6, '0');
}

export function currentTotp(secretBase32: string, at: number = Date.now()): string {
  return totpAt(base32Decode(secretBase32), Math.floor(at / 1000 / 30));
}

/** Vérifie un code avec fenêtre ±1 pas, en comparaison temps constant. */
export function verifyTotp(secretBase32: string, code: string, at: number = Date.now()): boolean {
  const clean = (code ?? '').replace(/\s/g, '');
  if (!/^\d{6}$/.test(clean)) return false;
  const secret = base32Decode(secretBase32);
  const step = Math.floor(at / 1000 / 30);
  for (const delta of [0, -1, 1]) {
    if (crypto.timingSafeEqual(Buffer.from(totpAt(secret, step + delta)), Buffer.from(clean))) {
      return true;
    }
  }
  return false;
}

/** URL otpauth:// pour les applications d'authentification (Google Authenticator…). */
export function otpauthUrl(secretBase32: string, account: string): string {
  const label = encodeURIComponent(`LifeHelm:${account}`);
  return `otpauth://totp/${label}?secret=${secretBase32}&issuer=LifeHelm&algorithm=SHA1&digits=6&period=30`;
}
