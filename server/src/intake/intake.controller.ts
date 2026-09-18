import { Body, Controller, Get, Headers, Param, Post, Query, UseGuards } from "@nestjs/common";
import { Actor, RequestActorGuard, Roles, type RequestActor } from "../auth/request-context";
import { DashboardService } from "../dashboard/dashboard.service";
import { ProductLookupService } from "../product/product-lookup.service";
import { AdminDecisionDto, CreateItemDto, CreateSessionDto, ProductLookupDto, SubmitItemDto } from "./dto";
import { IntakeService } from "./intake.service";

@Controller("v1")
@UseGuards(RequestActorGuard)
export class IntakeController {
  constructor(private readonly intake: IntakeService, private readonly dashboardService: DashboardService, private readonly productLookup: ProductLookupService) {}

  @Post("product-lookups")
  lookupProduct(@Actor() actor: RequestActor, @Body() body: ProductLookupDto) { return this.productLookup.lookup(actor, body.rawCode, body.scheme); }

  @Post("intake-sessions")
  createSession(@Actor() actor: RequestActor, @Body() body: CreateSessionDto) { return this.intake.createSession(actor, body); }

  @Post("intake-sessions/:sessionId/items")
  createItem(@Actor() actor: RequestActor, @Param("sessionId") sessionId: string, @Body() body: CreateItemDto) { return this.intake.createItem(actor, sessionId, body); }

  @Post("intake-items/:itemId/submit")
  submit(@Actor() actor: RequestActor, @Param("itemId") itemId: string, @Body() body: SubmitItemDto, @Headers("idempotency-key") key: string) { return this.intake.submitItem(actor, itemId, body, key); }

  @Get("donation-items")
  dashboard(@Actor() actor: RequestActor, @Query("search") search?: string, @Query("limit") limit?: string) { return this.dashboardService.list(actor, search, Number(limit || 50)); }

  @Get("admin/review-queue")
  @Roles("admin")
  reviewQueue(@Actor() actor: RequestActor) { return this.intake.reviewQueue(actor); }

  @Post("admin/intake-items/:itemId/decision")
  @Roles("admin")
  decide(@Actor() actor: RequestActor, @Param("itemId") itemId: string, @Body() body: AdminDecisionDto, @Headers("idempotency-key") key: string) { return this.intake.decide(actor, itemId, body, key); }
}
