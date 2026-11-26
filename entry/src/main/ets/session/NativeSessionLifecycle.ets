const MAX_GENERATION: string = '18446744073709551615';
let currentGeneration: string = '0';

export function advanceSessionGeneration(): string {
  if (currentGeneration === MAX_GENERATION) {
    throw new Error('Unable to advance session generation');
  }
  const digits = currentGeneration.split('');
  for (let index = digits.length - 1; index >= 0; index--) {
    const digit = digits[index].charCodeAt(0) - 48;
    if (digit < 9) {
      digits[index] = (digit + 1).toString();
      currentGeneration = digits.join('');
      return currentGeneration;
    }
    digits[index] = '0';
  }
  currentGeneration = `1${digits.join('')}`;
  return currentGeneration;
}

export function isCurrentSessionGeneration(generation: string): boolean {
  if (typeof generation !== 'string' || !/^[1-9][0-9]*$/.test(generation) ||
    generation.length > MAX_GENERATION.length ||
    (generation.length === MAX_GENERATION.length && generation > MAX_GENERATION)) {
    throw new Error('Invalid session generation token');
  }
  return generation === currentGeneration;
}
