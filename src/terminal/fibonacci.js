export function generateFibonacci(start, maxLen) {
  const seq = [BigInt(start), BigInt(start)];
  while (seq.length < maxLen) {
    const next = seq[seq.length - 1] + seq[seq.length - 2];
    seq.push(next);
  }
  return seq;
}
