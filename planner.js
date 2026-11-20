const UINT256_BITS = 256;
const BITS_PER_BYTE = 8;
const UINT256_MAX = (1n << BigInt(UINT256_BITS)) - 1n;

function parseDomainMax(input) {
  const value = input.trim().replaceAll('_', '');
  const hex = /^0x([0-9a-f]+)$/i.exec(value);
  if (hex) {
    const digits = hex[1].replace(/^0+/, '') || '0';
    return digits.length <= UINT256_MAX.toString(16).length ? BigInt('0x' + digits) : null;
  }

  const decimal = /^(\d+)(?:e(\d+))?$/i.exec(value);
  if (!decimal) return null;

  const digits = decimal[1].replace(/^0+/, '');
  if (!digits) return 0n;

  const exponent = Number(decimal[2] ?? 0);
  if (digits.length + exponent > UINT256_MAX.toString().length) return null;
  return BigInt(digits + '0'.repeat(exponent));
}

function bitLength(value) {
  return value.toString(2).length;
}

function solidityWidth(bits) {
  return Math.ceil(bits / BITS_PER_BYTE) * BITS_PER_BYTE;
}

function planQuantization(domainMaxInput, discardedBitWidthInput) {
  const domainMax = parseDomainMax(domainMaxInput);
  if (domainMax === null || domainMax === 0n || domainMax > UINT256_MAX) {
    return { invalidInput: 'domainMax', error: 'Enter a positive uint256 domain maximum.' };
  }

  const width = discardedBitWidthInput.trim();
  const d = Number(width);
  if (!/^\d+$/.test(width) || d >= UINT256_BITS) {
    return { invalidInput: 'discardedBitWidth', error: 'Enter a whole number from 0 to ' + (UINT256_BITS - 1) + '.' };
  }

  const rawBits = bitLength(domainMax);
  const nativeBits = solidityWidth(rawBits);
  const step = 1n << BigInt(d);
  const domain = { domainMax, rawBits, nativeBits, d, step };

  if (d === 0) {
    const actualMax = (1n << BigInt(nativeBits)) - 1n;
    return { ...domain, identity: true, actualMax, maxError: 0n };
  }

  const requiredCoefficient = (domainMax + step - 1n) / step;
  const e = Math.min(bitLength(requiredCoefficient), UINT256_BITS - d);
  const actualMax = ((1n << BigInt(e)) - 1n) * step;
  if (domainMax > actualMax) {
    return { error: 'The requested step cannot cover this domain. Use fewer discarded bits.' };
  }

  const maxError = domainMax < step ? domainMax : step - 1n;
  return { ...domain, e, actualMax, uintBits: solidityWidth(e), maxError };
}

if (typeof module !== 'undefined') module.exports = { planQuantization };
