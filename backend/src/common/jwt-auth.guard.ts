import { Injectable, CanActivate, ExecutionContext, HttpException, HttpStatus } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Request } from 'express';
import { PrismaService } from '../prisma/prisma.service';

export interface AccessTokenPayload {
  sub: string; // userId
  sid: string; // sessionId courante
  fid: string; // familyId (famille de rotation)
  typ: 'access';
}

/**
 * Garde JWT + vérification d'état de la session en base :
 * la révocation (logout, logout-all, changement/réinitialisation de mot de
 * passe, rotation) est donc effective IMMÉDIATEMENT, même si le jeton
 * d'accès de 15 min n'a pas expiré (CDC D01.3 « révocation des sessions »).
 */
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private jwt: JwtService,
    private prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<Request>();
    const header = request.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      throw new HttpException(
        { statusCode: HttpStatus.UNAUTHORIZED, code: 'UNAUTHORIZED', message: 'Jeton manquant.' },
        HttpStatus.UNAUTHORIZED,
      );
    }
    const token = header.slice('Bearer '.length).trim();
    let payload: AccessTokenPayload;
    try {
      payload = this.jwt.verify<AccessTokenPayload>(token);
      if (payload.typ !== 'access') throw new Error('type invalide');
    } catch {
      throw new HttpException(
        {
          statusCode: HttpStatus.UNAUTHORIZED,
          code: 'UNAUTHORIZED',
          message: 'Session expirée ou jeton invalide.',
        },
        HttpStatus.UNAUTHORIZED,
      );
    }

    // Vérification serveur de la session (révocation effective immédiate)
    const session = await this.prisma.session.findUnique({ where: { id: payload.sid } });
    if (!session || session.revokedAt !== null || session.expiresAt <= new Date()) {
      throw new HttpException(
        {
          statusCode: HttpStatus.UNAUTHORIZED,
          code: 'UNAUTHORIZED',
          message: 'Session révoquée. Reconnectez-vous.',
        },
        HttpStatus.UNAUTHORIZED,
      );
    }

    // Dernière utilisation (best effort — jamais bloquant)
    this.prisma.session
      .update({ where: { id: payload.sid }, data: { lastUsedAt: new Date() } })
      .catch(() => undefined);

    (request as Request & { user?: AccessTokenPayload }).user = payload;
    return true;
  }
}
