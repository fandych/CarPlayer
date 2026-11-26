import { AirPlayEventRequest } from '../AirPlayEventChannel';
import { AirPlayRtspResponse } from '../AirPlayRtspClient';
import { BinaryPlist, PlistNode } from '../BinaryPlist';
import {
  extractCarPlayTouchReport,
  scaleCarPlayTouchReport
} from '../CarPlayTouchReport';
import {
  isForceKeyFrameCommand,
  parseIapSendMessagePayload
} from './AirPlayMediaHelpers';
import { AirPlayMediaSessionVideoTransport } from './AirPlayMediaSessionVideoTransport';

export abstract class AirPlayMediaSessionEventTransport extends AirPlayMediaSessionVideoTransport {
  setNightModeHandler(handler: ((night: boolean) => void) | undefined): void {
    this.nightModeHandler = handler;
    handler?.(this.nightMode);
  }

  protected handleChangeModes(request: AirPlayEventRequest, params: PlistNode | undefined): void {
    this.modes = this.applyModeChanges(this.modes, params);
    request.responseBody = BinaryPlist.encode(PlistNode.dictionary(new Map<string, PlistNode>([
      ['status', PlistNode.integer(0)],
      ['params', this.createModesDictionary(this.modes)]
    ])));
    this.log(`AirPlay changeModes granted: screen=${this.modes.screenEntity}, audio=${this.modes.audioEntity}, ` +
      `speech=${this.modes.speechMode}, call=${this.modes.phoneCallEntity}, nav=${this.modes.turnByTurnEntity}`);
    const payload = this.createModesChangedPayload(this.modes);
    void this.client.request('POST', '/command', payload, { contentType: 'application/x-apple-binary-plist' })
      .then((response: AirPlayRtspResponse): void => {
        if (response.statusCode !== 200) {
          this.log(`AirPlay modesChanged rejected: ${response.statusLine}`);
        }
      })
      .catch((error: Error): void => this.log(`AirPlay modesChanged failed: ${error.message}`));
  }

  protected handleEventRequest(request: AirPlayEventRequest): boolean {
    let commandSummary = '';
    if (request.body.length > 0) {
      try {
        const command = BinaryPlist.decode(request.body);
        if (command.kind === 'dictionary') {
          commandSummary = ` fields=${Array.from(command.dictionaryValue.keys()).join(',')}`;
          const touchReport = extractCarPlayTouchReport(command, this.touchHid?.uuid);
          if (request.method === 'POST' && request.target === '/command' && touchReport) {
            const device = this.touchHid;
            this.touchReportHandler?.(device ?
              scaleCarPlayTouchReport(touchReport, device, this.videoWidth, this.videoHeight) : touchReport);
          }
          const type = command.get('type');
          if (request.method === 'POST' && request.target === '/command' &&
            type?.kind === 'string' && type.stringValue === 'changeModes') {
            this.handleChangeModes(request, command.get('params'));
          }
          if (request.method === 'POST' && request.target === '/command' &&
            type?.kind === 'string' && type.stringValue === 'iAPSendMessage') {
            const bytes = parseIapSendMessagePayload(command);
            const session = this.virtualIap2Session;
            if (session && bytes) {
              void session.receive(bytes).catch((error: Error): void => {
                if (this.virtualIap2Session !== session) {
                  return;
                }
                this.log(`MIB3 virtual iAP2 receive failed: ${error.message}`);
                session.cancel();
                this.virtualIap2Session = undefined;
              });
            }
          }
          if (request.method === 'POST' && request.target === '/command' &&
            type?.kind === 'string' && type.stringValue === 'setNightMode') {
            const night = command.get('params')?.get('nightMode');
            if (night?.kind !== 'boolean') {
              throw new Error('setNightMode requires params.nightMode Boolean');
            }
            this.nightMode = night.boolValue;
            this.nightModeHandler?.(this.nightMode);
          }
          if (request.method === 'POST' && request.target === '/command' &&
            type?.kind === 'string' && type.stringValue === 'hidSendReport') {
            return true;
          }
          if (request.method === 'POST' && request.target === '/command' && isForceKeyFrameCommand(command)) {
            this.log('AirPlay receiver requested an immediate H.264 key frame');
            this.forceKeyFrameHandler?.();
          }
        }
      } catch (error) {
        commandSummary = ` plistError=${error instanceof Error ? error.message : String(error)}`;
      }
    }
    this.log(
      `AirPlay event ${request.method} ${request.target} cseq=${request.cseq} body=${request.body.length}B${commandSummary}`
    );
    return false;
  }

}
