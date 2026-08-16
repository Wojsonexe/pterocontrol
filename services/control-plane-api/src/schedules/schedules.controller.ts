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
import { PterodactylScheduleDto, PterodactylScheduleTaskDto } from '@pterocontrol/pterodactyl-sdk';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { AuthenticatedUser } from '../auth/guards/jwt-auth.guard';
import { CreateScheduleTaskDto } from './dto/create-schedule-task.dto';
import { CreateScheduleDto } from './dto/create-schedule.dto';
import { SchedulesService } from './schedules.service';

@Controller('servers/:serverId/schedules')
export class SchedulesController {
  constructor(private readonly schedulesService: SchedulesService) {}

  @Get()
  list(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
  ): Promise<PterodactylScheduleDto[]> {
    return this.schedulesService.list(user.tenantId, serverId);
  }

  @Roles('owner', 'admin')
  @Post()
  create(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
    @Body() dto: CreateScheduleDto,
  ): Promise<PterodactylScheduleDto> {
    return this.schedulesService.create(user.tenantId, user.sub, serverId, dto);
  }

  @Get(':scheduleId')
  getOne(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
    @Param('scheduleId', ParseIntPipe) scheduleId: number,
  ): Promise<PterodactylScheduleDto> {
    return this.schedulesService.getOne(user.tenantId, serverId, scheduleId);
  }

  @Roles('owner', 'admin')
  @Delete(':scheduleId')
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
    @Param('scheduleId', ParseIntPipe) scheduleId: number,
  ): Promise<void> {
    await this.schedulesService.remove(user.tenantId, user.sub, serverId, scheduleId);
  }

  @Roles('owner', 'admin')
  @Post(':scheduleId/tasks')
  createTask(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
    @Param('scheduleId', ParseIntPipe) scheduleId: number,
    @Body() dto: CreateScheduleTaskDto,
  ): Promise<PterodactylScheduleTaskDto> {
    return this.schedulesService.createTask(user.tenantId, user.sub, serverId, scheduleId, dto);
  }

  @Roles('owner', 'admin')
  @Delete(':scheduleId/tasks/:taskId')
  @HttpCode(HttpStatus.NO_CONTENT)
  async removeTask(
    @CurrentUser() user: AuthenticatedUser,
    @Param('serverId') serverId: string,
    @Param('scheduleId', ParseIntPipe) scheduleId: number,
    @Param('taskId', ParseIntPipe) taskId: number,
  ): Promise<void> {
    await this.schedulesService.removeTask(user.tenantId, user.sub, serverId, scheduleId, taskId);
  }
}
