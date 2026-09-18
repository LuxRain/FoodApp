import { Module } from "@nestjs/common";
import { APP_GUARD } from "@nestjs/core";
import { RequestActorGuard } from "./auth/request-context";
import { DashboardService } from "./dashboard/dashboard.service";
import { DatabaseService } from "./database/database.service";
import { IntakeController } from "./intake/intake.controller";
import { IntakeService } from "./intake/intake.service";
import { ProductLookupService } from "./product/product-lookup.service";

@Module({
  controllers: [IntakeController],
  providers: [DatabaseService, IntakeService, DashboardService, ProductLookupService, RequestActorGuard, { provide: APP_GUARD, useExisting: RequestActorGuard }],
})
export class AppModule {}
