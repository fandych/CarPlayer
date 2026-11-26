interface WifiApiErrorDetails {
  code?: number;
  message?: string;
}

export function formatWifiApiError(error: Error | Object): string {
  if (error instanceof Error) {
    return error.message;
  }
  const details = error as WifiApiErrorDetails;
  const parts: string[] = [];
  if (details.code !== undefined) {
    parts.push(`code=${details.code}`);
  }
  if (details.message) {
    parts.push(details.message);
  }
  return parts.length > 0 ? parts.join(': ') : JSON.stringify(error) || String(error);
}
