import { BadRequestException, CanActivate, ExecutionContext, ForbiddenException, Injectable, SetMetadata, createParamDecorator } from "@nestjs/common";
import { Reflector } from "@nestjs/core";
import type { Request } from "express";
import type { UserRole } from "../domain/types";

export type RequestActor = { userId: string; organizationId: string; role: UserRole };
export const ROLES_KEY = "roles";
export const Roles = (...roles: UserRole[]) => SetMetadata(ROLES_KEY, roles);

@Injectable()
export class RequestActorGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<Request & { actor?: RequestActor }>();
    const userId = request.header("x-user-id");
    const organizationId = request.header("x-organization-id");
    const role = request.header("x-role") as UserRole | undefined;
    if (!userId || !organizationId || !role || !["regular_user", "admin"].includes(role)) throw new BadRequestException("Valid development actor headers are required");
    const allowed = this.reflector.getAllAndOverride<UserRole[]>(ROLES_KEY, [context.getHandler(), context.getClass()]);
    if (allowed && !allowed.includes(role)) throw new ForbiddenException("This role cannot perform the requested action");
    request.actor = { userId, organizationId, role };
    return true;
  }
}

export const Actor = createParamDecorator((_data: unknown, context: ExecutionContext): RequestActor => context.switchToHttp().getRequest().actor);
