import { AirPlayEventChannel, AirPlayEventRequest } from '../AirPlayEventChannel';
import { AirPlayMediaSessionTransport } from './AirPlayMediaSessionTransport';
import { AirPlayMediaSessionPayloads } from './AirPlayMediaSessionPayloads';
import { TouchHidDevice } from '../CarPlayTouchReport';

export abstract class AirPlayMediaSessionStartHelpers extends AirPlayMediaSessionTransport {
  protected async setupEventChannel(
    eventPort: number,
    sharedSecret: Uint8Array | undefined,
    mib3VirtualLink: boolean,
    paired: boolean,
    touchHid: TouchHidDevice | undefined
  ): Promise<void> {
    if (eventPort > 0) {
      const eventChannel = new AirPlayEventChannel(
        (message: string): void => this.log(message),
        (request: AirPlayEventRequest): boolean => this.handleEventRequest(request),
        this.wifiNetworkLease
      );
      this.eventChannel = eventChannel;
      try {
        await eventChannel.connect(this.receiverHost, eventPort, sharedSecret);
      } catch (error) {
        this.log(`AirPlay event channel unavailable: ${error instanceof Error ? error.message : String(error)}`);
        this.eventChannel = undefined;
        await eventChannel.close();
        if (mib3VirtualLink && paired) {
          throw new Error(
            `MIB3 virtual iAP2 event channel unavailable: ${error instanceof Error ? error.message : String(error)}`
          );
        }
      }
    } else {
      this.log('Receiver did not provide an event port before resource claim');
      if (mib3VirtualLink && paired) {
        throw new Error('MIB3 virtual iAP2 requires an AirPlay event channel');
      }
    }
    const eventChannel = this.eventChannel;
    if (touchHid && eventChannel) {
      try {
        await eventChannel.sendCommand(AirPlayMediaSessionPayloads.buildHidSetInputModePayload(touchHid.uuid));
        this.ensureRunning();
        this.log(`AirPlay touch HID input mode armed: uuid=${touchHid.uuid}, mode=0`);
      } catch (error) {
        this.ensureRunning();
        this.log(`AirPlay touch HID input mode unavailable: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
  }
}
