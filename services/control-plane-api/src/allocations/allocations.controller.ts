import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseIntPipe,
  Post,
} from '@nestjs/common';
import { PterodactylAllocationDto } from '@pterocontrol/pterodactyl-sdk';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { AuthenticatedUser } from '../auth/guards/jwt-auth.guard';
import { AllocationsService } from './allocations.service';
import { SetAllocationNotesDto } from './dto/set-allocation-notes.dto';

@Controller('servers/:serverId/allocations')
export class AllocationsController {
  constructor(private readonly allocationsService: AllocationsService) {}

  @Get()
  list(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
  ): Promise<PterodactylAllocationDto[]> {
    return this.allocationsService.list(user.tenantId, serverId);
  }

  @Roles('owner', 'admin')
  @Post()
  create(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
  ): Promise<PterodactylAllocationDto> {
    return this.allocationsService.create(user.tenantId, user.sub, serverId);
  }

  @Roles('owner', 'admin')
  @Post(':allocationId/notes')
  setNotes(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
    @Param('allocationId', ParseIntPipe) allocationId: number,
    @Body() dto: SetAllocationNotesDto,
  ): Promise<PterodactylAllocationDto> {
    return this.allocationsService.setNotes(
      user.tenantId,
      user.sub,
      serverId,
      allocationId,
      dto.notes,
    );
  }

  @Roles('owner', 'admin')
  @Post(':allocationId/primary')
  @HttpCode(HttpStatus.NO_CONTENT)
  async setPrimary(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
    @Param('allocationId', ParseIntPipe) allocationId: number,
  ): Promise<void> {
    await this.allocationsService.setPrimary(user.tenantId, user.sub, serverId, allocationId);
  }

  @Roles('owner', 'admin')
  @Delete(':allocationId')
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
    @Param('allocationId', ParseIntPipe) allocationId: number,
  ): Promise<void> {
    await this.allocationsService.remove(user.tenantId, user.sub, serverId, allocationId);
  }
}
