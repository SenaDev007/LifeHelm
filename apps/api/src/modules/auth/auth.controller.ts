import {
  Body,
  Controller,
  Delete,
  Get,
  Post,
  Req,
  Res,
  UseGuards,
} from "@nestjs/common";
import { Response, Request } from "express";
import { AuthService } from "./auth.service";
import { RegisterDto } from "./dto/register.dto";
import { LoginDto } from "./dto/login.dto";
import { JwtAuthGuard } from "./jwt-auth.guard";

@Controller("/auth")
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post("/register")
  async register(
    @Body() dto: RegisterDto,
    @Res({ passthrough: true }) res: Response
  ) {
    return this.authService.register(dto, res);
  }

  @Post("/login")
  async login(@Body() dto: LoginDto, @Res({ passthrough: true }) res: Response) {
    return this.authService.login(dto, res);
  }

  @Post("/refresh")
  async refresh(@Req() req: Request, @Res({ passthrough: true }) res: Response) {
    return this.authService.refresh(req, res);
  }

  @Post("/logout")
  @UseGuards(JwtAuthGuard)
  async logout(@Req() req: Request, @Res({ passthrough: true }) res: Response) {
    return this.authService.logout(req, res);
  }

  @Get("/sessions")
  @UseGuards(JwtAuthGuard)
  async sessions(@Req() req: Request) {
    return this.authService.listSessions(req);
  }

  @Delete("/sessions/:id")
  @UseGuards(JwtAuthGuard)
  async revokeSession(@Req() req: Request, @Res({ passthrough: true }) res: Response) {
    // MVP: endpoint non câblé côté front pour l'instant
    return res.json({ success: true });
  }
}

