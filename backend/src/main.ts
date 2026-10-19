import 'reflect-metadata';
// Le .env du projet DOIT gagner sur les variables d'environnement système
// (un DATABASE_URL externe ne doit jamais masquer la configuration locale).
import * as dotenv from 'dotenv';
dotenv.config({ override: true, quiet: true });

import { NestFactory } from '@nestjs/core';
import { ValidationPipe, Logger, HttpStatus } from '@nestjs/common';
import { AppModule } from './app.module';
import { HttpExceptionFilter } from './common/http-exception.filter';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });

  // Préfixe global REST (CDC §3)
  app.setGlobalPrefix('api/v1');

  // Validation stricte des DTO (class-validator) — whitelist : champs inconnus ignorés
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      transformOptions: { enableImplicitConversion: true },
      errorHttpStatusCode: HttpStatus.BAD_REQUEST,
    }),
  );

  // Format d'erreur homogène {statusCode, code, message}
  app.useGlobalFilters(new HttpExceptionFilter());

  // CORS ouvert (le mobile et la preview web appellent l'API en Bearer — pas de cookies)
  app.enableCors({
    origin: true,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  });

  const port = Number(process.env.PORT ?? 3001);
  await app.listen(port, '0.0.0.0');
  Logger.log(`LifeHelm API démarrée sur http://localhost:${port}/api/v1`, 'Bootstrap');
}

bootstrap();
