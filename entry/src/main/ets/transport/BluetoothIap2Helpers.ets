export function isCarPlayAdapterName(name: string): boolean {
  const normalized = name.toLowerCase();
  return ['smart box', 'car link', 'carlinkit', 'auto kit', 'cpc200']
    .some((token: string): boolean => normalized.includes(token));
}

export function formatBluetoothErrorMessage(error: Error | string): string {
  return error instanceof Error ? error.message : String(error);
}

export function closeHeldBluetoothClients(
  clientIds: number[],
  closeSocket: (clientId: number) => void,
  onFailure: (message: string) => void
): void {
  for (const clientId of clientIds) {
    try {
      closeSocket(clientId);
    } catch (error) {
      onFailure(`Bluetooth held client cleanup failed: ${formatBluetoothErrorMessage(error)}`);
    }
  }
  clientIds.length = 0;
}
