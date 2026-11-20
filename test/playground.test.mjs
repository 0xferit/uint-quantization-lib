import assert from 'node:assert/strict';
import { test } from 'node:test';
import planner from '../planner.js';

const { planQuantization } = planner;
const uint256Max = 2n ** 256n - 1n;

test('a cap just beyond the last bucket start needs one more encoded bit', () => {
  const aligned = planQuantization('65280', '8');
  assert.equal(aligned.e, 8);
  assert.equal(aligned.actualMax, 65280n);

  const crossing = planQuantization('65535', '8');
  assert.equal(crossing.e, 9);
  assert.ok(crossing.actualMax >= 65535n);
  assert.equal(crossing.uintBits, crossing.nativeBits);
});

test('derives the encoded width before rounding to a byte-sized storage type', () => {
  const plan = planQuantization('1e3', '2');
  assert.equal(plan.e, 8);
  assert.equal(plan.nativeBits - plan.uintBits, 8);
  assert.equal(plan.maxError, 3n);
});

test('validates the full discarded width before shifting', () => {
  for (const width of ['8.5', '8e1', '-1', '256', '10000000000000000000000000000', '']) {
    const plan = planQuantization('1000', width);
    assert.equal(plan.invalidInput, 'discardedBitWidth', width);
  }
});

test('rejects an invalid domain before deriving a scheme', () => {
  for (const cap of ['0', '1.5', '1e1000000000000000000000000000000', (uint256Max + 1n).toString()]) {
    assert.equal(planQuantization(cap, '8').invalidInput, 'domainMax', cap);
  }
});

test('keeps the entire uint256 range with the native identity', () => {
  const plan = planQuantization(uint256Max.toString(), '0');
  assert.equal(plan.identity, true);
  assert.equal(plan.nativeBits, 256);
  assert.equal(plan.actualMax, uint256Max);
  assert.equal(plan.maxError, 0n);
  assert.equal(plan.e, undefined);
});

test('handles the largest shift and rejects a cap outside that scheme', () => {
  const halfRange = 2n ** 255n;
  const plan = planQuantization(halfRange.toString(), '255');
  assert.equal(plan.e, 1);
  assert.equal(plan.actualMax, halfRange);

  const impossible = planQuantization((halfRange + 1n).toString(), '255');
  assert.match(impossible.error, /cannot cover/i);
  assert.equal(impossible.e, undefined);
});

test('caps floor loss at the domain maximum when the requested step is larger', () => {
  const plan = planQuantization('0xf', '12');
  assert.equal(plan.e, 1);
  assert.equal(plan.maxError, 15n);
});
