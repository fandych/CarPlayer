interface NetworkErrorWithCode extends Error {
  code?: number | string;
}

interface NetworkErrorDescription {
  code?: number | string;
  message?: string;
}

export function formatNetworkError(error: Error | Object): string {
  if (error instanceof Error) {
    const details = error as NetworkErrorWithCode;
    return details.code === undefined ? details.message : `${details.message} (code=${details.code})`;
  }
  const details = error as NetworkErrorDescription;
  const parts: string[] = [];
  if (details.code !== undefined) {
    parts.push(`code=${details.code}`);
  }
  if (details.message) {
    parts.push(details.message);
  }
  if (parts.length > 0) {
    return parts.join(': ');
  }
  try {
    return JSON.stringify(error) || String(error);
  } catch (_serializationError) {
    return String(error);
  }
}
