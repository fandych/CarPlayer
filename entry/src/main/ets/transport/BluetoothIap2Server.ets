import bluetoothSocket from '@ohos.bluetooth.socket';
import { toArrayBuffer } from '../protocol/Iap2Codec';
import {
  closeHeldBluetoothClients,
  isCarPlayAdapterName
} from './BluetoothIap2Helpers';
import { BluetoothIap2AcceptRetry } from './BluetoothIap2AcceptRetry';
export { isCarPlayAdapterName } from './BluetoothIap2Helpers';

export type ByteHandler = (bytes: Uint8Array) => void;

export class BluetoothIap2Server {
  private serverId: number = -1;
  private clientId: number = -1;
  private readHandler?: (data: ArrayBuffer) => void;
  private onClientData?: ByteHandler;
  private onClientConnected?: () => void;
  private onClientDisconnected?: () => void;
  private onFailure?: (message: string) => void;
  private adapterMode: boolean = false;
  private adapterHandoffCompleted: boolean = false;
  private readonly heldClientIds: number[] = [];
  private readonly acceptRetry: BluetoothIap2AcceptRetry = new BluetoothIap2AcceptRetry();
  private connectionMonitorTimer: number = -1;
  private connectionGeneration: number = 0;
  private connectPending: boolean = false;

  async start(
    onConnected: () => void,
    onData: ByteHandler,
    onError: (message: string) => void,
    adapterMode: boolean = false,
    onDisconnected: () => void = (): void => {}
  ): Promise<void> {
    if (this.serverId >= 0) {
      throw new Error('Bluetooth listener is already running');
    }
    this.adapterMode = adapterMode;
    this.adapterHandoffCompleted = false;
    this.acceptRetry.cancel();
    this.onClientConnected = onConnected;
    this.onClientData = onData;
    this.onClientDisconnected = onDisconnected;
    this.onFailure = onError;
    await new Promise<void>((resolve, reject) => {
      const options: bluetoothSocket.SppOptions = {
        uuid: '00000000-deca-fade-deca-deafdecacafe',
        secure: true,
        type: bluetoothSocket.SppType.SPP_RFCOMM
      };
      try {
        bluetoothSocket.sppListen(adapterMode ? 'Wireless iAP' : 'iAP2', options, (error, serverId) => {
          if (error) {
            reject(new Error(`Bluetooth RFCOMM listen failed (${error.code}): ${error.message}`));
            return;
          }
          this.serverId = serverId;
          this.acceptNext();
          resolve();
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        reject(new Error(`Bluetooth RFCOMM listen failed: ${message}`));
      }
    });
  }

  async send(bytes: Uint8Array): Promise<void> {
    if (this.clientId < 0) {
      throw new Error('No Bluetooth accessory is connected');
    }
    try {
      await bluetoothSocket.sppWriteAsync(this.clientId, toArrayBuffer(bytes));
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      throw new Error(`Bluetooth RFCOMM write failed: ${message}`);
    }
  }

  get isClientConnected(): boolean {
    return this.clientId >= 0;
  }

  async connectToDevice(
    deviceId: string,
    onAttemptFailure: (message: string) => void = (_message: string): void => {}
  ): Promise<boolean> {
    if (this.serverId < 0 || this.clientId >= 0 || this.connectPending) {
      return false;
    }
    const generation = ++this.connectionGeneration;
    this.connectPending = true;
    return await new Promise<boolean>((resolve): void => {
      const options: bluetoothSocket.SppOptions = {
        uuid: '00000000-deca-fade-deca-deafdecacaff',
        secure: true,
        type: bluetoothSocket.SppType.SPP_RFCOMM
      };
      try {
        bluetoothSocket.sppConnect(deviceId, options, (error, clientId): void => {
          if (generation !== this.connectionGeneration || this.serverId < 0) {
            if (!error) {
              this.closeSocket(clientId, 'stale outgoing Bluetooth socket');
            }
            resolve(false);
            return;
          }
          this.connectPending = false;
          if (error) {
            onAttemptFailure(`Bluetooth RFCOMM connect failed (${error.code}): ${error.message}`);
            resolve(false);
            return;
          }
          if (this.clientId >= 0) {
            this.closeSocket(clientId, 'superseded outgoing Bluetooth socket');
            resolve(false);
            return;
          }
          try {
            this.attachClient(clientId);
            resolve(true);
          } catch (connectError) {
            onAttemptFailure(`Bluetooth outgoing client setup failed: ${this.errorMessage(connectError)}`);
            if (this.clientId === clientId) {
              this.closeClient();
            } else {
              this.closeSocket(clientId, 'failed outgoing Bluetooth client setup');
            }
            resolve(false);
          }
        });
      } catch (error) {
        this.connectPending = false;
        onAttemptFailure(`Bluetooth RFCOMM connect failed: ${this.errorMessage(error)}`);
        resolve(false);
      }
    });
  }

  stop(): void {
    this.connectionGeneration++;
    this.connectPending = false;
    this.acceptRetry.cancel();
    this.disconnectClient();
    this.closeHeldClients();
    if (this.serverId >= 0) {
      try {
        bluetoothSocket.sppCloseServerSocket(this.serverId);
      } catch (error) {
        this.onFailure?.(`Bluetooth server socket cleanup failed: ${this.errorMessage(error)}`);
      }
      this.serverId = -1;
    }
    this.readHandler = undefined;
    this.onClientData = undefined;
    this.onClientConnected = undefined;
    this.onClientDisconnected = undefined;
    this.onFailure = undefined;
    this.adapterMode = false;
    this.adapterHandoffCompleted = false;
  }

  setAdapterHandoffCompleted(completed: boolean): void {
    if (!this.adapterMode) {
      return;
    }
    this.adapterHandoffCompleted = completed;
    if (!completed) this.closeHeldClients();
  }

  disconnectClient(): void {
    this.connectionGeneration++;
    this.connectPending = false;
    this.closeClient();
  }

  private acceptNext(): void {
    if (this.serverId < 0) {
      return;
    }
    try {
      bluetoothSocket.sppAccept(this.serverId, (error, clientId) => {
        if (error) {
          if (this.serverId >= 0) {
            this.reportAcceptFailure(`Bluetooth accept failed (${error.code}): ${error.message}`);
            this.scheduleAcceptRetry();
          }
          return;
        }
        this.acceptRetry.markAccepted();
        if (this.adapterMode && this.adapterHandoffCompleted && this.clientId >= 0) {
          this.heldClientIds.push(clientId);
          this.acceptNext();
          return;
        }
        try {
          this.connectionGeneration++;
          this.connectPending = false;
          this.closeActiveClient(true);
          this.attachClient(clientId);
          this.acceptNext();
        } catch (acceptError) {
          this.reportAcceptFailure(`Bluetooth client setup failed: ${this.errorMessage(acceptError)}`);
          if (this.clientId === clientId) {
            this.clientId = -1;
            this.readHandler = undefined;
          }
          try {
            bluetoothSocket.sppCloseClientSocket(clientId);
          } catch (closeError) {
            this.onFailure?.(`Bluetooth client cleanup failed: ${this.errorMessage(closeError)}`);
          }
          this.scheduleAcceptRetry();
        }
      });
    } catch (error) {
      this.reportAcceptFailure(`Bluetooth accept failed: ${this.errorMessage(error)}`);
      this.scheduleAcceptRetry();
    }
  }

  private closeClient(): void { this.closeActiveClient(false); }

  private scheduleAcceptRetry(): void {
    this.acceptRetry.schedule((): boolean => this.serverId >= 0, (): void => this.acceptNext());
  }

  private reportAcceptFailure(message: string): void {
    this.acceptRetry.report(message, this.onFailure);
  }

  private closeActiveClient(notify: boolean): void {
    if (this.clientId < 0) {
      return;
    }
    const clientId = this.clientId;
    if (this.connectionMonitorTimer >= 0) {
      clearInterval(this.connectionMonitorTimer);
      this.connectionMonitorTimer = -1;
    }
    if (this.readHandler) {
      try {
        bluetoothSocket.off('sppRead', clientId, this.readHandler);
      } catch (error) {
        this.onFailure?.(`Bluetooth read listener cleanup failed: ${this.errorMessage(error)}`);
      }
    }
    try {
      bluetoothSocket.sppCloseClientSocket(clientId);
    } catch (error) {
      this.onFailure?.(`Bluetooth client socket cleanup failed: ${this.errorMessage(error)}`);
    }
    this.clientId = -1;
    this.readHandler = undefined;
    if (notify) {
      this.onClientDisconnected?.();
    }
  }

  private attachClient(clientId: number): void {
    this.clientId = clientId;
    this.readHandler = (data: ArrayBuffer): void => {
      if (this.clientId === clientId) {
        this.onClientData?.(new Uint8Array(data));
      }
    };
    bluetoothSocket.on('sppRead', clientId, this.readHandler);
    this.onClientConnected?.();
    this.connectionMonitorTimer = setInterval((): void => {
      if (this.clientId !== clientId) {
        return;
      }
      try {
        if (!bluetoothSocket.isConnected(clientId)) {
          this.closeActiveClient(true);
        }
      } catch (error) {
        this.reportAcceptFailure(`Bluetooth connection state check failed: ${this.errorMessage(error)}`);
      }
    }, 1000);
  }

  private closeSocket(clientId: number, reason: string): void {
    try {
      bluetoothSocket.sppCloseClientSocket(clientId);
    } catch (error) {
      this.onFailure?.(`Bluetooth ${reason} cleanup failed: ${this.errorMessage(error)}`);
    }
  }

  private closeHeldClients(): void {
    closeHeldBluetoothClients(this.heldClientIds, (clientId: number): void => {
      bluetoothSocket.sppCloseClientSocket(clientId);
    }, (message: string): void => this.onFailure?.(message));
  }

  private errorMessage(error: Error | string): string { return error instanceof Error ? error.message : String(error); }
}
