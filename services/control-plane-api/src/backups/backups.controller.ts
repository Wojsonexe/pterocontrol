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
import { PterodactylBackupDto } from '@pterocontrol/pterodactyl-sdk';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { AuthenticatedUser } from '../auth/guards/jwt-auth.guard';
import { BackupsService } from './backups.service';
import { CreateBackupDto } from './dto/create-backup.dto';
import { RestoreBackupDto } from './dto/restore-backup.dto';

@Controller('servers/:serverId/backups')
export class BackupsController {
  constructor(private readonly backupsService: BackupsService) {}

  @Get()
  list(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
  ): Promise<PterodactylBackupDto[]> {
    return this.backupsService.list(user.tenantId, serverId);
  }

  @Roles('owner', 'admin')
  @Post()
  create(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
    @Body() dto: CreateBackupDto,
  ): Promise<PterodactylBackupDto> {
    return this.backupsService.create(user.tenantId, user.sub, serverId, dto);
  }

  @Get(':backupUuid')
  getOne(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
    @Param('backupUuid') backupUuid: string,
  ): Promise<PterodactylBackupDto> {
    return this.backupsService.getOne(user.tenantId, serverId, backupUuid);
  }

  @Get(':backupUuid/download')
  getDownloadUrl(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
    @Param('backupUuid') backupUuid: string,
  ): Promise<{ url: string }> {
    return this.backupsService.getDownloadUrl(user.tenantId, serverId, backupUuid);
  }

  @Roles('owner', 'admin')
  @Delete(':backupUuid')
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
    @Param('backupUuid') backupUuid: string,
  ): Promise<void> {
    await this.backupsService.remove(user.tenantId, user.sub, serverId, backupUuid);
  }

  @Roles('owner', 'admin')
  @Post(':backupUuid/restore')
  @HttpCode(HttpStatus.ACCEPTED)
  async restore(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
    @Param('backupUuid') backupUuid: string,
    @Body() dto: RestoreBackupDto,
  ): Promise<{ accepted: true }> {
    await this.backupsService.restore(
      user.tenantId,
      user.sub,
      serverId,
      backupUuid,
      dto.truncate ?? false,
    );
    return { accepted: true };
  }

  @Roles('owner', 'admin')
  @Post(':backupUuid/lock')
  toggleLock(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
    @Param('backupUuid') backupUuid: string,
  ): Promise<PterodactylBackupDto> {
    return this.backupsService.toggleLock(user.tenantId, user.sub, serverId, backupUuid);
  }
}
