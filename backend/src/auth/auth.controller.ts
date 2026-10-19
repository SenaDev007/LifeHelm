import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import { ThrottleGuard, Throttle } from '../common/throttle.guard';
import { JwtAuthGuard } from '../common/jwt-auth.guard';
import { CurrentUser, AccessTokenPayload } from '../common/current-user.decorator';
import { AuthService } from './auth.service';
import {
  RegisterDto,
  LoginDto,
  RefreshDto,
  LogoutDto,
  ChangePasswordDto,
  ForgotPasswordDto,
  ResetPasswordDto,
  TotpDto,
  VerifyCodeDto,
} from './dto/auth.dto';
import { Request } from 'express';

@Controller('auth')
@UseGuards(ThrottleGuard)
export class AuthController {
  constructor(private auth: AuthService) {}

  private meta(req: Request) {
    return {
      userAgent: req.headers['user-agent'],
      ip: (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() ?? req.socket.remoteAddress,
    };
  }

  @Post('register')
  @Throttle(10, 60_000)
  @HttpCode(201)
  register(@Body() dto: RegisterDto, @Req() req: Request) {
    return this.auth.register(dto, this.meta(req));
  }

  @Post('login')
  @Throttle(15, 60_000)
  @HttpCode(200)
  login(@Body() dto: LoginDto, @Req() req: Request) {
    return this.auth.login(dto, this.meta(req));
  }

  @Post('refresh')
  @Throttle(30, 60_000)
  @HttpCode(200)
  refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto.refreshToken);
  }

  @Post('logout')
  @HttpCode(204)
  logout(@Body() dto: LogoutDto) {
    return this.auth.logout(dto.refreshToken);
  }

  @Post('logout-all')
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  logoutAll(@CurrentUser() user: AccessTokenPayload) {
    return this.auth.logoutAll(user.sub);
  }

  @Get('me')
  @UseGuards(JwtAuthGuard)
  me(@CurrentUser() user: AccessTokenPayload) {
    return this.auth.me(user.sub);
  }

  @Get('sessions')
  @UseGuards(JwtAuthGuard)
  sessions(@CurrentUser() user: AccessTokenPayload) {
    return this.auth.listSessions(user.sub, user.fid);
  }

  @Delete('sessions/:id')
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  revokeSession(@CurrentUser() user: AccessTokenPayload, @Param('id') sessionId: string) {
    return this.auth.revokeSession(user.sub, sessionId);
  }

  @Post('password')
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  changePassword(@CurrentUser() user: AccessTokenPayload, @Body() dto: ChangePasswordDto) {
    return this.auth.changePassword(user.sub, dto.currentPassword, dto.newPassword);
  }

  @Post('password/forgot')
  @Throttle(5, 60_000)
  @HttpCode(202)
  forgot(@Body() dto: ForgotPasswordDto) {
    return this.auth.forgotPassword(dto.identifier);
  }

  @Post('password/reset')
  @Throttle(10, 60_000)
  @HttpCode(204)
  reset(@Body() dto: ResetPasswordDto) {
    return this.auth.resetPassword(dto.resetToken, dto.newPassword);
  }

  @Post('2fa/setup')
  @UseGuards(JwtAuthGuard)
  @HttpCode(200)
  setup2fa(@CurrentUser() user: AccessTokenPayload) {
    return this.auth.setup2fa(user.sub);
  }

  @Post('2fa/enable')
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  enable2fa(@CurrentUser() user: AccessTokenPayload, @Body() dto: TotpDto) {
    return this.auth.enable2fa(user.sub, dto.totpCode);
  }

  @Post('2fa/disable')
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  disable2fa(@CurrentUser() user: AccessTokenPayload, @Body() dto: TotpDto) {
    return this.auth.disable2fa(user.sub, dto.totpCode);
  }

  @Post('verify-email')
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  verifyEmail(@CurrentUser() user: AccessTokenPayload, @Body() dto: VerifyCodeDto) {
    return this.auth.verifyEmail(user.sub, dto.code);
  }

  @Post('verify-phone')
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  verifyPhone(@CurrentUser() user: AccessTokenPayload, @Body() dto: VerifyCodeDto) {
    return this.auth.verifyPhone(user.sub, dto.code);
  }
}
