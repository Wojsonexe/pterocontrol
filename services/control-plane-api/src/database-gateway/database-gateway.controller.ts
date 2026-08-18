import { Body, Controller, Param, Post } from '@nestjs/common';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { AuthenticatedUser } from '../auth/guards/jwt-auth.guard';
import { DatabaseGatewayService, QueryResult } from './database-gateway.service';
import { ExecuteQueryDto } from './dto/execute-query.dto';

@Controller('servers/:serverId/databases/:databaseId/query')
export class DatabaseGatewayController {
  constructor(private readonly gatewayService: DatabaseGatewayService) {}

  @Roles('owner', 'admin')
  @Post()
  execute(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
    @Param('databaseId') databaseId: string,
    @Body() dto: ExecuteQueryDto,
  ): Promise<QueryResult> {
    return this.gatewayService.execute(user.tenantId, user.sub, serverId, databaseId, dto.sql);
  }
}
