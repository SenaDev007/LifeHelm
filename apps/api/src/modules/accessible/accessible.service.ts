import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { prisma } from "@lifehelm/database";
import { CreateShopLogDto } from "./dto/create-shop-log.dto";
import { UpdateShopLogDto } from "./dto/update-shop-log.dto";

function toISODateLocal(d: Date) {
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function parseISODate(dateStr: string) {
  // Prisma @db.Date expects a Date object; we interpret the string as UTC midnight.
  return new Date(`${dateStr}T00:00:00.000Z`);
}

@Injectable()
export class AccessibleService {
  async getToday(userId?: string) {
    if (!userId) throw new BadRequestException("Non authentifié");
    const dateStr = toISODateLocal(new Date());
    const date = parseISODate(dateStr);

    const log = await prisma.dailyShopLog.findUnique({
      where: {
        userId_date: {
          userId,
          date,
        },
      },
    });

    return log ?? null;
  }

  async createOrUpdate(userId?: string, dto?: CreateShopLogDto) {
    if (!userId) throw new BadRequestException("Non authentifié");
    if (!dto) throw new BadRequestException("Données manquantes");

    const date = parseISODate(dto.date);
    const capitalMatin = dto.capitalMatin ?? 0;
    const recettes = dto.recettes ?? 0;
    const reapprovisionnement = dto.reapprovisionnement ?? 0;
    const beneficeNet = recettes - reapprovisionnement;

    const log = await prisma.dailyShopLog.upsert({
      where: {
        userId_date: {
          userId,
          date,
        },
      },
      create: {
        userId,
        date,
        capitalMatin,
        recettes,
        reapprovisionnement,
        beneficeNet,
        note: dto.note ?? null,
      },
      update: {
        capitalMatin,
        recettes,
        reapprovisionnement,
        beneficeNet,
        note: dto.note ?? null,
      },
    });

    return log;
  }

  async patch(userId: string | undefined, id: string, dto?: UpdateShopLogDto) {
    if (!userId) throw new BadRequestException("Non authentifié");
    if (!dto) throw new BadRequestException("Données manquantes");

    const existing = await prisma.dailyShopLog.findUnique({ where: { id } });
    if (!existing || existing.userId !== userId) throw new NotFoundException("Log introuvable");

    const newCapitalMatin = dto.capitalMatin ?? Number(existing.capitalMatin);
    const newRecettes = dto.recettes ?? Number(existing.recettes);
    const newReappro = dto.reapprovisionnement ?? Number(existing.reapprovisionnement);
    const beneficeNet = newRecettes - newReappro;

    return prisma.dailyShopLog.update({
      where: { id },
      data: {
        capitalMatin: newCapitalMatin,
        recettes: newRecettes,
        reapprovisionnement: newReappro,
        beneficeNet,
        note: dto.note ?? existing.note ?? null,
      },
    });
  }
}

