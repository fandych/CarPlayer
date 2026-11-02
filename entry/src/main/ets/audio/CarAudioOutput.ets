import audio from '@ohos.multimedia.audio';

export function scalePlaybackPcm(source: Uint8Array, volume: number): Uint8Array {
  const gain = Math.max(0, Math.min(100, Number.isFinite(volume) ? volume : 100)) / 100;
  if (gain === 1) {
    return source;
  }
  const output = source.slice();
  const view = new DataView(output.buffer, output.byteOffset, output.byteLength);
  for (let offset = 0; offset + 1 < output.length; offset += 2) {
    view.setInt16(offset, Math.round(view.getInt16(offset, true) * gain), true);
  }
  return output;
}

export class CarAudioOutput {
  private static readonly owners: Set<CarAudioOutput> = new Set();
  private static serial: Promise<void> = Promise.resolve();
  private static volumeManager?: audio.AudioVolumeManager;
  private static readonly volumeHandler = (event: audio.StreamVolumeEvent): void => {
    if (CarAudioOutput.owners.size === 0 || !Number.isFinite(event.volume)) {
      return;
    }
    const manager = CarAudioOutput.volumeManager;
    if (manager) {
      const maximum = manager.getMaxVolumeByStream(audio.StreamUsage.STREAM_USAGE_MEDIA);
      AppStorage.setOrCreate('carplayRemoteVolume', Math.round(100 * event.volume / Math.max(1, maximum)));
    }
  };

  private static enqueue(action: () => Promise<void>): Promise<void> {
    const operation = CarAudioOutput.serial.then(action);
    CarAudioOutput.serial = operation.catch((): void => {});
    return operation;
  }

  async start(): Promise<void> {
    await CarAudioOutput.enqueue(async (): Promise<void> => {
      if (CarAudioOutput.owners.has(this)) {
        return;
      }
      if (CarAudioOutput.owners.size === 0) {
        const manager = audio.getAudioManager();
        const volumeManager = manager.getVolumeManager();
        try {
          const maximum = volumeManager.getMaxVolumeByStream(audio.StreamUsage.STREAM_USAGE_MEDIA);
          const volume = volumeManager.getVolumeByStream(audio.StreamUsage.STREAM_USAGE_MEDIA);
          AppStorage.setOrCreate('carplayRemoteVolume', Math.round(100 * volume / Math.max(1, maximum)));
        } catch (_error) {
        }
        try {
          volumeManager.on('streamVolumeChange', audio.StreamUsage.STREAM_USAGE_MEDIA,
            CarAudioOutput.volumeHandler);
          CarAudioOutput.volumeManager = volumeManager;
        } catch (_error) {
          CarAudioOutput.volumeManager = undefined;
        }
      }
      CarAudioOutput.owners.add(this);
    });
  }

  async stop(): Promise<void> {
    await CarAudioOutput.enqueue(async (): Promise<void> => {
      if (!CarAudioOutput.owners.delete(this) || CarAudioOutput.owners.size > 0) {
        return;
      }
      const volumeManager = CarAudioOutput.volumeManager;
      CarAudioOutput.volumeManager = undefined;
      if (volumeManager) {
        volumeManager.off('streamVolumeChange', CarAudioOutput.volumeHandler);
      }
    });
  }
}