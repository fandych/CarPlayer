export function formatLocalTimestamp(date: Date = new Date()): string {
  const offsetMinutes = -date.getTimezoneOffset();
  const offsetMagnitude = Math.abs(offsetMinutes);
  const offsetSign = offsetMinutes >= 0 ? '+' : '-';
  const pad = (value: number, length: number = 2): string => value.toString().padStart(length, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T` +
    `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}.` +
    `${pad(date.getMilliseconds(), 3)}${offsetSign}${pad(Math.floor(offsetMagnitude / 60))}:` +
    `${pad(offsetMagnitude % 60)}`;
}

export function formatLocalDateKey(date: Date = new Date()): string {
  const pad = (value: number): string => value.toString().padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

export function formatLocalClock(date: Date = new Date()): string {
  const pad = (value: number, length: number = 2): string => value.toString().padStart(length, '0');
  return `[${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}.` +
    `${pad(date.getMilliseconds(), 3)}]`;
}