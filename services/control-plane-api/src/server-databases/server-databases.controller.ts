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
import { PterodactylServerDatabaseDto } from '@pterocontrol/pterodactyl-sdk';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { AuthenticatedUser } from '../auth/guards/jwt-auth.guard';
import { CreateServerDatabaseDto } from './dto/create-server-database.dto';
import { ServerDatabasesService } from './server-databases.service';

@Controller('servers/:serverId/databases')
export class ServerDatabasesController {
  constructor(private readonly serverDatabasesService: ServerDatabasesService) {}

  @Get()
  list(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
  ): Promise<PterodactylServerDatabaseDto[]> {
    return this.serverDatabasesService.list(user.tenantId, serverId);
  }

  @Roles('owner', 'admin')
  @Post()
  create(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
    @Body() dto: CreateServerDatabaseDto,
  ): Promise<PterodactylServerDatabaseDto> {
    return this.serverDatabasesService.create(user.tenantId, user.sub, serverId, dto);
  }

  @Roles('owner', 'admin')
  @Post(':databaseId/rotate-password')
  rotatePassword(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
    @Param('databaseId') databaseId: string,
  ): Promise<PterodactylServerDatabaseDto> {
    return this.serverDatabasesService.rotatePassword(
      user.tenantId,
      user.sub,
      serverId,
      databaseId,
    );
  }

  @Roles('owner', 'admin')
  @Delete(':databaseId')
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
    @Param('databaseId') databaseId: string,
  ): Promise<void> {
    await this.serverDatabasesService.remove(user.tenantId, user.sub, serverId, databaseId);
  }
}
