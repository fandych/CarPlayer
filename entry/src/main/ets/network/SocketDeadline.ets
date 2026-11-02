export function settleSocketWithin<T>(operation: Promise<T>, timeoutMs: number, message: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout((): void => reject(new Error(message)), timeoutMs);
    operation.then((value: T): void => {
      clearTimeout(timer);
      resolve(value);
    }, (error: Error): void => {
      clearTimeout(timer);
      reject(error);
    });
  });
}