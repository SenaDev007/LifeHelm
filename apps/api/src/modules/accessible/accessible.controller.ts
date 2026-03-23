import { Body, Controller, Get, Patch, Post, Req, UseGuards, Param } from "@nestjs/common";
import { Request } from "express";
import { JwtAuthGuard } from "../auth/jwt-auth.guard";
import { AccessibleService } from "./accessible.service";
import { CreateShopLogDto } from "./dto/create-shop-log.dto";
import { UpdateShopLogDto } from "./dto/update-shop-log.dto";

@Controller("/accessible")
export class AccessibleController {
  constructor(private readonly accessibleService: AccessibleService) {}

  @UseGuards(JwtAuthGuard)
  @Get("/shop-log/today")
  async shopLogToday(@Req() req: Request) {
    const authUser = (req as unknown as { user?: { id: string } }).user;
    return this.accessibleService.getToday(authUser?.id);
  }

  @UseGuards(JwtAuthGuard)
  @Post("/shop-log")
  async createShopLog(@Req() req: Request, @Body() dto: CreateShopLogDto) {
    const authUser = (req as unknown as { user?: { id: string } }).user;
    return this.accessibleService.createOrUpdate(authUser?.id, dto);
  }

  @UseGuards(JwtAuthGuard)
  @Patch("/shop-log/:id")
  async patchShopLog(@Req() req: Request, @Param("id") id: string, @Body() dto: UpdateShopLogDto) {
    const authUser = (req as unknown as { user?: { id: string } }).user;
    return this.accessibleService.patch(authUser?.id, id, dto);
  }
}

