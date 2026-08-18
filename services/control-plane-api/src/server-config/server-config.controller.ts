import { Body, Controller, Get, Param, Put } from '@nestjs/common';
import { PterodactylStartupVariableDto } from '@pterocontrol/pterodactyl-sdk';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { AuthenticatedUser } from '../auth/guards/jwt-auth.guard';
import { UpdateStartupVariableDto } from './dto/update-startup-variable.dto';
import { ServerConfigService } from './server-config.service';

@Controller('servers/:serverId/startup')
export class ServerConfigController {
  constructor(private readonly serverConfigService: ServerConfigService) {}

  @Get()
  getVariables(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
  ): Promise<PterodactylStartupVariableDto[]> {
    return this.serverConfigService.getStartupVariables(user.tenantId, serverId);
  }

  @Roles('owner', 'admin')
  @Put('variable')
  updateVariable(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
    @Body() dto: UpdateStartupVariableDto,
  ): Promise<PterodactylStartupVariableDto> {
    return this.serverConfigService.updateStartupVariable(
      user.tenantId,
      user.sub,
      serverId,
      dto,
    );
  }
}
