import test from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import { authMiddleware } from '../src/middleware/auth.js';

const SECRET = 'test-secret';
process.env.BF_JWT_SECRET = SECRET;

function makeReq(token) {
  return {
    headers: { authorization: `Bearer ${token}` },
    header: (h) => (h.toLowerCase() === 'authorization' ? `Bearer ${token}` : undefined),
    requestId: 'test',
    app: { locals: { env: { BF_JWT_SECRET: SECRET } } },
  };
}

function makeRes() {
  return {
    statusCode: null,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
}

test('accepts token with sub field (canonical BF-Server format)', () => {
  const token = jwt.sign({ sub: 'user-abc', role: 'staff', tokenVersion: 0 }, SECRET);
  const req = makeReq(token);
  const res = makeRes();
  let called = false;

  authMiddleware(req, res, () => {
    called = true;
  });

  assert.equal(called, true);
  assert.equal(req.user.id, 'user-abc');
  assert.equal(req.user.role, 'staff');
});

test('accepts legacy id field for transition', () => {
  const token = jwt.sign({ id: 'legacy-123', role: 'Admin', tokenVersion: 0 }, SECRET);
  const req = makeReq(token);
  const res = makeRes();
  let called = false;

  authMiddleware(req, res, () => {
    called = true;
  });

  assert.equal(called, true);
  assert.equal(req.user.id, 'legacy-123');
  assert.equal(req.user.role, 'admin');
});

test('rejects client role', () => {
  const token = jwt.sign({ sub: 'user-xyz', role: 'client', tokenVersion: 0 }, SECRET);
  const req = makeReq(token);
  const res = makeRes();
  let called = false;

  authMiddleware(req, res, () => {
    called = true;
  });

  assert.equal(called, false);
  assert.equal(res.statusCode, 401);
});

test('rejects missing token', () => {
  const req = {
    headers: {},
    header: () => undefined,
    requestId: 'test',
    app: { locals: { env: {} } },
  };
  const res = makeRes();
  let called = false;

  authMiddleware(req, res, () => {
    called = true;
  });

  assert.equal(called, false);
  assert.equal(res.statusCode, 401);
});
