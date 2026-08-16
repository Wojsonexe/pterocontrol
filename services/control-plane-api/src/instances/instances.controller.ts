import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
} from '@nestjs/common';
import { PterodactylInstance } from '@prisma/client';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { AuthenticatedUser } from '../auth/guards/jwt-auth.guard';
import { CreateInstanceDto } from './dto/create-instance.dto';
import { InstancesService } from './instances.service';

@Controller('instances')
export class InstancesController {
  constructor(private readonly instancesService: InstancesService) {}

  @Roles('owner', 'admin')
  @Post()
  create(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateInstanceDto,
  ): Promise<PterodactylInstance> {
    return this.instancesService.create(user.tenantId, dto);
  }

  @Get()
  findAll(@CurrentUser() user: AuthenticatedUser): Promise<PterodactylInstance[]> {
    return this.instancesService.findAllForTenant(user.tenantId);
  }

  @Get(':id')
  findOne(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
  ): Promise<PterodactylInstance> {
    return this.instancesService.findOneForTenant(user.tenantId, id);
  }

  @Roles('owner', 'admin')
  @Post(':id/sync')
  @HttpCode(HttpStatus.OK)
  resync(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
  ): Promise<PterodactylInstance> {
    return this.instancesService.resync(user.tenantId, id);
  }

  @Roles('owner', 'admin')
  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
  ): Promise<void> {
    await this.instancesService.remove(user.tenantId, id);
  }
}
