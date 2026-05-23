export const BabelAPI = {
  ALPHABET: "abcdefghijklmnopqrstuvwxyz,._",
  BASE: 29n,
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
  let totalMatches = 0;
  const overlay = Array(BabelAPI.PAGE_LENGTH).fill(0);
  let foundInstances = [];

  // Simulate compute delay if requested
  if (computeSpeed > 0) {
    await new Promise(r => setTimeout(r, computeSpeed));
  }

  for (const word of uniqueWords) {
    if (word.length < 1) continue;
    
    let pos = fullText.indexOf(word);
    while (pos !== -1) {
      const prevChar = pos > 0 ? fullText[pos - 1] : '_';
      const nextChar = pos + word.length < fullText.length ? fullText[pos + word.length] : '_';
      
      const isSpaced = (prevChar === '_' || prevChar === '.' || prevChar === ',') && 
                       (nextChar === '_' || nextChar === '.' || nextChar === ',');
      const isValid = isSpaced || (word.length >= 3);

      if (isValid) {
        foundInstances.push({ word: word, start: pos, end: pos + word.length });
        for (let i = 0; i < word.length; i++) overlay[pos + i] = 1; // Mark as hit
        totalMatches++;
      }
      pos = fullText.indexOf(word, pos + 1);
    }
  }

  // Sort by position for proximity multiplier
  foundInstances.sort((a, b) => a.start - b.start);
  let sequenceStreak = 1;

  for (let i = 0; i < foundInstances.length; i++) {
    const current = foundInstances[i];
    let wordScore = current.word.length + 1; // 1 pt per char + 1 pt per valid word

    let distMult = 1;
    if (i > 0) {
      const prev = foundInstances[i-1];
      const dist = current.start - prev.end;
      
      // Proximity Multiplier: Up to x10 if very close
      if (dist >= 0 && dist < 100) {
        distMult = Math.max(1, 10 - Math.floor(dist/10)); 
      }

      // Sequence Multiplier: Check if it followed the prev word in the original source
      const prevSourceIdx = sourceWordsOrdered.indexOf(prev.word);
      if (prevSourceIdx !== -1 && prevSourceIdx + 1 < sourceWordsOrdered.length && sourceWordsOrdered[prevSourceIdx + 1] === current.word) {
        sequenceStreak++;
      } else {
        sequenceStreak = 1;
      }
    }

    score += (wordScore * distMult * sequenceStreak);
  }

  return { score, matches: foundInstances, overlay };
}
