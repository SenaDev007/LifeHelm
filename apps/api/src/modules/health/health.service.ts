import { Injectable } from "@nestjs/common";
import { prisma } from "@lifehelm/database";

@Injectable()
export class HealthService {
  async check() {
    const db = await prisma.$queryRaw`SELECT 1+1 as result`;
    return {
      status: "ok",
      db: Array.isArray(db) ? "ok" : "ok",
      redis: process.env.REDIS_URL ? "ok" : "missing",
    };
  }
}

