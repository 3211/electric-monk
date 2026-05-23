export const BabelAPI = {
  ALPHABET: "abcdefghijklmnopqrstuvwxyz ',._-1234567890=+()!:;\"",
  BASE: 51n,
  PAGE_LENGTH: 3200, // 40 rows * 80 cols
  MODULUS: null,
  MULTIPLIER: null,
  INCREMENT: null,
  MOD_INVERSE: null,

  init() {
    this.MODULUS = this.BASE ** BigInt(this.PAGE_LENGTH);
    let rawMulti = 123456789012345678912345678901234567891n % this.MODULUS;
    if (rawMulti % this.BASE === 0n) rawMulti += 1n;
    this.MULTIPLIER = rawMulti;
    this.INCREMENT = 987654321098765432109876543210987654321n % this.MODULUS;
    
    let m0 = this.MODULUS, a = this.MULTIPLIER, m = this.MODULUS;
    let x0 = 0n, x1 = 1n, q, t;
    while (a > 1n) {
      q = a / m; t = m; m = a % m; a = t;
      t = x0; x0 = x1 - q * x0; x1 = t;
    }
    if (x1 < 0n) x1 += m0;
    this.MOD_INVERSE = x1;
  },

  addressToText(address) {
    if (!this.MODULUS) this.init();
    const addrInt = BigInt(address);
    let rawId = (addrInt - this.INCREMENT) % this.MODULUS;
    if (rawId < 0n) rawId += this.MODULUS;
    rawId = (rawId * this.MOD_INVERSE) % this.MODULUS;

    let temp = rawId;
    let chars = [];
    for (let i = 0; i < this.PAGE_LENGTH; i++) {
      chars.push(this.ALPHABET[Number(temp % this.BASE)]);
      temp /= this.BASE;
    }
    return chars.reverse().join('');
  },

  textToAddress(text) {
    if (!this.MODULUS) this.init();
    let num = 0n;
    for (let i = 0; i < text.length; i++) {
      num = num * this.BASE + BigInt(this.ALPHABET.indexOf(text[i]));
    }
    return (num * this.MULTIPLIER + this.INCREMENT) % this.MODULUS;
  }
};

/**
 * Score a decrypted text against a reference text (like the Bible).
 * 
 * @param {string} fullText - The 3200-char string from BabelAPI
 * @param {string[]} uniqueWords - Array of unique words from the reference text
 * @param {string[]} sourceWordsOrdered - Array of all words in order from the reference text
 * @param {number} computeSpeed - Delay in ms per chunk (for animation tracking, optional)
 * @returns {Promise<{score: number, matches: Array<{word, start, end}>, overlay: number[]}>}
 */
export async function scoreDecryptedText(fullText, uniqueWords, sourceWordsOrdered, computeSpeed = 0) {
  let score = 0;
  const overlay = Array(BabelAPI.PAGE_LENGTH).fill(0);
  let rawInstances = [];

  // Simulate compute delay if requested
  if (computeSpeed > 0) {
    await new Promise(r => setTimeout(r, computeSpeed));
  }

  for (const word of uniqueWords) {
    if (word.length < 1) continue;
    
    let pos = fullText.indexOf(word);
    while (pos !== -1) {
      const prevChar = pos > 0 ? fullText[pos - 1] : ' ';
      const nextChar = pos + word.length < fullText.length ? fullText[pos + word.length] : ' ';
      
      const isBoundary = (ch) => !/[a-z'-]/.test(ch);
      const isSpaced = isBoundary(prevChar) && isBoundary(nextChar);
      
      // If it's a short word, it MUST be spaced to even be considered
      const isValid = word.length >= 4 || isSpaced;

      if (isValid) {
        rawInstances.push({ word: word, start: pos, end: pos + word.length });
      }
      pos = fullText.indexOf(word, pos + 1);
    }
  }

  // Sort by position
  rawInstances.sort((a, b) => a.start - b.start);

  // Coherence Filter & Sequence Analysis
  let finalMatches = [];
  let sequenceStreak = 1;

  for (let i = 0; i < rawInstances.length; i++) {
    const current = rawInstances[i];
    let isCoherent = current.word.length >= 4; // Long words are inherently coherent
    let distMult = 1;
    let seqBonus = 1;

    if (i > 0) {
      const prev = rawInstances[i-1];
      const dist = current.start - prev.end;
      
      // Proximity check
      if (dist >= 0 && dist < 100) {
        distMult = Math.max(1, 10 - Math.floor(dist/10));
      }

      // Sequence check (Check if current word follows prev word in source text)
      // We look for any instance in the source where current word follows prev word
      let isFollower = false;
      let searchIdx = sourceWordsOrdered.indexOf(prev.word);
      while (searchIdx !== -1 && searchIdx + 1 < sourceWordsOrdered.length) {
        if (sourceWordsOrdered[searchIdx + 1] === current.word) {
          isFollower = true;
          break;
        }
        searchIdx = sourceWordsOrdered.indexOf(prev.word, searchIdx + 1);
      }

      if (isFollower) {
        sequenceStreak++;
        seqBonus = sequenceStreak;
        isCoherent = true; // Short word becomes coherent if part of a sequence
        
        // Retrospectively mark the previous word as coherent if it was short
        if (prev.word.length < 4 && !finalMatches.includes(prev)) {
           finalMatches.push(prev);
           for (let j = prev.start; j < prev.end; j++) overlay[j] = 1;
        }
      } else {
        sequenceStreak = 1;
      }
    }

    if (isCoherent) {
      finalMatches.push(current);
      for (let j = current.start; j < current.end; j++) overlay[j] = 1;
      
      let wordScore = current.word.length + 1;
      score += (wordScore * distMult * seqBonus);
    }
  }

  return { score, matches: finalMatches, overlay };
}
