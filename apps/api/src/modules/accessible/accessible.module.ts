import { Module } from "@nestjs/common";
import { AccessibleController } from "./accessible.controller";
import { AccessibleService } from "./accessible.service";

@Module({
  imports: [],
  controllers: [AccessibleController],
  providers: [AccessibleService],
})
export class AccessibleModule {}

