import jwt from 'jsonwebtoken';

const TOKEN_REGEX = /^Bearer\s+(.+)$/i;
const ALLOWED_ROLES = ['admin', 'staff'];

function authMiddleware(req, res, next) {
  const auth = req.headers.authorization;
  const token = auth && TOKEN_REGEX.test(auth) ? auth.match(TOKEN_REGEX)[1] : null;

  if (!token) {
    return res.status(401).json({ code: 'unauthorized', message: 'Authentication required', requestId: req.requestId });
  }

  try {
    const payload = jwt.verify(token, process.env.BF_JWT_SECRET || req.app?.locals?.env?.BF_JWT_SECRET);
    const userId = payload.sub || payload.id;
    const role = (payload.role || '').toLowerCase();

    if (!userId || !ALLOWED_ROLES.includes(role)) {
      throw new Error('invalid_payload');
    }

    req.user = { id: String(userId), role };

    const siloHeader = req.headers['x-silo'];
    if (typeof siloHeader === 'string' && ['BF', 'BI', 'SLF'].includes(siloHeader)) {
      req.silo = siloHeader;
    } else {
      req.silo = 'BF';
    }

    return next();
  } catch {
    return res.status(401).json({ code: 'unauthorized', message: 'Invalid token', requestId: req.requestId });
  }
}

export { authMiddleware };
