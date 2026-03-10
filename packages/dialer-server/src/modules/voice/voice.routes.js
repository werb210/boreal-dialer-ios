import express from 'express';

function createVoiceRouter(opts) {
  const { makeError, requireVoiceEnabled, voiceSessionsRepo, findAssignedStaffId } = opts;
  const router = express.Router();

  router.post('/call', requireVoiceEnabled, async (req, res, next) => {
    if (req.body?.fromIdentity || req.body?.toClientId) return next();
    const role = String(req.user?.role || '').toLowerCase();
    if (!['staff', 'admin'].includes(role)) return makeError(res, req, 403, 'forbidden', 'forbidden');

    const clientId = req.body?.clientId || req.body?.toClientId;
    if (!clientId) return makeError(res, req, 400, 'bad_request', 'clientId is required');

    const assignedStaffId = (await findAssignedStaffId(clientId)) || req.user.id;
    const callSession = await voiceSessionsRepo.create({
      clientId,
      assignedStaffId,
      fromIdentity: `client:${clientId}`,
    });

    return res.status(200).json({
      callId: callSession.id,
      ringTargets: [],
      callSession,
      requestId: req.requestId,
    });
  });

  return router;
}

export default createVoiceRouter;
