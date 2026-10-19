import { CanActivate, ExecutionContext, HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Request } from 'express';

export const THROTTLE_KEY = 'throttle:config';
export interface ThrottleConfig {
  limit: number; // requêtes max
  windowMs: number; // par fenêtre glissante
}

interface Bucket {
  count: number;
  resetAt: number;
}

/**
 * Garde anti-bruteforce en mémoire (MVP mono-instance — le CDC laisse le
 * fournisseur de rate-limiting en arbitrage ; Redis sera branché en prod).
 * Appliquée aux routes sensibles : login, register, forgot, refresh.
 */
@Injectable()
export class ThrottleGuard implements CanActivate {
  private buckets = new Map<string, Bucket>();

  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const config = this.reflector.get<ThrottleConfig | undefined>(
      THROTTLE_KEY,
      context.getHandler(),
    );
    if (!config) return true;

    const request = context.switchToHttp().getRequest<Request>();
    const ip = (request.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
      ?? request.socket.remoteAddress
      ?? 'inconnu';
    const key = `${ip}:${context.getHandler().name}`;
    const now = Date.now();

    let bucket = this.buckets.get(key);
    if (!bucket || bucket.resetAt <= now) {
      bucket = { count: 0, resetAt: now + config.windowMs };
      this.buckets.set(key, bucket);
    }
    bucket.count += 1;

    if (bucket.count > config.limit) {
      const retry = Math.ceil((bucket.resetAt - now) / 1000);
      throw new HttpException(
        {
          statusCode: HttpStatus.TOO_MANY_REQUESTS,
          code: 'RATE_LIMITED',
          message: `Trop de tentatives. Réessayez dans ${retry} s.`,
        },
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    // Nettoyage périodique simple
    if (this.buckets.size > 5000) {
      for (const [k, b] of this.buckets) if (b.resetAt <= now) this.buckets.delete(k);
    }
    return true;
  }
}

export function Throttle(limit: number, windowMs: number): MethodDecorator {
  return (
    _target: object,
    _propertyKey: string | symbol,
    descriptor: PropertyDescriptor,
  ) => {
    Reflect.defineMetadata(THROTTLE_KEY, { limit, windowMs } satisfies ThrottleConfig, descriptor.value);
    return descriptor;
  };
}
