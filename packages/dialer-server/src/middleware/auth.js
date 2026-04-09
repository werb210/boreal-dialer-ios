import jwt from 'jsonwebtoken';

const TOKEN_REGEX = /^Bearer\s+(.+)$/i;

function authMiddleware(req, res, next) {
  const auth = req.headers.authorization;
  const token = auth && TOKEN_REGEX.test(auth) ? auth.match(TOKEN_REGEX)[1] : null;

  if (!token) {
    return res.status(401).json({ code: 'unauthorized', message: 'Authentication required', requestId: req.requestId });
  }

  try {
    const payload = jwt.verify(token, process.env.BF_JWT_SECRET || req.app?.locals?.env?.BF_JWT_SECRET);
    if (!payload?.id || !['admin', 'staff', 'Admin', 'Staff', 'client'].includes(payload.role)) {
      throw new Error('invalid_payload');
    }
    req.user = { id: String(payload.id), role: payload.role };
    return next();
  } catch {
    return res.status(401).json({ code: 'unauthorized', message: 'Invalid token', requestId: req.requestId });
  }
}

export { authMiddleware };
