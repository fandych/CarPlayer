import { SessionControllerAirPlayDiscoveryFlow } from './SessionControllerAirPlayDiscoveryFlow';

const AIRPLAY_CTRL_INVITE_WAIT_MS: number = 4000;
const AIRPLAY_ENDPOINT_RESOLVE_WAIT_MS: number = 3000;

export abstract class SessionControllerAirPlayPrerequisiteFlow extends SessionControllerAirPlayDiscoveryFlow {
  protected abstract clearAirPlayCtrlReannounceTimer(): void;
  protected abstract scheduleAirPlayControlReannounce(generation: number): void;
  protected abstract handleAirPlayTransportDisconnect(generation: number, message: string): void;
  protected abstract scheduleAirPlayStableReset(generation: number): void;
  protected abstract airPlayRetryDelayMs(error: Error): number;
  protected abstract scheduleAirPlayReconnect(reason: string, retryDelayMs?: number): void;

  protected hasSelfContainedAirPlayEndpoint(): boolean {
    const endpoint = this.iap2AirPlayEndpoint;
    return endpoint !== undefined && endpoint.port > 0 &&
      endpoint.addresses.some((address: string): boolean => address.trim().length > 0);
  }
  protected hasAirPlayStartSignal(): boolean {
    return this.inviteReceived || this.airPlayStartSessionReceived ||
      this.mdnsAirPlayService !== undefined || this.airPlayEndpointResolveElapsed;
  }
  protected startAirPlayPrerequisiteWait(): void {
    if (!this.running || !this.vehicleWifiConnected) {
      return;
    }
    if (this.hasSelfContainedAirPlayEndpoint()) {
      this.clearAirPlayWaitTimers();
      void this.connectAirPlay().catch((error: Error): void => this.reportError(error));
      return;
    }
    if (this.inviteReceived || this.airPlayInviteWaitElapsed) {
      this.clearAirPlayInviteWaitTimer();
      this.startAirPlayEndpointResolutionWait();
      return;
    }
    if (this.airPlayInviteWaitTimer >= 0) {
      return;
    }
    this.airPlayInviteWaitTimer = setTimeout((): void => {
      this.airPlayInviteWaitTimer = -1;
      if (!this.running || !this.vehicleWifiConnected || this.hasSelfContainedAirPlayEndpoint()) {
        return;
      }
      this.airPlayInviteWaitElapsed = true;
      this.events.onLog('等待 CarPlay ctrl 邀请达到 4 秒；继续等待 AirPlay mDNS/端点解析');
      this.startAirPlayEndpointResolutionWait();
    }, AIRPLAY_CTRL_INVITE_WAIT_MS);
  }
  protected startAirPlayEndpointResolutionWait(): void {
    if (!this.running || !this.vehicleWifiConnected) {
      return;
    }
    if (this.mdnsAirPlayService || this.hasSelfContainedAirPlayEndpoint()) {
      this.clearAirPlayWaitTimers();
      void this.connectAirPlay().catch((error: Error): void => this.reportError(error));
      return;
    }
    if (this.airPlayEndpointResolveTimer >= 0) {
      return;
    }
    this.airPlayEndpointResolveTimer = setTimeout((): void => {
      this.airPlayEndpointResolveTimer = -1;
      if (!this.running || !this.vehicleWifiConnected || this.mdnsAirPlayService ||
        this.hasSelfContainedAirPlayEndpoint()) {
        return;
      }
      this.airPlayEndpointResolveElapsed = true;
      this.refreshDiscoveredAirPlay();
      this.events.onLog('AirPlay mDNS 端点等待达到 3 秒；尝试已选车机网络的网关回退');
      void this.connectAirPlay().catch((error: Error): void => this.reportError(error));
    }, AIRPLAY_ENDPOINT_RESOLVE_WAIT_MS);
  }
  protected clearAirPlayInviteWaitTimer(): void {
    if (this.airPlayInviteWaitTimer >= 0) {
      clearTimeout(this.airPlayInviteWaitTimer);
      this.airPlayInviteWaitTimer = -1;
    }
  }
  protected clearAirPlayEndpointResolveTimer(): void {
    if (this.airPlayEndpointResolveTimer >= 0) {
      clearTimeout(this.airPlayEndpointResolveTimer);
      this.airPlayEndpointResolveTimer = -1;
    }
  }
  protected clearAirPlayWaitTimers(): void {
    this.clearAirPlayInviteWaitTimer();
    this.clearAirPlayEndpointResolveTimer();
  }
}
