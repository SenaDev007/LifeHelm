import * as crypto from 'crypto';

/** Hachage sha256 hexadécimal (refresh tokens, codes, reset tokens — jamais stockés en clair). */
export function sha256hex(value: string): string {
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}

/** Jeton opaque cryptographiquement sûr (hex). */
export function randomToken(bytes = 48): string {
  return crypto.randomBytes(bytes).toString('hex');
}

/** Code numérique à 6 chiffres (vérification courriel/téléphone). */
export function randomDigits(length = 6): string {
  let out = '';
  while (out.length < length) {
    out += crypto.randomInt(0, 10).toString();
  }
  return out;
}
