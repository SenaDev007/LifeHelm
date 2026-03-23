import { Injectable } from "@nestjs/common";
import { PassportStrategy } from "@nestjs/passport";
import { ExtractJwt, Strategy } from "passport-jwt";
import { ConfigService } from "@nestjs/config";
import { prisma } from "@lifehelm/database";

type JwtPayload = {
  sub: string; // user id
  plan: "FREE" | "PRO" | "FAMILY";
  uiMode: "STANDARD" | "ACCESSIBLE";
};

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(config: ConfigService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      secretOrKey: config.get<string>("JWT_ACCESS_SECRET", "change-me-access-secret-min-32-chars"),
    });
  }

  async validate(payload: JwtPayload) {
    const user = await prisma.user.findUnique({ where: { id: payload.sub } });
    if (!user) return null;
    return { id: user.id, plan: user.plan, uiMode: user.uiMode };
  }
}

