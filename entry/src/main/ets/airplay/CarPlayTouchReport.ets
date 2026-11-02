import { PlistNode } from './BinaryPlist';

export interface CarPlayTouchContact {
  id: number;
  down: boolean;
  x: number;
  y: number;
}

export const DEFAULT_TOUCH_HID_UUID: string = '2a2a2a2a';

export interface TouchHidDevice {
  uuid: string;
  logicalMaxX: number;
  logicalMaxY: number;
}

interface HidPointerExtents {
  touchScreen: boolean;
  logicalMaxX?: number;
  logicalMaxY?: number;
}

export function extractCarPlayTouchReport(
  command: PlistNode,
  touchUuid: string = DEFAULT_TOUCH_HID_UUID
): Uint8Array | undefined {
  if (command.kind !== 'dictionary') {
    return undefined;
  }
  const type = command.get('type');
  const params = command.get('params');
  const fields = params?.kind === 'dictionary' ? params : command;
  const uuid = fields.get('uuid');
  const report = fields.get('hidReport');
  const commandUuid = normalizeHidUuid(uuid);
  if (type?.kind !== 'string' || type.stringValue !== 'hidSendReport' ||
    commandUuid !== normalizeHidUuidText(touchUuid) ||
    report?.kind !== 'data') {
    return undefined;
  }
  return report.dataValue;
}

export function parseHidPointerExtents(descriptor: Uint8Array): HidPointerExtents {
  const result: HidPointerExtents = { touchScreen: false };
  let usagePage = 0;
  let logicalMax = 0;
  let usages: number[] = [];
  let offset = 0;
  while (offset < descriptor.length) {
    const prefix = descriptor[offset];
    if (prefix === 0xfe) {
      offset += 3 + (descriptor[offset + 1] ?? 0);
      continue;
    }
    const sizeCode = prefix & 0x03;
    const size = sizeCode === 3 ? 4 : sizeCode;
    const itemType = (prefix >> 2) & 0x03;
    const tag = prefix >> 4;
    let value = 0;
    for (let index = 0; index < size; index++) {
      value += (descriptor[offset + 1 + index] ?? 0) * Math.pow(256, index);
    }
    offset += 1 + size;
    if (itemType === 1 && tag === 0) {
      usagePage = value;
    } else if (itemType === 1 && tag === 2) {
      logicalMax = value;
    } else if (itemType === 2 && tag === 0) {
      const usage = size === 4 ? value : usagePage * 0x10000 + value;
      usages.push(usage);
      if (usage === 0x0d0004) {
        result.touchScreen = true;
      }
    } else if (itemType === 0) {
      if (tag === 8) {
        for (const usage of usages) {
          if (usage === 0x010030) {
            result.logicalMaxX = logicalMax;
          } else if (usage === 0x010031) {
            result.logicalMaxY = logicalMax;
          }
        }
      }
      usages = [];
    }
  }
  return result;
}

export function findTouchHidDevice(info: PlistNode, displayUuid: string): TouchHidDevice | undefined {
  const devices = info.get('hidDevices');
  if (!devices || devices.kind !== 'array') {
    return undefined;
  }
  for (const device of devices.arrayValue) {
    if (device.kind !== 'dictionary') {
      continue;
    }
    const uuid = device.get('uuid');
    const descriptor = device.get('hidDescriptor');
    const deviceDisplay = device.get('displayUUID');
    const normalizedUuid = normalizeHidUuid(uuid);
    if (!normalizedUuid || descriptor?.kind !== 'data' ||
      (deviceDisplay?.kind === 'string' && deviceDisplay.stringValue !== displayUuid)) {
      continue;
    }
    const extents = parseHidPointerExtents(descriptor.dataValue);
    if (extents.touchScreen && extents.logicalMaxX && extents.logicalMaxY) {
      return { uuid: normalizedUuid, logicalMaxX: extents.logicalMaxX, logicalMaxY: extents.logicalMaxY };
    }
  }
  return undefined;
}

function normalizeHidUuid(node: PlistNode | undefined): string | undefined {
  if (node?.kind === 'string') {
    return normalizeHidUuidText(node.stringValue);
  }
  if (node?.kind === 'integer' && node.integerValue >= BigInt(0)) {
    return node.integerValue.toString(16);
  }
  return undefined;
}

function normalizeHidUuidText(value: string): string {
  const normalized = value.trim().toLowerCase();
  return normalized.startsWith('0x') ? normalized.slice(2) : normalized;
}

export function scaleCarPlayTouchReport(
  report: Uint8Array,
  device: TouchHidDevice,
  width: number,
  height: number
): Uint8Array {
  const scaled = report.slice();
  const offsets: number[] = report.length === 5 ? [1] : report.length === 12 ? [2, 8] : [];
  const scale = (value: number, maximum: number, size: number): number =>
    Math.min(size - 1, Math.max(0, Math.round(value * (size - 1) / Math.max(1, maximum))));
  for (const offset of offsets) {
    const x = scale(report[offset] | (report[offset + 1] << 8), device.logicalMaxX, width);
    const y = scale(report[offset + 2] | (report[offset + 3] << 8), device.logicalMaxY, height);
    scaled[offset] = x & 0xff;
    scaled[offset + 1] = (x >> 8) & 0xff;
    scaled[offset + 2] = y & 0xff;
    scaled[offset + 3] = (y >> 8) & 0xff;
  }
  return scaled;
}

export function parseCarPlayTouchReport(report: Uint8Array): CarPlayTouchContact[] | undefined {
  if (report.length === 5) {
    return [{
      id: 0,
      down: (report[0] & 1) !== 0,
      x: report[1] | (report[2] << 8),
      y: report[3] | (report[4] << 8)
    }];
  }
  if (report.length !== 12) {
    return undefined;
  }
  const contacts: CarPlayTouchContact[] = [];
  for (let slot = 0; slot < 2; slot++) {
    const offset = slot * 6;
    if (report[offset] !== slot || (report[offset + 1] & 0xfe) !== 0) {
      return undefined;
    }
    contacts.push({
      id: slot,
      down: (report[offset + 1] & 1) !== 0,
      x: report[offset + 2] | (report[offset + 3] << 8),
      y: report[offset + 4] | (report[offset + 5] << 8)
    });
  }
  return contacts;
}