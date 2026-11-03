import assert from 'node:assert/strict';
import { test } from 'node:test';
import { checkAccountDeletion } from './account-deletion.ts';

test('a pending deletion blocks checkout even while Auth still verifies', async () => {
  assert.equal(await checkAccountDeletion(async () => ({ data: { userId: 'verified-user' }, error: null })), 'deleting');
});
test('an active account can proceed only after a successful lookup', async () => {
  assert.equal(await checkAccountDeletion(async () => ({ data: null, error: null })), 'active');
});
test('a missing table or denied lookup fails closed', async () => {
  assert.equal(await checkAccountDeletion(async () => ({ data: null, error: new Error('denied') })), 'unavailable');
});
test('a network outage also fails closed', async () => {
  assert.equal(await checkAccountDeletion(async () => { throw new Error('offline'); }), 'unavailable');
});
